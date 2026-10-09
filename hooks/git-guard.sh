#!/bin/bash
# git-guard — PreToolUse hook for the Bash tool.
#
# Deterministically blocks the git patterns that the git-superpowers safety
# rules forbid, so safety does not depend on the model remembering prose:
#
#   1. git add . / -A / --all / :/ / * / ** / ./   → stage specific files instead
#   2. --no-verify (and commit -n, incl. combined -an/-nm, `-c core.hooksPath=`)
#   3. bare force push (--force, -f, combined -uf, +refspec) → --force-with-lease
#   4. force push / --delete / :ref / --mirror against a protected branch
#      (main, master, develop, dev, staging, production, release/*) — judged
#      by the REFSPEC (HEAD / @ / HEAD~0 are resolved), never by the remote name
#   5. --force-with-lease WITHOUT an explicit branch while the current branch is
#      protected (or cannot be determined) → name the branch explicitly
#   6. --force-with-lease combined with --all / --branches / wildcard or bare ':'
#      refspecs, and --prune without an explicit refspec (can delete remote main)
#
# THREAT MODEL: this guard prevents ACCIDENTAL dangerous commands by an
# assistant. It is a seatbelt, not a security boundary against deliberate
# evasion: variables, aliases/functions defined elsewhere, scripts and
# anything else that builds a command at run time are out of reach.
#
# Blocking = exit 2 with the reason on stderr (shown to Claude, which adjusts).
# Anything unparseable fails OPEN (exit 0) — a broken guard must never break
# the session. Escape hatch for deliberate exceptions, run by the USER only:
#   GIT_SUPERPOWERS_UNSAFE=1 <command>
#
# How it works: the hook JSON is parsed with python3 (json + a small shell-like
# tokenizer: quotes, $'…', escapes, brace lists, redirections, heredocs,
# ; & | newline ( ) ` $( ) and comments). Each simple command is normalized
# (env assignments and wrappers such as env/sudo/nice/timeout/xargs stripped,
# `bash -lc "…"`, `eval "…"` and heredocs fed to a shell recursed into, git
# global options like -C/-c/--no-pager skipped, abbreviated long options such
# as --force-w expanded) and then checked on real tokens, so text inside quoted
# strings (commit messages, echo) is data, not a command.
# Without python3 the guard cannot run and fails open with a warning.
# Text printed by `echo "git push -f"` is allowed.

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
ASSIGN = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')
KEYWORDS = {'{', '}', '!', 'if', 'then', 'else', 'elif', 'fi', 'do', 'done',
            'while', 'until', 'for', 'case', 'esac', 'in'}
SHELLS = {'bash', 'sh', 'zsh', 'dash', 'ksh'}
STDIN_RUNNERS = {'eval', 'source', '.'}
# wrapper -> (options that take a separate argument, positional args to skip)
WRAPPERS = {
    'env': ({'-u', '--unset', '-C', '--chdir', '-S', '--split-string'}, 0),
    'sudo': ({'-u', '-g', '-C', '-h', '-p', '-r', '-t', '-U', '-D', '--user', '--group', '--prompt'}, 0),
    'doas': ({'-u', '-C'}, 0),
    'command': (set(), 0), 'builtin': (set(), 0), 'nohup': (set(), 0),
    'exec': ({'-a'}, 0),
    'time': ({'-f', '-o', '--format', '--output'}, 0),
    'nice': ({'-n', '--adjustment'}, 0),
    'timeout': ({'-s', '-k', '--signal', '--kill-after'}, 1),
    'stdbuf': ({'-i', '-o', '-e', '--input', '--output', '--error'}, 0),
    'caffeinate': ({'-t', '-w'}, 0),
    'ionice': ({'-c', '-n', '-p', '-P', '-u', '--class', '--classdata'}, 0),
    'chrt': (set(), 1),
    'xargs': ({'-I', '-L', '-n', '-P', '-s', '-d', '-E', '-a', '-J', '--max-args', '--max-procs',
               '--delimiter', '--arg-file', '--max-lines', '--replace'}, 0),
}
# git global options that consume the next token
GLOBAL_ARG = {'-C', '-c', '--git-dir', '--work-tree', '--namespace',
              '--super-prefix', '--config-env', '--exec-path'}
COMMIT_ARG_LONG = {'--message', '--file', '--author', '--date', '--template',
                   '--reuse-message', '--reedit-message', '--fixup', '--squash',
                   '--cleanup', '--trailer', '--gpg-sign', '--pathspec-from-file'}
