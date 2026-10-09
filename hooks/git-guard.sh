#!/bin/bash
# git-guard — PreToolUse hook for the Bash tool.
#
# Deterministically blocks the git patterns that the git-superpowers safety
# rules forbid, so safety does not depend on the model remembering prose:
#
#   1. git add . / -A / --all / :/ / *    → stage specific files instead
#   2. --no-verify (and commit -n, incl. combined -an/-nm) on any git command
#   3. bare force push (--force, -f, combined -uf, +refspec) → --force-with-lease
#   4. force push / --delete / :ref / --mirror against a protected branch
#      (main, master, develop, dev, staging, production, release/*) — judged
#      by the REFSPEC, never by the remote name
#   5. --force-with-lease WITHOUT an explicit branch while the current branch is
#      protected (or cannot be determined) → name the branch explicitly
#
# Blocking = exit 2 with the reason on stderr (shown to Claude, which adjusts).
# Anything unparseable fails OPEN (exit 0) — a broken guard must never break
# the session. Escape hatch for deliberate exceptions, run by the USER only:
#   GIT_SUPERPOWERS_UNSAFE=1 <command>
#
# How it works: the hook JSON is parsed with python3 (json + a small shell-like
# tokenizer: quotes, escapes, ; & | newline ( ) ` $( ) heredocs, comments).
# Each simple command is normalized (env assignments / env / sudo / command /
# time / nohup stripped, `bash -c "…"` and `eval "…"` recursed into, git global
# options like -C/-c/--no-pager skipped) and then checked on real tokens, so
# text inside quoted strings (commit messages, echo) is data, not a command.
# Without python3 the guard cannot run and fails open with a warning.
#
# Known limits (by design — this is not a full shell): commands built via
# variables, aliases, functions, xargs or scripts are not caught. The guard is
# a seatbelt, not a jail. Text printed by `echo "git push -f"` is allowed.

set -u

