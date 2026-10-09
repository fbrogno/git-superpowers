---
name: git-undo
description: Safe git recovery — undo commits, revert pushes, restore files, escape bad rebases. Triggers: undo, revert, "mach rückgängig", "falscher branch", "alles kaputt gemacht", "restore file", /git-undo.
---

# Git Undo

Diagnose what went wrong and recover safely. This skill always shows you exactly what will happen before doing anything destructive — and always suggests the least destructive option first.

## Safety (always apply)
- Always show what will happen before executing any recovery
- Always confirm destructive operations with explicit user approval
- For pushed commits: prefer `git revert` over history rewriting
- For unpushed commits: prefer `git reset --soft` over `--hard`
- `git reflog` is always the ultimate escape hatch

## Workflow

### Step 1: Diagnose the Situation

Ask the user what happened if it's not clear from context. Common scenarios:

```
What went wrong? (describe in your own words, or pick a number)

[1] I want to undo my last commit (but keep the file changes)
[2] I want to undo my last commit AND discard the file changes
[3] I accidentally pushed to the wrong branch
[4] I need to revert a commit that's already pushed (shared with others)
[5] I accidentally deleted or overwrote a file
[6] My rebase went wrong and I want to go back
[7] I want to discard ALL uncommitted changes
```

Also show the current state to give context:

```bash
git status
git log --oneline -5
```

### Step 2: Explain Before Acting

Before running any recovery command, always show:
- **What will happen** — in plain language
- **What cannot be undone** — if the operation is irreversible
- **The escape hatch** — how to undo the recovery itself if it goes wrong

Then ask for confirmation. Never skip this for destructive operations.

---

## Recovery Scenarios

### Scenario 1: Undo Last Commit, Keep Changes

The safest undo — moves HEAD (your current position in git history) back one commit but keeps all file changes in your working directory.

```bash
git log --oneline -3    # Show what will be undone
git reset --soft HEAD~1
```

After: the commit disappears, but all changes remain staged. The user can edit them and recommit.

Show before running:
```
This will undo:
  abc1234 feat(amazon): add dashboard

Your file changes WILL BE KEPT (staged, ready to recommit).
This is reversible — you can redo the commit. Proceed? (y/n)
```

### Scenario 2: Undo Last Commit AND Discard Changes

This is destructive. The commit itself stays recoverable via `git reflog` (~90 days), but uncommitted working-tree changes are permanently lost.

First check the tree is clean:

```bash
git status --porcelain    # any output = dirty tree
```

If dirty: stop. Offer to stash first (`git stash push -u -m "git-undo backup $(date +%Y-%m-%d-%H%M)"`, recoverable via `git stash list`) or to commit the changes — only continue once the tree is clean or the user explicitly accepts losing those changes.

```bash
git log --oneline -3    # Show what will be lost
git diff HEAD~1..HEAD --stat    # Show what files will be affected
```

Show before running:
```
WARNING: This will discard:
  abc1234 feat(amazon): add dashboard
  → 5 files changed, 142 insertions

The commit stays recoverable via `git reflog` (~90 days).
Uncommitted changes in your working tree (none right now) would be permanently lost.
Are you sure? Type 'yes' to confirm:
```

Only proceed on explicit `yes` confirmation:
```bash
git reset --hard HEAD~1
```

### Scenario 3: Revert a Pushed Commit

When others may already have pulled the commit, `git revert` is the safe path — it creates a new commit that undoes the changes. This is safer than deleting the commit because it doesn't rewrite history that others already have.

```bash
git log --oneline -10   # Help user identify the commit
```

Ask which commit to revert. Then:

```bash
git show <hash> --stat  # Show what the commit did
```

Confirm:
```
This will create a new commit that UNDOES:
  abc1234 fix(auth): changed redirect logic

Other people's history stays intact — no force push needed.
Proceed? (y/n)
```

```bash
git revert <hash> --no-edit
git push origin <branch>
```

### Scenario 4: Pushed to the Wrong Branch

Show the situation first:

```bash
git log --oneline origin/main..HEAD    # commits on wrong branch
git branch --show-current              # current (wrong) branch
```

Ask what the correct branch should be. Then:

```bash
# Step 1: Create correct branch from current position
git checkout -b <correct-branch>

# Step 2: Push to correct branch
git push origin <correct-branch>

# Step 3: Switch back to wrong branch and remove the commits
git checkout <wrong-branch>
```

Show before Step 3:
```
Now we need to remove those commits from <wrong-branch>.

Commits that will be removed from <wrong-branch>:
  abc1234 feat(amazon): add dashboard
  def5678 fix(amazon): typo

They will still exist on <correct-branch>. Proceed? (y/n)
```