PUSH_ARG_LONG = {'--repo', '--push-option', '--receive-pack', '--exec'}
ADD_ARG_LONG = {'--chmod', '--pathspec-from-file'}
# Long options per subcommand (git accepts any unique prefix of these)
LONG_OPTS = {
    'push': 'force force-with-lease force-if-includes delete mirror verify no-verify all branches '
            'prune tags follow-tags set-upstream dry-run verbose quiet repo porcelain atomic '
            'push-option signed recurse-submodules thin no-thin ipv4 ipv6 progress receive-pack '
            'exec no-force-with-lease'.split(),
    'commit': 'no-verify verify amend all message file no-edit edit author date signoff fixup squash '
              'reuse-message reedit-message allow-empty allow-empty-message dry-run patch interactive '
              'include only quiet verbose cleanup gpg-sign no-gpg-sign trailer pathspec-from-file '
              'branch short long porcelain null template status no-status untracked-files '
              'reset-author no-post-rewrite z'.split(),
    'add': 'all no-all ignore-removal update patch interactive force dry-run verbose intent-to-add '
           'refresh ignore-errors chmod pathspec-from-file pathspec-file-nul renormalize sparse edit '
           'ignore-missing'.split(),
}
ANSI_ESC = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'e': '\x1b', 'E': '\x1b',
            'f': '\f', 'v': '\v', '\\': '\\', "'": "'", '"': '"', '?': '?'}
# placeholders protecting quoted braces/commas from brace expansion
PH = str.maketrans('{},', '\x00\x01\x02')
UNPH = str.maketrans('\x00\x01\x02', '{},')
REDIR_OP = re.compile(r'&?(?:>>|>|<)[&|]?')

HOOK_BLOCK = ("'--no-verify' bypasses the repo's hooks.",
              "fix the hook failure instead; only the user may bypass hooks manually")


class Block(Exception):
    def __init__(self, msg, alt):
        self.msg, self.alt = msg, alt


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


def ansi_c(s):
    """Decode the body of $'…'."""
    def rep(m):
        g = m.group(1)
        try:
            if g[0] in 'xuU' and len(g) > 1:
                return chr(int(g[1:], 16))
            if g[0] in '01234567':
                return chr(int(g, 8))
        except ValueError:
            return ''
        return ANSI_ESC.get(g[0], '\\' + g)
    return re.sub(r'\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{1,4}|U[0-9a-fA-F]{1,8}|[0-7]{1,3}|.)',
                  rep, s, flags=re.S)


def brace_expand(w):
    """Expand simple comma lists {a,b}; leaves the word alone if it explodes."""
    m = re.search(r'\{([^{}]*,[^{}]*)\}', w)
    if not m:
        return [w]
    out = []
    for alt in m.group(1).split(','):
        out += brace_expand(w[:m.start()] + alt + w[m.end():])
        if len(out) > 64:
            return [w]
    return out


def scan_subst(body, nested):
    """Command substitutions executed inside an unquoted heredoc body."""
    for m in re.finditer(r'\$\(', body):
        nested.append(body[m.end():match_paren(body, m.end())])
    for m in re.finditer(r'`([^`]*)`', body):
        nested.append(m.group(1))