[ "${GIT_SUPERPOWERS_UNSAFE:-0}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

if ! command -v python3 >/dev/null 2>&1; then
  echo "git-guard: python3 not found — guard inactive (fail open)." >&2
  exit 0
fi

read -r -d '' PYCODE <<'PYEOF'
import json, os, re, subprocess, sys

PROTECTED = re.compile(r'(main|master|develop|dev|staging|production|release(/.*)?)')
WRAPPERS = {'env', 'sudo', 'command', 'time', 'nohup', 'exec', 'builtin', 'doas'}
KEYWORDS = {'{', '}', '!', 'if', 'then', 'else', 'elif', 'fi', 'do', 'done',
            'while', 'until', 'for', 'case', 'esac', 'in'}
SHELLS = {'bash', 'sh', 'zsh', 'dash', 'ksh'}
# git global options that consume the next token
GLOBAL_ARG = {'-C', '-c', '--git-dir', '--work-tree', '--namespace',
              '--super-prefix', '--config-env', '--exec-path'}
COMMIT_ARG_LONG = {'--message', '--file', '--author', '--date', '--template',
                   '--reuse-message', '--reedit-message', '--fixup', '--squash',
                   '--cleanup', '--trailer', '--gpg-sign', '--pathspec-from-file'}
PUSH_ARG_LONG = {'--repo', '--push-option', '--receive-pack', '--exec'}


class Block(Exception):
    def __init__(self, msg, alt):
        self.msg, self.alt = msg, alt


def strip_heredocs(text):
    out, delim = [], None
    for line in text.split('\n'):
        if delim is not None:
            if line.strip() == delim:
                delim = None
            continue
        m = re.search(r'<<-?\s*["\']?([A-Za-z_][A-Za-z0-9_]*)["\']?', line)
        if m and '<<<' not in line:
            delim = m.group(1)
        out.append(line)
    return '\n'.join(out)


def match_paren(s, i):
    """s[i] is just after '$('; return index of the matching ')' (or len)."""
    depth = 1
    while i < len(s):
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(s)


def tokenize(text, nested):
    """Return list of simple commands (token lists); nested command strings
    found inside double quotes ($(…), backticks) are appended to `nested`."""
    segs, cur, word, have = [], [], [], False
    i, n = 0, len(text)

    def flush():
        nonlocal word, have
        if have:
            cur.append(''.join(word))
        word, have = [], False

    def end_seg():
        nonlocal cur
        flush()
        if cur:
            segs.append(cur)
        cur = []

    while i < n:
        c = text[i]
        if c == '\\' and i + 1 < n:
            if text[i + 1] != '\n':
                word.append(text[i + 1]); have = True
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            word.append(text[i + 1:j]); have = True
            i = j + 1
        elif c == '"':
            have = True
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\' and i + 1 < n:
                    word.append(text[i + 1]); i += 2
                elif text[i] == '$' and text[i + 1:i + 2] == '(':
                    j = match_paren(text, i + 2)
                    nested.append(text[i + 2:j])
                    word.append(text[i:j + 1]); i = j + 1
                elif text[i] == '`':
                    j = text.find('`', i + 1)
                    j = n if j < 0 else j
                    nested.append(text[i + 1:j])
                    word.append(text[i:j + 1]); i = j + 1
                else:
                    word.append(text[i]); i += 1
            i += 1
        elif c in ';&|\n()`':
            end_seg(); i += 1
        elif c in ' \t':
            flush(); i += 1
        elif c == '#' and not have:
            while i < n and text[i] != '\n':
                i += 1
        else:
            word.append(c); have = True; i += 1
    end_seg()
    return segs


def is_cluster(tok):
    return len(tok) > 1 and tok[0] == '-' and tok[1] != '-' and tok[1:].isalpha()


def unwrap(toks):
    """Strip env assignments / wrappers / leading keywords. Returns
    (tokens, recursed_command_strings)."""
    extra = []
    while toks:
        t = toks[0]
        if t in KEYWORDS or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t):
            toks = toks[1:]
        elif os.path.basename(t) in WRAPPERS:
            w = os.path.basename(t)
            toks = toks[1:]
            while toks and (toks[0].startswith('-') or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', toks[0])):
                if toks[0] in ('-u', '-g', '-C', '-h', '-p') and w in ('sudo', 'env', 'doas') and len(toks) > 1:
                    toks = toks[2:]
                else:
                    toks = toks[1:]
        else:
            break
    if toks:
        b = os.path.basename(toks[0])
        if b in SHELLS and '-c' in toks[1:]:
            k = toks.index('-c')
            if k + 1 < len(toks):
                extra.append(toks[k + 1])
        elif b == 'eval':
            extra.append(' '.join(toks[1:]))
    return toks, extra


def current_branch(cwd):
    try:
        r = subprocess.run(['git', '-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD'],
                           capture_output=True, text=True, timeout=5)
        b = r.stdout.strip()
        if r.returncode == 0 and b and b != 'HEAD':
            return b
    except Exception:
        pass
    return None


def norm_ref(r):
    r = r.lstrip('+')
    if r.startswith('refs/heads/'):
        r = r[len('refs/heads/'):]
    return r


def check_add(args):
    for a in args:
        if a in ('--all', '.', ':/', '*', ':(top)') or (is_cluster(a) and 'A' in a):
            raise Block("'git add %s' stages everything blindly." % a,
                        "always stage specific files: git add <file> <file>")


def check_commit(args):
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a == '--':
            break
        if a == '--no-verify':
            raise Block("'--no-verify' bypasses the repo's hooks.",
                        "fix the hook failure instead; only the user may bypass hooks manually")
        if a.startswith('--'):
            if a in COMMIT_ARG_LONG:
                skip = True
        elif is_cluster(a):
            for idx, ch in enumerate(a[1:]):
                if ch == 'n':
                    raise Block("'git commit -n' is short for --no-verify and bypasses the repo's hooks.",
                                "fix the hook failure instead; only the user may bypass hooks manually")
                if ch in 'mFCctSu':
                    skip = (idx == len(a) - 2)
                    break


def check_push(args, cwd):
    force = lease = delete = False
    pos, skip, dashdash = [], False, False
    for a in args:
        if skip:
            skip = False
            continue
        if dashdash or not a.startswith('-') or a == '-':
            pos.append(a)
        elif a == '--':
            dashdash = True
        elif a == '--no-verify':
            raise Block("'--no-verify' bypasses the repo's hooks.",
                        "fix the hook failure instead; only the user may bypass hooks manually")
        elif a == '--mirror':
            raise Block("'git push --mirror' overwrites/deletes remote refs wholesale.",
                        "push the specific branch: git push origin <branch>")
        elif a == '--force':
            force = True
        elif a == '--delete':
            delete = True
        elif a.startswith('--force-with-lease') or a.startswith('--force-if-includes'):
            lease = True
        elif a.startswith('--'):
            if a in PUSH_ARG_LONG:
                skip = True
        elif is_cluster(a):
            for idx, ch in enumerate(a[1:]):
                if ch == 'f':
                    force = True
                elif ch == 'd':
                    delete = True
                elif ch == 'o':
                    skip = (idx == len(a) - 2)
                    break
    remote = pos[0] if pos else None
    refspecs = pos[1:]
    plus = any(r.startswith('+') for r in refspecs)

    if (force and not lease) or plus:
        raise Block("bare force push ('--force' / '-f' / '+refspec') can overwrite teammates' work.",
                    "use: git push --force-with-lease --force-if-includes origin <feature-branch>")

    # Destination branches of every refspec (judged by refspec, never by remote)
    dests, implicit = [], not refspecs
    for r in refspecs:
        r = r.lstrip('+')
        if delete:
            dst = r
        elif ':' in r:
            src, dst = r.rsplit(':', 1)
            if src == '':
                dests.append((norm_ref(dst), True))
                continue
        else:
            dst = r
        dests.append((norm_ref(dst), delete))
    need_branch = lease and (implicit or any(d == 'HEAD' for d, _ in dests))
    if need_branch:
        cur = current_branch(cwd)
        if cur is None:
            raise Block("--force-with-lease without an explicit branch, and the current branch could not be determined.",
                        "name the branch explicitly: git push --force-with-lease origin <feature-branch>")
        dests = [(cur if d == 'HEAD' else d, dl) for d, dl in dests]
        if implicit:
            dests.append((cur, False))
        if PROTECTED.fullmatch(cur):
            raise Block("--force-with-lease without an explicit branch while on protected branch '%s'." % cur,
                        "protected branches are never rewritten; use git revert, or name a feature branch explicitly")
    for d, dl in dests:
        if not PROTECTED.fullmatch(d):
            continue
        if dl:
            raise Block("deleting protected branch '%s' on the remote." % d,
                        "protected branches are never deleted by Claude; ask the user to do it in the hosting UI")
        if lease:
            raise Block("force-pushing protected branch '%s' (main/master/develop/dev/staging/production/release/*)." % d,
                        "protected branches are never rewritten; use git revert instead")


def check_simple(toks, cwd, depth=0):
    toks, extra = unwrap(toks)
    for e in extra:
        if depth < 4:
            check_command(e, cwd, depth + 1)
    if not toks or os.path.basename(toks[0]) != 'git':
        return
    i = 1
    while i < len(toks) and toks[i].startswith('-'):
        t = toks[i]
        if t == '-C' and i + 1 < len(toks):
            nd = toks[i + 1]
            cwd = nd if os.path.isabs(nd) else os.path.join(cwd, nd)
        if t in GLOBAL_ARG and '=' not in t:
            i += 1
        i += 1
    if i >= len(toks):
        return
    sub, args = toks[i], toks[i + 1:]
    if '--no-verify' in args and sub not in ('commit', 'push'):
        raise Block("'--no-verify' bypasses the repo's hooks.",
                    "fix the hook failure instead; only the user may bypass hooks manually")
    if sub == 'add':
        check_add(args)
    elif sub == 'commit':
        check_commit(args)
    elif sub == 'push':
        check_push(args, cwd)


def check_command(text, cwd, depth=0):
    nested = []
    for toks in tokenize(strip_heredocs(text), nested):
        check_simple(toks, cwd, depth)
    for n in nested:
        if depth < 4:
            check_command(n, cwd, depth + 1)


def main():
    try:
        data = json.load(sys.stdin)
        cmd = data.get('tool_input', {}).get('command', '') or ''
        cwd = data.get('cwd') or os.getcwd()
    except Exception:
        return 0
    if 'git' not in cmd:
        return 0
    try:
        check_command(cmd, cwd)
    except Block as b:
        sys.stderr.write("git-guard blocked this command: %s\n" % b.msg)
        sys.stderr.write("Safe alternative: %s\n" % b.alt)
        sys.stderr.write("Rule source: git-superpowers references/git-safety.md\n")
        return 2
    except Exception:
        return 0  # unparseable -> fail open
    return 0


sys.exit(main())
PYEOF

printf '%s' "$INPUT" | python3 -c "$PYCODE"
exit $?
