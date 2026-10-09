---
name: repo-overview
description: Multi-repo dashboard — branch status, ahead/behind, uncommitted changes across all repos. Triggers: repo status, "wo steh ich überall", "welche repos sind behind", "was hab ich offen", /repo-overview.
---

# Repo Overview

Scan all your git repositories and show a dashboard with branch status, ahead/behind counts, and uncommitted changes. Then offer to take action on any repo.

## Safety (always apply)
- Never batch-sync all repos — each sync needs individual attention
- Confirm before destructive operations
- Handle repos without remote or in detached HEAD gracefully

## Workflow

### Step 1: Find Repositories

Use these sources in order — stop as soon as you have results:

**1. Context (fastest):** Check if you already know where repos are — from CLAUDE.md, memory, the current conversation, or the current working directory. If the user is in a git repo, check sibling directories too.

**2. Config:** If `.claude-git.yml` exists in the current or home directory with `scan_dirs`, use those paths.

**3. Linux locate (fast, uses index):**
```bash
locate -r '/\.git$' 2>/dev/null | grep "^$HOME" \
  | grep -v 'node_modules\|\.cache\|\.claude/plugins\|Library\|\.Trash\|\.npm\|\.nvm\|Caches' \
  | sed 's/\/.git$//' | sort -u
```

**4. Filesystem scan (macOS default — Spotlight does NOT index hidden dirs like `.git`, so `mdfind` finds nothing; pruned `find` is the reliable way):**
```bash
find ~ -maxdepth 4 \
  \( -name node_modules -o -name Library -o -name .Trash -o -name .npm \
     -o -name .nvm -o -name .cache -o -name Caches -o -path "*/.claude/plugins" \) -prune \
  -o -type d -name ".git" -print 2>/dev/null | sed 's/\/.git$//' | sort -u
```

`-prune` skips whole subtrees instead of filtering results afterwards — on a big home directory that's the difference between ~2s and ~30s.

Keep the list manageable — if more than 20 repos are found, show only those with recent activity (committed within last 30 days).

### Step 2: Gather Status

For many repos (>5), spawn the `git-superpowers:repo-scanner` agent with the list of repo paths. It handles parallel fetching and status collection in minimal bash calls.

IMPORTANT: Gather ALL repo data in ONE single Bash call. Do NOT run separate Bash calls per repo — that wastes time and tokens. Use this pattern:

```bash
# Fetch all repos in parallel first
for path in /path/to/repo1 /path/to/repo2 /path/to/repo3; do
  git -C "$path" fetch origin --quiet 2>/dev/null &
done
wait

# Then collect all status in one loop
for path in /path/to/repo1 /path/to/repo2 /path/to/repo3; do
  name=$(basename "$path")
  branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")
  base=$(git -C "$path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
  [ -z "$base" ] && base=main
  behind=$(git -C "$path" rev-list --count HEAD..origin/$base 2>/dev/null || echo "?")
  ahead=$(git -C "$path" rev-list --count origin/$base..HEAD 2>/dev/null || echo "?")
  changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last=$(git -C "$path" log --oneline -1 --format='%cr' 2>/dev/null || echo "no commits")
  remote_url=$(git -C "$path" remote get-url origin 2>/dev/null || echo "no remote")
  echo "$name|$branch|$behind|$ahead|$changes|$last|$remote_url"
done
```

This runs everything in ONE Bash call and outputs a parseable table. The parallel fetch at the top ensures all repos are up to date before reading status. The per-repo `$base` detection handles repos whose default branch isn't `main`.

Handle repos without a remote — show "no remote" instead of numbers.

### Step 3: Display Dashboard

Format as a table with columns: Repo, Branch, Behind, Ahead, Changes, Last Commit. Use ⚠️ for repos behind main, ✓ for up-to-date. Sort by: repos with issues first (behind, uncommitted changes), then clean repos. End with a summary line counting repos that need attention.

### Step 4: Offer Actions

Ask: **"Want to do something? Pick a repo number, or:"**
- **"sync <repo>"** → run smart-sync for that repo
- **"details <repo>"** → show last 5 commits, list uncommitted files, diff --stat
- **"commit <repo>"** → run smart-commit for that repo
- **"done"** → exit

When the user selects an action, `cd` into that repo and invoke the appropriate workflow.

### Step 5: Return to Dashboard

After completing an action, show the updated dashboard to reflect changes (re-scan the affected repo).

### Step 6: Remote Repos (not cloned locally)

After showing local repos, check if `gh` CLI is available and authenticated:

```bash
gh auth status 2>/dev/null
```

If available, list repos from the user's GitHub organizations that aren't cloned locally. Note: `gh repo list` without an argument only lists the user's OWN repos — org repos need the org name:

```bash
# Own repos + each org's repos
gh repo list --limit 1000 --json nameWithOwner,updatedAt --jq '.[] | "\(.nameWithOwner) \(.updatedAt)"'
for org in $(gh api user/orgs --jq '.[].login' 2>/dev/null); do
  gh repo list "$org" --limit 1000 --json nameWithOwner,updatedAt --jq '.[] | "\(.nameWithOwner) \(.updatedAt)"'
done
```

Compare with local repos (by name matching). Show repos that exist on GitHub but not locally:

```
Remote Repos (not cloned locally):

  Org/Repo                    Last Update
  ──────────────────────────────────────────
  myorg/new-service           2 days ago
  myorg/internal-tools        1 week ago
  myorg/legacy-api            3 months ago

  3 repos in your organizations are not cloned locally.
  Clone? (number or "skip")
```

If the user selects a repo to clone, ask the user where to clone, suggesting the common parent directory of existing local repos, and run `git clone`.

Only show this section if there are actually uncloned repos. Skip silently if `gh` is not available or not authenticated — this is an optional bonus feature.

### Repos from Other Orgs (detected via remote URL)

Some local repos may point to organizations the user isn't a member of (e.g., external collaborator). Detect these by checking remote URLs:

```bash
for path in $REPOS; do
  remote_url=$(git -C "$path" remote get-url origin 2>/dev/null)
  # Extract org from URL
done
```

Present these separately from confirmed org memberships:

```
Repos from Other Orgs (via remote URL):

  external-org (not an org member, but local repos exist):
    repo-a, repo-b
```

Never label these as "Collaborator" or assume the user's role — just state the fact that local repos point to this org.

## Next Steps

After the dashboard, proactively suggest actions based on the data:

- If repos are behind main: "X repos are behind main. Run `/smart-sync` on them?"
- If repos have uncommitted changes: "X repos have uncommitted work. Want to commit? (`/smart-commit`)"
- If everything is clean: "All repos look good. ✓"

## Token Efficiency

The entire dashboard scan uses ~2 lines of output per repo. For 10 repos, that's ~20 lines total. No diffs are read unless the user asks for details.

## Edge Cases

- **Repo without remote**: Show "no remote" in Behind/Ahead columns
- **Repo on the default branch**: Behind/Ahead still applies — it compares to `origin/<default>`, i.e. unpulled/unpushed commits
- **Detached HEAD**: Show the commit hash instead of branch name
- **Fetch fails**: Show last known state, note "(offline)" next to the repo
- **Non-standard main branch**: Use `git symbolic-ref refs/remotes/origin/HEAD` to detect