def tokenize(text, nested, heredocs):
    """Return a list of simple commands (token lists). Command strings found
    in $(…), backticks, <(…) are appended to `nested`; heredoc / here-string
    bodies are appended to `heredocs` as (command_token_list, body, quoted)."""
    segs, cur = [], []
    parts, have = [], False        # current word: [(text, quoted)]
    redir = None                   # None | ('skip',) | ('here', command_list)
    pending = []                   # heredocs waiting for their body at the next newline
    i, n = 0, len(text)

    def flush():
        nonlocal parts, have, redir
        if not have:
            return
        word = ''.join(s.translate(PH) if q else s for s, q in parts)
        parts, have = [], False
        if redir:
            if redir[0] == 'here':
                heredocs.append((redir[1], word.translate(UNPH), True))
            redir = None
            return
        words = brace_expand(word) if '{' in word and ',' in word else [word]
        cur.extend(w.translate(UNPH) for w in words)

    def end_seg():
        nonlocal cur, redir
        flush()
        redir = None
        if cur:
            segs.append(cur)
        cur = []

    def add(s, quoted):
        nonlocal have
        parts.append((s, quoted))
        have = True

    while i < n:
        c = text[i]
        nxt = text[i + 1:i + 2]
        if c == '\\' and i + 1 < n:
            if nxt != '\n':
                add(nxt, True)
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            add(text[i + 1:j], True)
            i = j + 1
        elif c == '$' and nxt == "'":
            j = i + 2
            while j < n and text[j] != "'":
                j += 2 if text[j] == '\\' else 1
            add(ansi_c(text[i + 2:j]), True)
            i = j + 1
        elif c == '$' and nxt == '"':
            i += 1                      # $"…" is an ordinary double-quoted string
        elif c == '$' and nxt == '{':
            j = text.find('}', i)
            j = n - 1 if j < 0 else j
            add(text[i:j + 1], True)    # ${…} is no brace list
            i = j + 1
        elif c == '"':
            buf = []
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\' and i + 1 < n:
                    buf.append(text[i + 1]); i += 2
                elif text[i] == '$' and text[i + 1:i + 2] == '(':
                    j = match_paren(text, i + 2)
                    nested.append(text[i + 2:j])
                    buf.append(text[i:j + 1]); i = j + 1
                elif text[i] == '`':
                    j = text.find('`', i + 1)
                    j = n if j < 0 else j
                    nested.append(text[i + 1:j])
                    buf.append(text[i:j + 1]); i = j + 1
                else:
                    buf.append(text[i]); i += 1
            add(''.join(buf), True)
            i += 1
        elif c in '<>' or (c == '&' and nxt == '>'):
            # a glued fd number ("2>") belongs to the operator, anything else ends the word
            if have and all(not q for _, q in parts) and ''.join(s for s, _ in parts).isdigit():
                parts, have = [], False
            else:
                flush()
            if text.startswith('<<<', i):
                redir = ('here', cur)
                i += 3
            elif text.startswith('<<', i):
                i += 2
                strip = text[i:i + 1] == '-'
                i += strip
                while i < n and text[i] in ' \t':
                    i += 1
                delim, quoted = [], False
                while i < n and text[i] not in ' \t\n;&|()<>':
                    ch = text[i]
                    if ch in '\'"':
                        j = text.find(ch, i + 1)
                        j = n if j < 0 else j
                        delim.append(text[i + 1:j]); quoted = True; i = j + 1
                    elif ch == '\\':
                        delim.append(text[i + 1:i + 2]); quoted = True; i += 2
                    else:
                        delim.append(ch); i += 1
                pending.append((''.join(delim), strip, quoted, cur))
            elif text[i + 1:i + 2] == '(' and c in '<>':
                j = match_paren(text, i + 2)    # process substitution <(…) / >(…)
                nested.append(text[i + 2:j])
                add('/dev/fd/63', True)
                i = j + 1
            else:
                i = REDIR_OP.match(text, i).end()
                redir = ('skip',)               # the next word is a redirect target
        elif c == '\n':
            end_seg()
            i += 1
            for delim, strip, quoted, cmd in pending:
                lines = []
                while i < n:
                    j = text.find('\n', i)
                    j = n if j < 0 else j
                    line = text[i:j]
                    i = j + 1
                    if (line.lstrip('\t') if strip else line) == delim:
                        break
                    lines.append(line)
                heredocs.append((cmd, '\n'.join(lines), quoted))
            pending = []
        elif c in ';&|()`':
            end_seg(); i += 1
        elif c in ' \t':
            flush(); i += 1
        elif c == '#' and not have:
            while i < n and text[i] != '\n':
                i += 1
        else:
            add(c, False); i += 1
    end_seg()
    return segs


def is_cluster(tok):
    return len(tok) > 1 and tok[0] == '-' and tok[1] != '-' and tok[1:].isalpha()


def shell_c_string(toks):
    """For `bash -lc "cmd"` style calls return the command string, else None."""
    k = 1
    while k < len(toks):
        a = toks[k]
        if a == '--':
            return None
        if a in ('-o', '+o', '-O', '+O'):
            k += 2
        elif a.startswith('--'):
            k += 1
        elif a[0] in '-+' and len(a) > 1 and a[1:].isalpha():
            if 'c' in a[1:]:
                return toks[k + 1] if k + 1 < len(toks) else None
            k += 1
        else:
            return None
    return None


def reads_stdin_as_commands(toks):
    """True if the (unwrapped) command executes its stdin / here-doc as shell code."""
    if not toks:
        return False
    b = os.path.basename(toks[0])
    if b in STDIN_RUNNERS:
        return True
    if b not in SHELLS or shell_c_string(toks) is not None:
        return False
    args, k = toks[1:], 0
    while k < len(args):
        if args[k] in ('-o', '+o', '-O', '+O'):
            k += 2
        elif args[k].startswith(('-', '+')):
            k += 1
        else:
            return False        # script file given: stdin is data for the script
    return True


