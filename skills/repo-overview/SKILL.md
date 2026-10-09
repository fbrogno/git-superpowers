---
name: repo-overview
description: Use when the user wants the state of all their repositories at once — "wo steh ich überall", "welche Repos sind behind", "was hab ich offen", "repo status", "status aller Projekte", "uncommitted changes in allen Repos". For a single repo's branches use branch-inspect.
---

# Repo Overview

Scan all git repositories and show a dashboard: branch, ahead/behind, uncommitted changes. Then offer actions per repo.

## Safety
- Never batch-sync all repos; each sync needs individual attention
- Confirm before destructive operations; handle repos without remote or in detached HEAD gracefully

## Workflow

### 1. Find repos (stop at the first source that yields results)
1. Context: CLAUDE.md, memory, conversation, cwd and its sibling directories.
2. `.claude-git.yml` `scan_dirs` (current or home directory).
3. Linux `locate -r '/\.git$' | grep "^$HOME"` with noise filtered (node_modules, caches, Trash, `.claude/plugins`).
4. macOS default (Spotlight does not index `.git`, so no `mdfind`): pruned find.
```bash
find ~ -maxdepth 4 \( -name node_modules -o -name Library -o -name .Trash -o -name .npm -o -name .nvm -o -name .cache -o -name Caches -o -path "*/.claude/plugins" \) -prune -o -type d -name .git -print 2>/dev/null | sed 's/\/.git$//' | sort -u
```
More than 20 repos: only those with commits in the last 30 days.

### 2. Gather status in ONE Bash call
More than 5 repos: spawn `git-superpowers:repo-scanner`. Otherwise fetch in parallel, then collect:
```bash
for path in <repos>; do git -C "$path" fetch origin --quiet 2>/dev/null & done; wait
for path in <repos>; do
  name=$(basename "$path"); branch=$(git -C "$path" branch --show-current 2>/dev/null || echo detached)
  base=$(git -C "$path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@'); [ -z "$base" ] && base=main
  behind=$(git -C "$path" rev-list --count HEAD..origin/$base 2>/dev/null || echo "?")
  ahead=$(git -C "$path" rev-list --count origin/$base..HEAD 2>/dev/null || echo "?")
  changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last=$(git -C "$path" log -1 --format='%cr' 2>/dev/null || echo "no commits")
  echo "$name|$branch|$behind|$ahead|$changes|$last|$(git -C "$path" remote get-url origin 2>/dev/null || echo 'no remote')"
done
```
Edge cases: no remote shows "no remote" instead of numbers; detached HEAD shows the hash; fetch failure shows last known state with "(offline)".

### 3. Dashboard
Table: Repo, Branch, Behind, Ahead, Changes, Last Commit. ⚠️ behind, ✓ current; problem repos first; summary line of repos needing attention. About 2 lines per repo, no diffs.

### 4. Actions
Ask: pick a repo, `sync <repo>` (smart-sync), `details <repo>` (last 5 commits, uncommitted files, diff --stat), `commit <repo>` (smart-commit), `done`. `cd` into the repo for the action, then re-scan that repo and show the updated dashboard.

### 5. Remote repos not cloned (optional)
If `gh auth status` works, list own and org repos (`gh repo list --limit 1000`, plus `gh api user/orgs` and `gh repo list <org>`; a bare `gh repo list` only shows the user's own) and show those missing locally. Clone on request into the common parent of existing repos. Local repos whose remote points to an org the user is not a member of: list separately as "via remote URL", never label the user's role. Skip silently without `gh`.

### 6. Suggest
Behind: `/smart-sync`. Uncommitted: `/smart-commit`. All clean: "All repos look good."
