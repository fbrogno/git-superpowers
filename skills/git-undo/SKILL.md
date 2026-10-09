---
name: git-undo
description: Use when the user wants to undo or recover something in git — revert a commit, "mach rückgängig", "falscher Branch", pushed to the wrong branch, "letzten Commit ändern" (amend), squash the last commits, restore a deleted or overwritten file, escape a bad rebase, discard all local changes, "alles kaputt gemacht". Not for splitting a commit (commit-split) or stashes (stash).
---

# Git Undo

Diagnose what went wrong, then recover with the least destructive option that works.

## Iron Law

```
NO DESTRUCTIVE COMMAND WITHOUT A RECOVERY PATH AND EXPLICIT USER CONFIRMATION
```

Before any `reset --hard`, `clean`, `checkout -- <file>` or force push: show exactly what is lost, name the way back (reflog SHA, backup stash), get a "yes".

## Red Flags

| Thought | Reality |
|---|---|
| "The git-guard hook will catch anything bad" | It blocks patterns, not intent. A plain `reset --hard` passes and eats uncommitted work. |
| "It's only my branch, force-push is fine" | Check `git log origin/<branch> --format=%ae \| sort -u` first. Teammates may have it. |
| "Uncommitted changes are probably nothing" | Untracked and unstaged work is NOT in the reflog. Back it up (`stash -u`) or confirm. |
| "I'll skip the preview, the user is in a hurry" | The preview is 2 lines. Data loss is forever. |
| "reset is quicker than revert" | On pushed commits, revert is the only safe option. |

## Workflow

1. Show state: `git status`, `git log --oneline -5`. If unclear, ask which scenario below applies.
2. Before acting, state: what will happen, what cannot be undone, how to undo the recovery itself.
3. Confirm, execute, then verify with `git status` and `git log --oneline -5`.

Prefer `git revert` for pushed commits and `git reset --soft` for unpushed ones. `git reflog` (~90 days) is the escape hatch; mention it after every recovery.

## Scenarios

**1. Undo last commit, keep changes** (reversible)
```bash
git log --oneline -3 && git reset --soft HEAD~1
```
Changes stay staged for recommit. This also covers "letzten Commit ändern" and squashing the last N commits (`git reset --soft HEAD~N`, then recommit) only if `git log origin/<branch>..HEAD` lists all N commits; otherwise it is pushed history: revert, or the force-push rules in scenario 4. `git commit --amend` is acceptable only for an unpushed commit, after confirmation.

**2. Undo last commit AND discard changes** (destructive)
Require a clean tree first (`git status --porcelain` empty); if dirty, offer `git stash push -u -m "git-undo backup $(date +%Y-%m-%d-%H%M)"` or a commit. Show `git diff HEAD~1..HEAD --stat`. The commit stays in the reflog; uncommitted work would not. Only on typed `yes`: `git reset --hard HEAD~1`.

**3. Revert a pushed commit** (safe for shared history)
```bash
git show <hash> --stat      # confirm it is the right commit
git revert <hash> --no-edit && git push origin <branch>
```

**4. Commits landed on the wrong branch**
```bash
git log --oneline origin/<wrong>..HEAD    # the stray commits
git branch <correct-branch>               # keep them on the right branch
```
Push `<correct-branch>` if wanted. Then remove them from `<wrong>` (show the list, confirm):
- Not pushed (the log above shows them): `git reset --hard origin/<wrong>` (stash first if tree is dirty).
- Already pushed: if `<wrong>` is protected or shared (see `references/git-safety.md`), revert: `git revert <sha1> <sha2> --no-edit && git push`. Only on a private branch: `git reset --hard <last-good-sha>` then `git push --force-with-lease --force-if-includes`.

**5. Deleted or overwritten file**
```bash
git log --oneline --all -- <file>              # or --diff-filter=D -- "**/*" if the name is unknown
git show <hash>:<file>                         # preview, confirm
git checkout <hash> -- <file>                  # restores and stages
```

**6. Bad rebase**
If the rebase is still in progress (`git status` says so), run `git rebase --abort` first. Otherwise `git reflog | head -20`, find the entry just before the rebase started, show `git diff <ref>..HEAD --stat`, confirm, clean tree required (else backup stash), then `git reset --hard <ref>`. Offer `/smart-sync` to redo the rebase with guidance.

**7. Discard ALL uncommitted changes** (irreversible)
Show `git status` and `git diff --stat`, list untracked files that will vanish. Offer the backup stash (`-u`) first. Only on `yes`: `git reset --hard HEAD && git clean -fd` (skip both if the stash already cleaned the tree). Run `git status` afterwards.

## Rules

- Never skip the preview for destructive operations
- Never force-push a protected or shared branch; revert instead
- After recovery always run `git status` and `git log --oneline -5`