def unwrap(toks):
    """Strip env assignments / wrappers / leading keywords. Returns
    (tokens, recursed_command_strings)."""
    extra = []
    while toks:
        t = toks[0]
        if t in KEYWORDS or ASSIGN.match(t):
            toks = toks[1:]
            continue
        w = os.path.basename(t)
        if w not in WRAPPERS:
            break
        argopts, npos = WRAPPERS[w]
        toks = toks[1:]
        while toks:
            o = toks[0]
            if o == '--':
                toks = toks[1:]
                break
            if ASSIGN.match(o):
                toks = toks[1:]
            elif o.startswith('-') and len(o) > 1:
                if o in argopts and len(toks) > 1:
                    if w == 'env' and o in ('-S', '--split-string'):
                        extra.append(toks[1])
                    toks = toks[2:]
                else:
                    toks = toks[1:]
            else:
                break
        toks = toks[npos:]
    if toks:
        b = os.path.basename(toks[0])
        if b in SHELLS:
            s = shell_c_string(toks)
            if s is not None:
                extra.append(s)
        elif b == 'eval':
            extra.append(' '.join(toks[1:]))
    return toks, extra


def expand_long(sub, a):
    """Expand an abbreviated long option (git accepts unique prefixes) to its
    full name, keeping any =value. Ambiguous/unknown prefixes stay as typed
    (git itself rejects the ambiguous ones)."""
    if not a.startswith('--') or a == '--':
        return a
    name, eq, val = a[2:].partition('=')
    opts = LONG_OPTS[sub]
    if name in opts:
        return a
    cands = {o for o in opts if o.startswith(name)}
    cands |= {'no-' + o for o in opts if not o.startswith('no-') and ('no-' + o).startswith(name)}
    if len(cands) == 1:
        return '--' + cands.pop() + eq + val
    return a


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


def resolve_branch(ref, cwd):
    """Local branch a symbolic ref (HEAD~0, main^0, @{u}…) points at, or None."""
    try:
        r = subprocess.run(['git', '-C', cwd, 'rev-parse', '--symbolic-full-name', ref],
                           capture_output=True, text=True, timeout=5)
        out = r.stdout.strip()
        if r.returncode == 0 and out.startswith('refs/heads/'):
            return out[len('refs/heads/'):]
    except Exception:
        pass
    return None


def symbolic(d):
    return d in ('HEAD', '@') or '~' in d or '^' in d or '@{' in d


def norm_ref(r):
    r = r.lstrip('+')
    if r.startswith('refs/heads/'):
        r = r[len('refs/heads/'):]
    return r


def is_everything(p):
    """Does this pathspec stage the whole tree (., ./, :/, *, **, …)?"""
    if p.startswith(':'):
        m = re.match(r':\([^)]*\)', p)
        if m:
            p = p[m.end():]
        elif p.startswith(':/'):
            p = p[2:]
        else:
            return False
        if p == '':
            return True
    return os.path.normpath(p) in ('.', '*', '**')


def check_add(args):
    dashdash = skip = False
    for a in args:
        if skip:
            skip = False
        elif dashdash or not a.startswith('-'):
            if is_everything(a):
                raise Block("'git add %s' stages everything blindly." % a,
                            "always stage specific files: git add <file> <file>")
        elif a == '--':
            dashdash = True
        elif a.startswith('--'):
            a = expand_long('add', a)
            if a == '--all':
                raise Block("'git add --all' stages everything blindly.",
                            "always stage specific files: git add <file> <file>")
            skip = a in ADD_ARG_LONG
        elif is_cluster(a) and 'A' in a:
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
        if a.startswith('--'):
            a = expand_long('commit', a)
            if a.split('=', 1)[0] == '--no-verify':
                raise Block(*HOOK_BLOCK)
            skip = a in COMMIT_ARG_LONG
        elif is_cluster(a):
            for idx, ch in enumerate(a[1:]):
                if ch == 'n':
                    raise Block("'git commit -n' is short for --no-verify and bypasses the repo's hooks.",
                                "fix the hook failure instead; only the user may bypass hooks manually")
                if ch in 'mFCctSu':
                    skip = (idx == len(a) - 2)
                    break


