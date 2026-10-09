---
name: branch-inspect
description: Use when the user wants to know what teammates are doing on other branches of this repo — "was machen die anderen", "welche Branches gibt es", "wer hat was gemacht", "compare branches", "überschneidet sich mein Branch mit bb". For a single file across branches use cross-compare; for all repos use repo-overview.
---

# Branch Inspect

See who committed what on other branches and where your branch may conflict with theirs, before it happens.

## Safety
- `git fetch origin --quiet` first, stale refs make every comparison wrong
- Never run `git log` without a range or limit (`--oneline`, max 20)
- Preflight per `references/common-snippets.md#preflight`; `origin/main` below means `origin/$BASE` (`#base-branch`)

## Workflow

### 1. List branches
```bash
git fetch origin --quiet
git branch -r --sort=-committerdate --format='%(refname:short) %(committerdate:relative) %(authorname)'
```
Drop `origin/HEAD`, highlight the current branch, hide branches idle for 90+ days unless asked. Numbered list; ask which to inspect (number, name, or "compare" for overlap analysis).

### 2. Branch details
```bash
git log --oneline origin/main..origin/<branch> | head -20
git shortlog -sn origin/main..origin/<branch>
```
Commits per author, commit list, `--stat`, and a one-sentence summary of what the branch is doing.

### 3. Compare with your branch
Files both changed since the fork: `comm -12` overlap (`references/common-snippets.md#overlap`, with `origin/<branch>` as the second ref). For each overlapping file read both diffs and rate risk: **LOW** different parts (auto-merge), **MEDIUM** nearby, **HIGH** same lines. Deeper: `/conflict-simulator`; actual code: `/cross-compare`.

### 4. Recommend
Conflicts likely: sync now, wait, or coordinate merge order with the teammate. None: "No overlapping changes, merge order does not matter." Very stale branch (days idle, many commits behind): warn it will conflict when it syncs.

### 5. Multi-branch ("compare")
NxN overlap matrix of branch pairs with counts and ⚠️/✓.

### Next steps
Conflicts: `/conflict-simulator` or `/smart-sync`. Files wanted: `/selective-merge` or `/cherry-pick`. Own branch behind: `/smart-sync`.
