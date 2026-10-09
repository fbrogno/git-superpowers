---
name: cross-compare
description: Use when the user wants to see how one file, module or directory differs across several branches — "vergleich die Branches", "compare X across branches", "wie sieht der Code in den anderen Branches aus", "welche Branches haben diese Datei geändert". For overall branch activity use branch-inspect.
---

# Cross-Compare

Compare a file, module or directory across all branches that touched it and forecast which branches would collide, without switching branches.

## Safety
- `git fetch origin` first; `--stat` before full diffs, full diffs only on request
- Preflight per `references/common-snippets.md#preflight`; `origin/main` below means `origin/$BASE` (`#base-branch`)
- More than 5 relevant branches: ask the user to narrow down first

## Workflow

### 1. Target
Use a named path directly. Vague term ("amazon"): resolve via `git diff --name-only origin/main | grep -i <term>` and common patterns (`src/<module>/`, `src/components/<Name>`, `src/pages/<route>`); ask when several match.

### 2. Relevant branches
```bash
git fetch origin --quiet
git branch -r --sort=-committerdate --format='%(refname:short)'      # minus origin/HEAD
git diff --name-only origin/main...origin/<branch> -- <path>          # non-empty = touched it
```
Run the per-branch diffs in one parallel Bash call. None touched it: "No branches modified `<path>`", stop.

### 3. Per-branch summary
```bash
git diff --stat origin/main...origin/<branch> -- <path>
git log --oneline origin/main..origin/<branch> -- <path>
```
Table: Branch | Commits | +Lines | -Lines | one-sentence summary.

### 4. Collision forecast
Ask git, do not compare line numbers across diverged diffs:
```bash
git merge-tree --write-tree origin/<A> origin/<B> >/dev/null 2>&1; echo $?          # 0 clean, 1 conflicts (git >= 2.38)
git merge-tree --write-tree --name-only origin/<A> origin/<B> 2>/dev/null | tail -n +2   # conflicting files
```
Git < 2.38: file-level overlap only (`references/common-snippets.md#overlap` with the two branches and `-- <path>`). Risk per pair: **HIGH** merge-tree conflicts under the path, **MEDIUM** same file but merges cleanly (semantic review wise), **LOW** separate files.

### 5. Details and recommendations
On request `git diff origin/main...origin/<branch> -- <path>` (annotate by topic with `references/hunk-analysis.md`). Recommend: sync before a conflicting branch merges; the most complete branch is the merge candidate; complementary changes merge in order. Offer `/cherry-pick` or `/branch-inspect`.