How to remove them depends on whether the mistake was already pushed — check first:

```bash
git log --oneline origin/<wrong-branch>..HEAD
```

**Mistake NOT pushed yet** (the commits appear in the output): the remote is still clean — just reset the local branch to it. No force push needed. Check `git status --porcelain` first; if dirty, offer `git stash push -u -m "git-undo backup <date>"` before the hard reset:

```bash
git reset --hard origin/<wrong-branch>
```

**Mistake already pushed** (output is empty — remote has the bad commits too): resetting to origin would be a no-op. Reset to the last good commit and rewrite the remote:

```bash
git log --oneline -10                      # identify the last good commit
git reset --hard <last-good-sha>
git push --force-with-lease --force-if-includes origin <wrong-branch>
```

**Exception — wrong branch is protected or shared** (main/master/develop, or a branch others work on — see Protected Branches in `references/git-safety.md`): never force-push it. Revert instead, which is safe for everyone who already pulled:

```bash
git revert <bad-sha-1> <bad-sha-2> --no-edit
git push origin <wrong-branch>
```

Explain the difference: `--force-with-lease --force-if-includes` fails if someone else pushed meanwhile; `revert` keeps history intact and is the only correct option once teammates may have the commits.

### Scenario 5: Accidentally Deleted or Overwrote a File

Find the last commit that had the file:

```bash
git log --oneline --all -- <file>
```

Show the user the history and ask which version to restore. Then:

```bash
git show <hash>:<file>    # Preview the file contents
```

Ask: "Restore this version? (y/n)"

```bash
git checkout <hash> -- <file>
```

If the user doesn't know the filename or path:

```bash
git log --oneline --diff-filter=D -- "**/*"   # Recently deleted files
```

After restoring, the file is staged. Ask: "Stage and commit the restored file? (y/n)"

### Scenario 6: Bad Rebase — Go Back to Pre-Rebase State

`git reflog` is the escape hatch — it records every position your branch has been in, like an undo history for git itself.

```bash
git reflog | head -20
```

Show the output and explain it:
```
Recent history (most recent first):

abc1234 HEAD@{0}: rebase (finish): returning to refs/heads/fb
def5678 HEAD@{1}: rebase (pick): feat: last commit
...
zzz9999 HEAD@{8}: checkout: moving from main to fb     ← before rebase

The last entry before the rebase is HEAD@{8} (zzz9999).
Restore to that point? (y/n)
```

Show what will be lost:
```bash
git diff <pre-rebase-ref>..HEAD --stat
```

Only proceed on confirmation (and only with a clean `git status --porcelain` — otherwise offer `git stash push -u -m "git-undo backup <date>"` first):
```bash
git reset --hard <pre-rebase-ref>
```

Then offer to re-sync cleanly: "Want to run smart-sync now to redo the rebase with guidance?"

### Scenario 7: Discard ALL Uncommitted Changes

This is irreversible. Show exactly what will be lost:

```bash
git status
git diff --stat
```

```
WARNING: All of the following will be discarded (staged and unstaged):
  M  src/amazon/dashboard.tsx (+42 lines)
  M  src/utils/api.ts (+8 lines)
  ?  src/amazon/NewWidget.tsx (untracked — will be deleted)

Safety net: I can first save everything to a stash
  (git stash push -u -m "git-undo backup <date>" — recover via `git stash list`).
Without the backup there is no undo. Backup first? (recommended)
Type 'yes' to confirm the discard:
```

Offer the backup first and run it if accepted (`-u` includes untracked files):
```bash
git stash push -u -m "git-undo backup $(date +%Y-%m-%d-%H%M)"
```

Only on `yes` — if the stash was made, the tree is already clean and nothing more is needed; otherwise:
```bash
git reset --hard HEAD    # Discards staged AND unstaged changes to tracked files
git clean -fd            # Remove untracked files
```

Show `git status` after to confirm clean state.

---

## The Reflog Safety Net

At the end of any recovery, remind the user:

```
Remember: git reflog shows every state your repo has been in for the past 90 days.
If something still looks wrong, run: git reflog
It's your ultimate escape hatch.
```

## Rules

- Always show what will happen before executing any recovery
- Always confirm destructive operations with explicit user approval
- For pushed commits: prefer `git revert` over history rewriting
- For unpushed commits: prefer `git reset --soft` over `--hard`
- Never skip `git reflog` as an option when the user is unsure what state they're in
- After recovery, always run `git status` and `git log --oneline -5` to verify
