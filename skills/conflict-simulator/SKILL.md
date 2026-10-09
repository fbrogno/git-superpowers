---
name: conflict-simulator
description: Use when the user wants to know whether a rebase or merge would conflict before doing it — "gibt es Konflikte", "will there be conflicts", "dry run rebase", "wird das klappen", "kann ich das ohne Konflikte mergen". Read-only prediction; to actually resolve conflicts use smart-sync.
---

# Conflict Simulator

Predict merge and rebase conflicts without touching the branch. Read-only: simulate, report, leave everything as found.

## Safety
- MUST NOT modify the working tree, index or any branch; never run `git rebase` as a simulation
- Record `git status --porcelain` and `git branch --show-current` first; after the simulation they must match, else stop and report the discrepancy
- If temp-worktree cleanup fails, stop and report the exact state so the user can recover
- On any failure the user's tree is left exactly as before (the fallback uses a throwaway worktree, never stash or checkout)

## Workflow

### 1. Preflight and fetch
Works with clean or dirty trees. Detached HEAD: stop (`references/common-snippets.md#preflight`). `git fetch origin` always, stale refs lie. Target defaults to `origin/$BASE` (`references/common-snippets.md#base-branch`); two explicit branches from the user override it. Show ahead/behind counts.

**Caveat to state in the report:** `git merge-tree` simulates a single merge against the tip; a rebase replays commit by commit and can hit sequential conflicts the merge does not show (rerere may also auto-resolve). Say "no conflicts expected", never "clean rebase guaranteed".

### 2. Overlap first
Run the overlap check (`references/common-snippets.md#overlap`). Empty: report "No overlapping files, no conflicts expected" and stop.

### 3. Simulate
```bash
OUT=$(git merge-tree --write-tree HEAD origin/$BASE 2>&1); EXIT=$?
[ "$EXIT" -ne 0 ] && echo "$OUT" | grep '^CONFLICT' | sed 's/.*Merge conflict in //'
```
Judge by the EXIT STATUS (0 clean, 1 conflicts), not the output text; an empty grep with exit 1 is still a conflict.

Git < 2.38 (no `--write-tree`): throwaway worktree, your own tree stays untouched:
```bash
tmp=$(mktemp -d); git worktree add --detach "$tmp" HEAD
git -C "$tmp" merge --no-commit --no-ff origin/$BASE 2>&1
CONFLICTED=$(git -C "$tmp" diff --name-only --diff-filter=U)
git -C "$tmp" merge --abort 2>/dev/null || true
git worktree remove --force "$tmp"; git worktree prune     # --force is safe: our own temp dir
```

### 4. Verify state
Re-run `git status --porcelain` and `git branch --show-current`; compare with step 1.

### 5. Report
No conflicts: say so, suggest `/smart-sync` when ready. Conflicts: per file the severity (**Easy** different sections, **Medium** same section compatible, **Hard** structural; unsure means Hard), what each side changed, a one-line recommendation, a timing hint (hard ones get worse over time). Offer `/smart-sync`, the full diff for a file, or `git log --oneline $(git merge-base HEAD origin/$BASE)..origin/$BASE -- <file>`.

## Multiple targets
One Bash call: `for t in origin/$BASE origin/<other>; do echo "== $t"; git merge-tree --write-tree HEAD $t 2>&1; echo "EXIT:$?"; done`

Proactive use: safe-push and smart-sync may call this when overlap is detected.