def check_push(args, cwd):
    force = lease = delete = all_ = prune = False
    pos, skip, dashdash = [], False, False
    for a in args:
        if skip:
            skip = False
            continue
        if dashdash or not a.startswith('-') or a == '-':
            pos.append(a)
            continue
        if a == '--':
            dashdash = True
            continue
        a = expand_long('push', a)
        name = a.split('=', 1)[0]
        if name == '--no-verify':
            raise Block(*HOOK_BLOCK)
        elif name == '--mirror':
            raise Block("'git push --mirror' overwrites/deletes remote refs wholesale.",
                        "push the specific branch: git push origin <branch>")
        elif name == '--force':
            force = True
        elif name == '--delete':
            delete = True
        elif name == '--force-with-lease':      # --force-if-includes alone is NOT a lease
            lease = True
        elif name in ('--all', '--branches'):
            all_ = True
        elif name == '--prune':
            prune = True
        elif a.startswith('--'):
            skip = a in PUSH_ARG_LONG
        elif is_cluster(a):
            for idx, ch in enumerate(a[1:]):
                if ch == 'f':
                    force = True
                elif ch == 'd':
                    delete = True
                elif ch == 'o':
                    skip = (idx == len(a) - 2)
                    break
    refspecs = pos[1:]
    plus = any(r.startswith('+') for r in refspecs)
    wildcard = any('*' in r or r.lstrip('+') == ':' for r in refspecs)

    if (force and not lease) or plus:
        raise Block("bare force push ('--force' / '-f' / '+refspec') can overwrite teammates' work.",
                    "use: git push --force-with-lease --force-if-includes origin <feature-branch>")
    if lease and (all_ or wildcard):
        raise Block("--force-with-lease together with --all/--branches/wildcard or ':' refspecs can rewrite protected branches.",
                    "push one named feature branch: git push --force-with-lease origin <feature-branch>")
    if prune and (not refspecs or all_ or wildcard):
        raise Block("'git push --prune' without an explicit refspec (or with --all/wildcards) can delete remote branches such as main.",
                    "push the specific branch; delete stale remote branches one by one (never protected ones)")

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
    if lease and (implicit or any(symbolic(d) for d, _ in dests)):
        cur = current_branch(cwd)
        if cur is None:
            raise Block("--force-with-lease without an explicit branch, and the current branch could not be determined.",
                        "name the branch explicitly: git push --force-with-lease origin <feature-branch>")
        resolved = []
        for d, dl in dests:
            if d in ('HEAD', '@'):
                d = cur
            elif symbolic(d):
                d = resolve_branch(d, cwd) or cur
            resolved.append((d, dl))
        dests = resolved
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


def check_config(spec, via_env):
    """Guard `git -c k=v` / `--config-env k=ENV` against hook and alias tricks."""
    key, _, value = spec.partition('=')
    k = key.lower()
    if k == 'core.hookspath':
        raise Block("'-c core.hooksPath=…' disables the repo's hooks (same as --no-verify).",
                    "fix the hook failure instead; only the user may bypass hooks manually")
    if k.startswith('alias.') and (via_env or value.startswith('!')
                                   or re.search(r'push|force|--no-verify', value)):
        raise Block("an inline git alias ('-c alias.…') hides what is really executed.",
                    "run the real git command directly")


def check_simple(toks, cwd, depth=0):
    toks, extra = unwrap(toks)
    for e in extra:
        check_command(e, cwd, depth + 1)
    if not toks or os.path.basename(toks[0]) != 'git':
        return
    i = 1
    while i < len(toks) and toks[i].startswith('-'):
        t = toks[i]
        name, eq, val = t.partition('=')
        if t == '-C' and i + 1 < len(toks):
            nd = toks[i + 1]
            cwd = nd if os.path.isabs(nd) else os.path.join(cwd, nd)
        if t == '-c' and i + 1 < len(toks):
            check_config(toks[i + 1], False)
        elif name == '--config-env':
            spec = val if eq else (toks[i + 1] if i + 1 < len(toks) else '')
            check_config(spec, True)
        if t in GLOBAL_ARG:
            i += 1
        i += 1
    if i >= len(toks):
        return
    sub, args = toks[i], toks[i + 1:]
    if '--no-verify' in args and sub not in ('commit', 'push'):
        raise Block(*HOOK_BLOCK)
    if sub == 'add':
        check_add(args)
    elif sub == 'commit':
        check_commit(args)
    elif sub == 'push':
        check_push(args, cwd)


def check_command(text, cwd, depth=0):
    if depth > 4:
        return
    nested, heredocs = [], []
    for toks in tokenize(text, nested, heredocs):
        check_simple(toks, cwd, depth)
    for cmd, body, quoted in heredocs:
        if reads_stdin_as_commands(unwrap(cmd)[0]):
            check_command(body, cwd, depth + 1)     # body is executed as shell code
        elif not quoted:
            scan_subst(body, nested)                # data, but $(…) in it still runs
    for nn in nested:
        check_command(nn, cwd, depth + 1)


def main():
    try:
        data = json.load(sys.stdin)
        cmd = data.get('tool_input', {}).get('command', '') or ''
        cwd = data.get('cwd') or os.getcwd()
    except Exception:
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
