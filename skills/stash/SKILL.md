---
name: stash
description: Use when the user mentions stashes — "stash", "zwischenspeichern", "wo ist mein stash", "stash anwenden", "lost stash", "stash weg", "stash aufräumen", "stash to branch". Not for urgent production fixes that need a clean tree (git-superpowers:hotfix) or working on two branches at once (git-superpowers:worktree).
---

# Stash

## Overview

A stash is easy to forget and easy to lose. List before you act, inspect before you apply, and delete only with the contents on screen and a yes from the user. Dropped stashes remain recoverable for a while, so a mistake is usually fixable.

## When to Use

- Saving, finding, inspecting, applying, cleaning up or recovering stashes.
- Not for: emergency fixes (`git-superpowers:hotfix` handles its own stash), parallel branches without stashing (`git-superpowers:worktree`).

## Iron Law

NEVER run `git stash clear` or `git stash drop` without first showing the stash contents (`git stash show -p --include-untracked stash@{n}`) and getting explicit confirmation. Stashes are shared by all worktrees of the repo.

## Procedure

### List and find

```bash
git stash list --date=relative          # stash@{n}: On <branch>: <message> (age)
git stash list | grep -i "<keyword>"    # find by message
git stash show -p --include-untracked stash@{n}   # full content (git >= 2.32); older: omit the flag
git stash show --stat stash@{n}
```

### Save

```bash
git stash push -u -m "<what and why>" [-- <paths>]
```

Always give a message; `-u` includes untracked files. Reference by message instead of number when the index may have shifted — resolve the current index first: `git stash list --format='%gd %s' | grep '<message>'` → `git stash apply stash@{<n>}`. (Don't use `stash^{/regex}`: it only searches the ancestry of the newest stash and misses older entries.)

### Apply: prefer apply over pop

```bash
git stash apply stash@{n}
# verify: git status, run tests
git stash drop stash@{n}     # only after showing contents and confirmation
```

`pop` drops automatically, but on a conflict it keeps the stash and the state is easy to misread. With `apply` the stash stays until the user has verified the result.

### Conflicts on apply

The stash is untouched. Resolve the markers in the working tree (see `references/conflict-resolution.md`), or abandon with `git checkout -- .` and `git clean` only after the user confirms what would be lost. Alternative that never conflicts: `git stash branch <new-branch> stash@{n}` creates a branch at the stash's base commit, applies it, and drops the stash on success.

### Recover a dropped or cleared stash

```bash
SHAS=$(git fsck --no-reflog | awk '/dangling commit/ {print $3}')
git log --merges --no-walk --format='%h %ci %s' $SHAS   # stash commits are merges, subject "WIP on" or "On"
git log --no-walk --format='%h %ci %s' $SHAS             # fallback: all dangling commits
git show <sha>               # inspect, then: git stash apply <sha>
```

`git fsck --unreachable | grep commit` is the broader variant. Works until garbage collection prunes the objects; act promptly. The `git stash drop` output prints the SHA — keep it.

### Clean up old stashes

Show each candidate with age and contents, ask per stash (or per explicit list), then drop one by one.

## Quick Reference

| Goal | Command |
|---|---|
| Save | `git stash push -u -m "msg"` |
| List | `git stash list --date=relative` |
| Inspect | `git stash show -p --include-untracked stash@{n}` |
| Apply | `git stash apply stash@{n}` |
| To branch | `git stash branch <name> stash@{n}` |
| Recover | `git fsck --no-reflog \| awk '/dangling commit/ {print $3}'` |

## Common Mistakes

- `pop` on a dirty tree, then losing track after a conflict.
- Stashing without `-u`, leaving new files behind.
- Dropping by index after another stash shifted the numbers.
- `stash clear` to "tidy up" without looking.
- Forgetting that stashes are repo-wide, not per branch or worktree.
