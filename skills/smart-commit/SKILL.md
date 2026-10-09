---
name: smart-commit
description: Use when the user wants to commit local changes — "commit", "committen", "einchecken", "stage and commit", "nur die Fixes committen", "commit nach Themen", "commit the bugfix not the feature", or has a mixed working tree to group by topic. Owns "commit"; pushing belongs to safe-push, splitting an existing commit to commit-split.
---

# Smart Commit

Commit by topic, not by file. When one file mixes topics (bugfix and feature), split at hunk level so each commit stays focused.

## Safety
- Stage specific files or hunks, never `git add .` / `-A` (see `references/common-snippets.md#standard-safety-lines`)
- Preflight per `references/common-snippets.md#preflight`; no changes = say so and stop
- Never push from here without a secret scan (`references/git-safety.md#secret-patterns`)

## Workflow

### 1. Scan cheaply (no full diffs yet)
```bash
git status; git diff --name-only; git diff --cached --name-only
git ls-files --others --exclude-standard; git diff --stat
```
Files already staged: ask whether to include them in the grouping or leave them.

### 2. Detect topics
Follow `references/topic-detection.md` (path, then `.claude-git.yml`, then semantic reading of ambiguous diffs only). For >10 files spawn `git-superpowers:topic-analyzer`. Mark files with several topics with ⚡.

### 3. Present and choose
Numbered list `[N] Topic (X files)` with M/A/D status; explain ⚡ = split at hunk level. Ask which topics to commit ("1,3" or "all"). With several topics ask the strategy: **[s] separate commits (default)**, [c] combined, [q] quick (stage all selected, auto-message, no confirmation; for "schnell", "alles rein"). One topic: skip the question.

### 4. Stage
Single-topic files: `git add <file>`. ⚡ files: hunk-level per `references/hunk-analysis.md` (see original with `git show HEAD:<file>`, back up the file, revert other topics' lines, `git add`, restore from backup). If a mixed file will not split cleanly, stop and ask instead of committing wrongly.

### 5. Verify and message
`git diff --cached --stat`, ask "Look correct?" (wrong file: `git reset HEAD <file>`, redo). `/diff-review` first is a good idea for logic-heavy changes.

Message: Conventional Commits (`feat|fix|refactor|chore|style|docs`) with scope from the topic, matching the repo's actual style (`git log --oneline -20`). Show it; user may edit.

### 6. Commit
Per `references/common-snippets.md#commit-template`. Hook failure: nothing was committed; fix, re-stage, commit anew (never `--amend`, never `--no-verify`).

### 7. Loop and next
`git status`; more topics left: ask again. Done: offer `/diff-review`, `/safe-push` (all pushing goes there), `/pr-prep`. Quick mode: just "Committed. Run /safe-push when ready."

## Rules
- Show `git diff --cached --stat` after staging and the message before committing (except quick mode)
- Hook failure: new commit, never amend
