---
name: hotfix
description: Use when production is broken and needs an urgent fix that must not mix with in-progress work — "hotfix", "production is broken", "prod ist down", "Notfall", "kritischer Bug in Produktion", "live gefixt werden". Only for urgent production fixes; ordinary bugfixes belong on a normal branch.
---

# Hotfix

Ship an emergency fix to production without touching the user's in-progress work. Straight line from broken to PR, minimal questions, no shortcuts on safety.

## Iron Law

```
THE HOTFIX BRANCHES FROM FRESHLY FETCHED PRODUCTION, AND THE USER'S WORK COMES BACK UNTOUCHED
```

Time pressure removes optional steps, never the secret scan, the conflict-marker check, or the return to the previous state.

## Red Flags

| Thought | Reality |
|---|---|
| "No time for the audit, prod is down" | A bad hotfix prolongs the outage. The audit is one grep pass. |
| "I'll fix it on the current feature branch" | Ships unfinished work to prod. Branch from `origin/$BASE`. |
| "git stash is quick, no need for a worktree" | A stash can conflict on pop and is shared across worktrees. Worktree leaves the tree untouched. |
| "Push straight to main, a PR is too slow" | PR plus a label is 20 seconds and keeps a review trail. Direct push only if the user says so. |
| "I'll refactor while I'm here" | Scope creep is production risk. Surgical change only. |
| "The guard hook will stop a leaked key" | It does not read file contents. Scan the diff yourself. |

## Workflow

Detect `$BASE` per `references/common-snippets.md#base-branch`; if a `production` or `release/*` branch is what's deployed (`git branch -r | grep -E 'origin/(production|release/)'`), use that. Ask for a short issue name (lowercase, hyphens).

### 1. Isolate (worktree preferred)

Record `PREVIOUS_BRANCH=$(git branch --show-current)` and `TS=$(date +%s)` first.

**Preferred: worktree** (no stash, user's work untouched). If your harness offers a native worktree tool (e.g. `EnterWorktree`), use it with a `hotfix/<name>` branch from `origin/$BASE`. Otherwise:
```bash
git worktree add ../<repo>-hotfix -b hotfix/<name> origin/$BASE
cd ../<repo>-hotfix
```
Work and commit there. Step 7 removes it.

**Fallback: stash** (only if a worktree is impossible):
```bash
STASHED=0
git status --porcelain | grep -q . && { git stash push -u -m "hotfix: park $TS" && STASHED=1; }
git checkout -b hotfix/<name> origin/$BASE
```
Stash only when the tree is dirty (otherwise an unrelated older stash would be popped later). Never leave the user's tree modified on failure: if anything aborts, restore with `git checkout "$PREVIOUS_BRANCH"` and, only if `STASHED=1`, the pop from step 7.

### 2. Fix
Read the relevant files, make a minimal targeted change, no refactoring. Wait for the user if they fix it themselves.

### 3. Audit before committing
Audit the working tree: `git diff origin/$BASE` plus new files from `git ls-files --others --exclude-standard`. After the commit (step 4) re-audit `git diff origin/$BASE..HEAD` before pushing.
- Conflict markers: `git diff origin/$BASE | grep -nE "^\+.*(<<<<<<<|=======|>>>>>>>)"`
- Secrets (`references/git-safety.md#secret-patterns`): block if found
- Debug artifacts (`console.log`, `debugger`)
- Scope: >10 files or >200 lines: ask "Is all of this needed for the emergency?"

### 4. Commit
`fix(<scope>): <description>` (the `fix:` prefix is needed for semver pipelines), staged by file, per `references/common-snippets.md#commit-template`. Show the message first.

### 5. Push and PR
```bash
git push -u origin hotfix/<name>
gh auth status >/dev/null 2>&1 && gh pr create --base "$BASE" --label hotfix --title "fix: <description>" --body "<HOTFIX: problem, fix, test plan (verify fix, no regressions, check prod logs after deploy)>"
```
No `gh`: push, give the web URL hint. Missing `hotfix` label: create the PR without it and say so. Show the PR URL.

### 6. Verify
Fresh `gh pr checks` output before saying CI is green (`references/common-snippets.md#verification`).

### 7. Return
- Worktree: `cd` back, `git worktree remove ../<repo>-hotfix` once pushed (the branch lives on).
- Stash: `git checkout "$PREVIOUS_BRANCH"`; only if `STASHED=1`: `git stash pop "$(git stash list --format=%gd --grep="hotfix: park $TS" | head -1)"` (pops exactly our stash); on stash conflict use `references/conflict-resolution.md`.

### 8. After merge
Remind: `/smart-sync` the previous branch so it builds on the fixed production code.

## Rules

- Secret scan and conflict-marker check are never skipped
- Never `git add .`; never branch from a feature branch
- Leave the workspace as found (branch, stash, working tree)
