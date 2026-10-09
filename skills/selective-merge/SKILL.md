---
name: selective-merge
description: Use when the user wants specific files, not commits or a whole branch, from another branch — "hol mir die Datei von", "get file X from branch Y", "ich brauch die Version von main", "take file from", "nur diese Datei übernehmen". For whole commits use cherry-pick.
---

# Selective Merge

Bring a file's current state from another branch into the working tree. No history, no merge commit, no commit at all; the user commits afterward.

## Safety
- Never overwrite uncommitted local changes without explicit confirmation
- Always show the diff between branches before applying
- Never leave the user's tree modified on failure: if a step fails or the user cancels midway, restore the pre-operation state (the file from `HEAD`, or the stash back) and say so
- Never commit the result; preflight per `references/common-snippets.md#preflight`

## Workflow

### 1. Intent
Need exact file path(s) and source branch (local, `origin/<branch>`). "get api.ts from bobby's branch" means resolve the real path and `origin/bobby`. `git fetch origin`, then `git branch -a | grep <name>`.

### 2. Show the difference
```bash
git cat-file -e origin/<branch>:<file> 2>/dev/null || echo FILE_NOT_ON_SOURCE
git ls-files --error-unmatch <file> 2>/dev/null || echo FILE_NOT_LOCAL
git diff HEAD..origin/<branch> -- <file>
```
Not on source: "Nothing to take", stop. Not local: it will be added as a new file. Empty diff: identical, stop. Show the diff readably.

### 3. Local changes check
`git status -- <file>`. If modified or staged, show the local diff and warn they are in no commit and would be lost. Options: stash only this file (`git stash push -u -m "selective-merge: park <file>" -- <file>`), commit first, take anyway, cancel. Wait for the choice.

### 4. Strategy
- **Replace**: `git restore --source=origin/<branch> --worktree -- <file>` (deliberately unstaged, unlike `git checkout <ref> -- <file>`).
- **Merge parts**: show the diff hunk by hunk, ask "Take this change?" for each, apply only the chosen ones by editing the file, show the resulting content.

### 5. Verify
`git diff HEAD -- <file>`, "Does this look right?". If stashed in step 3: for Replace the stash holds the old local version, so keep it until the user decides (`git stash show -p stash@{0} -- <file>` shows what was parked). To combine both, hand-merge from that diff, or commit the taken version first and then `git stash pop` (gives real conflict markers to resolve; a pop onto an uncommitted replaced file does not conflict, it refuses or overwrites). Drop the stash only after confirmation.

### 6. Hand back
Tell the user the file is changed but uncommitted; suggest `git add <file>` and commit, or `/smart-commit`.

## Does not
Bring history, create a merge commit, cherry-pick, or handle whole directories (ask for specific files). Multiple files: one by one with confirmation each.
