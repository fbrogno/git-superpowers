# Common Snippets

Shared snippets referenced by several skills. Skills point here by anchor (e.g. `references/common-snippets.md#base-branch`) instead of repeating them.

## Base Branch

Detect the default branch once, then use `$BASE` everywhere — never hardcode `main`. A user-named base (`develop`, `release/*`, stacked PR) overrides it.

```bash
git fetch origin
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null && BASE=main || BASE=master; }
BRANCH=$(git branch --show-current)
```

Skills that print `origin/main` in examples mean `origin/$BASE`.

## Preflight

Run at the start of any skill that commits, pushes, syncs or rewrites:

- Detached HEAD: `git branch --show-current` empty → stop, ask which branch to check out.
- No remote: `git remote | head -1` empty → fetch/push impossible, say so.
- Shallow clone: `git rev-parse --is-shallow-repository` = `true` → ranges/merge-base may be wrong.
- Worktree: stash is shared with the main checkout; a branch checked out elsewhere can't be checked out here.

## Overlap

Files changed on both sides since the fork point (conflict candidates):

```bash
MB=$(git merge-base HEAD origin/$BASE)
comm -12 <(git diff --name-only $MB..HEAD | sort) <(git diff --name-only $MB..origin/$BASE | sort)
```

No output = no file overlap. For two remote branches replace `HEAD` / `origin/$BASE` with the two refs.

## Commit Template

Always via heredoc, staging explicit files only:

```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<optional body>

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
```

Show `git diff --cached --stat` and the message before committing. Never hard-code a model name in the trailer.

## Standard Safety Lines

- Stage specific files, never `git add .` / `-A`.
- Force only as `--force-with-lease --force-if-includes`, never on protected/shared branches (see git-safety.md).
- Never `--no-verify`; fix the hook failure.
- Pre-commit hook failed = no commit exists; fix, re-stage, commit again as a NEW commit (never `--amend`).
- Show what will happen and get confirmation before any destructive command.
- Cleanup of a mistake on pushed history = new commit, never amend.

## Verification

Claims such as "CI is green", "tests pass", "pushed", "clean" need fresh command output from this turn, not memory of an earlier run:

- CI: `gh pr checks` or `gh run list --branch "$BRANCH" --limit 3`
- Tests: run the test command now and read the exit code
- Push/sync state: `git status -sb`

If `superpowers:verification-before-completion` is installed, follow it too. This works standalone without it.
