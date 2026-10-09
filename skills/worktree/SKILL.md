---
name: worktree
description: Use when the user wants a second branch checked out at the same time — "parallel arbeiten", "zweiter branch gleichzeitig", "worktree", "ohne stash wechseln", "work on two branches", "separate checkout". Not for stashing (git-superpowers:stash) or emergency fixes that can stash instead (git-superpowers:hotfix).
---

# Worktree

## Overview

A worktree is a second working directory on the same repository: another branch, no stash, no switching. This is the git-native operations view; `superpowers:using-git-worktrees` is the general-purpose counterpart for feature isolation. Only remove what you created, and only when clean.

## When to Use

- Work on branch B while branch A has uncommitted changes, long builds, or a running dev server.
- Not for: parking changes (`git-superpowers:stash`), one-off emergency fixes (`git-superpowers:hotfix`).

## Procedure

### 0. Prefer the native tool

If the harness offers `EnterWorktree` / `ExitWorktree`, use them instead of the commands below.

### 1. Check where you are

```bash
[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ] && echo "already in a linked worktree"
git rev-parse --show-superproject-working-tree   # non-empty: inside a submodule, stop and ask
git worktree list
```

Already in a worktree: tell the user; create the new one from the main checkout's perspective, not nested.

### 2. Choose the location

Default sibling directory `../<repo>-<branch-slug>`. Alternative `.worktrees/` inside the repo only if ignored:

```bash
git check-ignore -q .worktrees || echo ".worktrees" # not ignored: ask before appending to .gitignore
```

### 3. Create

```bash
git fetch origin --quiet
git worktree add ../<repo>-<slug> <existing-branch>             # existing branch
git worktree add -b <new-branch> ../<repo>-<slug> origin/<BASE> # new branch from base
git worktree add --detach ../<repo>-<slug> <rev>                # throwaway inspection
```

BASE detection: see Branch Detection in `references/git-safety.md`. A branch can be checked out in only one worktree; git refuses a second. Remember to install dependencies in the new directory (node_modules are not shared).

### 4. Remove (only ours, only clean)

```bash
git -C <wt> status --short            # show it
git -C <wt> log --oneline @{u}..      # unpushed commits?
git worktree remove <wt>
git worktree prune                     # clear records of deleted directories
```

Dirty or unpushed: show the output and ask. Never `--force` on a worktree the user made themselves. Deleting the branch afterwards is a separate decision (`git branch -d`).

## Quick Reference

| Goal | Command |
|---|---|
| List | `git worktree list` |
| Add | `git worktree add <path> <branch>` |
| New branch | `git worktree add -b <name> <path> origin/<BASE>` |
| Remove | `git worktree remove <path>` |
| Clean records | `git worktree prune` |
| Move/lock | `git worktree move` / `lock` |

## Common Mistakes

- Nesting a worktree inside another or inside a submodule.
- Creating `.worktrees/` without ignoring it, then committing it.
- `rm -rf` instead of `git worktree remove`.
- Using `--force` to get rid of uncommitted work.
- Assuming the stash is separate: it is shared across worktrees.
- Forgetting dependency install and env files in the new directory.
