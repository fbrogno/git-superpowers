---
name: safe-push
description: Use when the user wants to push commits to the remote — "push", "pushen", "ab damit", "hochladen", "push my branch", "check before push". Owns every push request; for committing use smart-commit, for the whole commit+push+PR chain use daily-workflow.
---

# Safe Push

Audit what is about to go out, fix what is wrong, then push. It reads the diff semantically (unfinished features, missing files), not just by regex.

## Iron Law

```
NO PUSH WITHOUT A FRESH AUDIT OF EXACTLY WHAT IS OUTGOING
```

Audit the diff as it is now, in this turn. An earlier review, a green CI run or "I only changed one line" does not count.

## Red Flags

| Thought | Reality |
|---|---|
| "I just reviewed this, skip the audit" | The diff changed since. Audit is one pass; run it. |
| "The git-guard hook scans for secrets" | The hook blocks command patterns, not secrets in file content. |
| "It's only a debug line / a TODO" | Those are exactly what the audit exists for. |
| "Tests passed earlier" | Earlier is not now. Re-run or say "not re-verified". |
| "User said hurry, I'll push and audit after" | A pushed secret is leaked; a delayed push costs a minute. |
| "Rejected, I'll just force-push" | Never. Remote has new commits: `/smart-sync`. |

## Workflow

Preflight per `references/common-snippets.md#preflight`. Never `git add .`.

### 1. What's going out
```bash
git fetch origin
git log --oneline origin/<branch>..HEAD
git diff --stat origin/<branch>..HEAD
```
Nothing outgoing: say "Nothing to push" and stop. New branch without upstream: use `origin/$BASE..HEAD`.

### 2. Conflict prediction
Detect `$BASE` and run the overlap check (`references/common-snippets.md#base-branch`, `#overlap`). Overlap: warn and suggest `/smart-sync` or `/conflict-simulator`. No overlap: stay silent.

### 3. Audit (one pass over `git diff origin/<branch>..HEAD`)

1. **Debug artifacts**: added `console.log/debug`, `debugger`, debug `print(` (not in tests or logging utilities).
2. **Conflict markers**: `<<<<<<<`, `=======`, `>>>>>>>`.
3. **Secrets**: patterns in `references/git-safety.md#secret-patterns`. Blocks the push.
4. **Incomplete features**: imports of files not in the push, components used but undefined, new TODO/FIXME/HACK.
5. **Large files** (`--stat` misses binaries):
```bash
git rev-list --objects origin/<branch>..HEAD | git cat-file --batch-check='%(objectsize) %(objecttype) %(rest)' \
  | awk '$2=="blob" && $1>1048576 {printf "%.1f MB  %s\n",$1/1048576,$3}' | sort -rn
```
Flag >1 MB; GitHub rejects >50 MB. Offer to remove accidental binaries (Git LFS if intended).
6. **Deploy configs** (only if the diff touches compose/Dockerfile/k8s/`.service`/`.env*`/proxy configs): hardcoded host ports, `container_name:`, `:latest`, host-path volumes, committed `.env` values. **Gate, not warning** when this push triggers the FIRST deploy and a hardcoded host port is present: do not push until the user's confirmation names the verification ("port X checked free on target") — hand off to `/deploy-check` for the confirmed read-only `ss -tlnp` check; better offer the config fix first.

### 4. Report and fix
All clear: "Safe Push Audit passed: N commits, M files. Push to origin/<branch>?" Otherwise list numbered findings (file:line, actual code) and ask which to fix (numbers, all, ignore).

Fixes: remove debug lines (replace if it was the only statement); `git add` forgotten files, or ask remove-import vs create-file; ask what to do with TODOs; secrets: show redacted, ask user to remove or swap for an env var. Then a separate cleanup commit per `references/common-snippets.md#commit-template` (`chore: cleanup before push`), never amend.

### 5. Push
```bash
git push origin <branch>
```
Rejected (remote has new commits): offer `/smart-sync` (recommended) or `git pull --rebase origin <branch>`; on any conflict `git rebase --abort` and redirect to `/smart-sync`.

### 6. Verify
"Pushed" is only true after fresh output: `git status -sb` must show no `ahead`, and `git log --oneline origin/<branch>..HEAD` must be empty. Claims about CI or tests need fresh `gh pr checks` or a test run from this turn (see `references/common-snippets.md#verification`; with superpowers installed: `superpowers:verification-before-completion`).

Next: `/pr-prep` for a pull request, `/repo-overview` for other repos.

## Rules

- Never push without showing what goes out; never skip the secret scan
- Show each issue with file, line and code; fix directly instead of only warning
- Plain `git push` only; if force seems needed, `/smart-sync` first
