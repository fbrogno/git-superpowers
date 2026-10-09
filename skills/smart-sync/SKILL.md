---
name: smart-sync
description: Use when the user wants their branch brought up to date with the default branch by rebase — "sync", "rebase onto main", "pull from main", "neusten Stand ziehen", "branch aktualisieren" — or when a rebase or merge is stopped on conflicts ("merge conflicts lösen", "rebase conflict"). Not for pushing (safe-push) or just predicting conflicts (conflict-simulator) (cherry-pick conflicts: cherry-pick).
---

# Smart Sync

Rebase the branch onto the default branch and resolve conflicts by topic instead of raw file diffs.

## Iron Law

```
NEVER FORCE-PUSH A SHARED OR PROTECTED BRANCH, AND NEVER WITHOUT --force-with-lease --force-if-includes
```

A rebase rewrites history. Check who else works on the branch, keep a way back (`git reflog`, `ORIG_HEAD`), and confirm before pushing.

## Red Flags

| Thought | Reality |
|---|---|
| "I'll just force-push quickly" | Lease+includes or nothing. Rejected lease = someone pushed; fetch and look. |
| "It's only my branch" | `git log origin/<branch> --format=%ae \| sort -u` — more than one author = shared. |
| "The PR already has reviews, a rebase is harmless" | It invalidates review context and re-runs CI. Ask first. |
| "Too many conflicts, I'll take `--ours` for everything" | During rebase `--ours` = main, `--theirs` = your commits. Wrong guess silently drops work. |
| "git-guard would block a bad force-push" | It blocks bare `--force`, not a lease on a branch teammates use. |

## Workflow

Preflight per `references/common-snippets.md#preflight`; detect `$BASE` per `#base-branch`. Never `git rebase -i` (needs stdin).

0. **Rebase already in progress?** `git rev-parse -q --verify REBASE_HEAD` succeeds, or `$(git rev-parse --git-path rebase-merge)` / `$(git rev-parse --git-path rebase-apply)` exists: skip steps 1-4 (no new stash, no new rebase) and go straight to step 5.
1. **Stash dirty tree**: `git status --porcelain`; if dirty `git stash push -u -m "smart-sync: auto-stash $(date +%Y-%m-%d-%H%M)"` and tell the user.
2. **Analyze incoming**: `git log --oneline HEAD..origin/$BASE`. Empty: "Already up to date", pop stash, stop. Otherwise show commits, `git diff --stat HEAD...origin/$BASE` and the overlap (`#overlap`); overlap means conflicts are likely (`/conflict-simulator` previews them).
3. **Merge commits on the branch?** `git log --merges origin/$BASE..HEAD --oneline`. If any: offer `--rebase-merges` (keeps structure), standard rebase (flattens, may re-conflict) or abort.
4. **Rebase**: `git rebase origin/$BASE`. Clean: go to step 7.
5. **Analyze conflicts** (`git diff --name-only --diff-filter=U`), read `references/conflict-resolution.md`; for >3 files spawn `git-superpowers:conflict-resolver` with `mode: rebase` (`mode: merge` in a merge). Group by topic, per group state what each side changed and a recommendation. More than 5 files: suggest aborting and syncing more often.
6. **Resolve** per topic: keep mine `git checkout --theirs <f>`, take main `git checkout --ours <f>` (inverted during rebase!), combine (edit, remove markers), or show the conflict. Mixed files hunk by hunk. Then `git add <f>` and `git rebase --continue`; repeat for later commits. Offer `git rebase --abort` at any point. If `git rerere status` lists files, ask the user to verify the auto-resolutions.
7. **Push** (history was rewritten): confirm, then `git push --force-with-lease --force-if-includes origin <branch>`. Protected or shared branch: stop (see `references/git-safety.md`). Lease rejected: `git fetch`, inspect `git log HEAD..origin/<branch>`, re-sync; do not force.
8. **Cleanup**: `git stash pop` if stashed. Verify with fresh output: `git log --oneline <branch>..origin/$BASE` must be empty and `git status -sb` clean. Summarize (commits applied, conflicts resolved) and suggest `/smart-commit`, `/safe-push`.

## Conflicts in an in-progress merge

If a `git merge` is already stopped on conflicts (`git status` says "You have unmerged paths", `git rev-parse -q --verify MERGE_HEAD` succeeds), resolve it here instead of rebasing: do not start a rebase or abort silently.

- Same topic grouping and per-group choices as step 5/6 (pass `mode: merge` to the conflict-resolver), but in a merge `--ours` = your branch and `--theirs` = the incoming branch (not inverted).
- Finish with `git add <files>`, show the message with `cat "$(git rev-parse --git-path MERGE_MSG)"`, then `git commit --no-edit` (no editor) — not `rebase --continue`.
- Escape hatch: `git merge --abort`. No force-push is needed afterwards (history was not rewritten); use `/safe-push`.

## Rules

- Rebase is the default; merge only when the user asks or a merge is already in progress
- Never bare `--force`; never force a protected or shared branch
- `--ours`/`--theirs` are inverted during rebase: say so when explaining
- Always restore the stash and verify Behind: 0 from fresh output
