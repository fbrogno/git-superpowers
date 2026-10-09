---
name: commit-split
description: Use when the last commit is too big or mixes topics and should be turned into several focused commits — "split commit", "Commit aufteilen", "commit zu groß", "too many things in one commit", "den letzten Commit in Themen trennen". Not for grouping uncommitted changes (smart-commit) or squashing commits together.
---

# Commit Split

Split an oversized or mixed commit into focused ones. Only safe for the tip commit(s); older commits need an interactive rebase (see Constraints).

## Safety
- Confirm the split plan before any `git reset`
- Warn before any force push with the exact command and consequences
- Never `--amend`; new commits only
- Verify `git diff --cached --stat` after staging each group
- Preflight per `references/common-snippets.md#preflight`; standard lines in `#standard-safety-lines`

## Workflow

### 1. Identify
Default `HEAD`; `git show --stat HEAD`. **Clean tree required** (`git status --porcelain`): otherwise stop and send the user to `/smart-commit` or `git stash push -u -m 'commit-split: before split'`.

Already pushed? Only meaningful when an upstream exists:
```bash
git fetch origin 2>/dev/null
git rev-parse --verify -q origin/<branch> >/dev/null && git log --oneline origin/<branch>..HEAD || echo "no upstream, nothing pushed"
```
Upstream exists and the log is empty: the commit is pushed; warn now that splitting rewrites history and needs a force push. Commit other than `HEAD`: see Constraints, stop.

### 2. Detect topics
`git show HEAD`, then `references/topic-detection.md` (path, `.claude-git.yml`, semantic). Assign each file to a topic, ⚡ for files with several topics. Present numbered groups.

### 3. Confirm plan and messages
Ask "Split into these N commits? Rename or merge groups?" and wait. Propose Conventional Commit messages per group; user adjusts.

### 4. Soft reset
`git reset --soft HEAD~1`, check `git status`, then unstage once: `git reset HEAD`.

### 5. Commit each group
Stage the group's files (`git add <file>`); ⚡ files per `references/hunk-analysis.md` (revert other topics' lines, add, restore full content). Show `git diff --cached --stat`, confirm only this topic is staged, commit per `references/common-snippets.md#commit-template`. If a mixed file will not split cleanly, stop and ask rather than committing wrongly.

### 6. Verify
`git log --oneline -6`: the original is replaced by N focused commits. Offer `/diff-review` and `/safe-push`.

### 7. Force push (only if it was pushed)
Branch must not be protected and `git log origin/<branch> --format='%ae' | sort -u` must show only the user (`references/git-safety.md`). Protected or shared: stop, the split stays local. Otherwise show the command and implications, confirm:
`git push --force-with-lease --force-if-includes origin <branch>`

## Constraints
Only the last commit(s) can be split safely. Further back needs `git rebase -i <commit>^` (mark `edit`, `git reset HEAD^`, stage and commit in parts, `git rebase --continue`), which needs a terminal. Give those steps to the user and offer to guide them.
