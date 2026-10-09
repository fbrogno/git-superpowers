---
name: cherry-pick
description: Use when the user wants specific commits from another branch applied to the current one — "cherry-pick", "hol den Fix von", "nimm den Commit von", "grab that bugfix from bb". For whole files rather than commits use selective-merge.
---

# Cherry-Pick

Apply specific commits from another branch without bringing everything else. Right when a branch has one useful fix but is not ready to merge.

## Safety
- Show `git show --stat` before applying; no silent picks; never `cherry-pick -n` silently
- Offer `--abort` while a pick is in progress
- Pick oldest first to respect dependencies; always use `-x` so the source stays traceable
- Preflight per `references/common-snippets.md#preflight`; `origin/main` below means `origin/$BASE` (`#base-branch`)

## Workflow

### 1. Source branch
User named one: use it. Otherwise `git fetch origin --quiet` and list remote branches by recent commit (`git branch -r --sort=-committerdate --format='%(refname:short) %(committerdate:relative) %(authorname)' | grep -v HEAD`). `/branch-inspect` helps find the right commits.

### 2. Candidates
`git log --oneline origin/$BASE..origin/<source>`, indexed. Ask which (numbers, hash, or description like "the bugfix"; confirm natural-language matches).

### 3. Preview
`git show <hash> --stat` per commit, ask "Apply? (y / d full diff / n skip)".

### 4. Duplicate check
```bash
git cherry HEAD origin/<source> | grep '^-'                    # '-' = equivalent patch already in HEAD
git log --oneline --grep="<subject>" origin/$BASE..HEAD       # softer signal
```
`git cherry` compares patch content, so a `-` means the change is already on the branch. Warn and ask before a possible duplicate.

### 5. Apply
```bash
ORIGINAL_TIP=$(git rev-parse HEAD)
git cherry-pick -x <hash>
```
Confirm each pick. On conflict: list `git diff --name-only --diff-filter=U`, offer keep mine, take incoming, combine (see `references/conflict-resolution.md`), show conflict, or `git cherry-pick --abort`. Then `git add <files>` and `git cherry-pick --continue`.

### 6. Verify
`git log --oneline origin/$BASE..HEAD` and `git diff --stat $ORIGINAL_TIP..HEAD`; summarize what was applied.

### 7. Push (optional)
Pushing goes through `/safe-push` (fetches and audits first). Heads-up: when the source branch merges later, a rebase may stop on a now-empty duplicate; `git rebase --skip` is the answer.
