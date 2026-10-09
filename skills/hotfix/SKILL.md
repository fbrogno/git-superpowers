---
name: hotfix
description: Emergency fix — stash work, branch from main, fix, audit, PR, return to previous branch. Triggers: hotfix, "production is broken", "notfall", "prod ist down", "dringend", "kritischer bug", /hotfix.
---

# Hotfix

Apply an emergency fix to production without contaminating your in-progress work. This workflow is optimized for speed — it minimizes questions and moves in a straight line from broken to fixed.

## Safety (always apply — even under time pressure)
- Secret scan and conflict marker check are non-negotiable
- Never `git add .` — stage specific files only
- Always start hotfix from the freshly fetched production branch (`origin/$BASE`), never from a feature branch
- Always return user to their original branch at the end
- See `references/git-safety.md` for secret patterns

## Workflow

### Step 1: Save Your Current Work

First, record the current branch name — you need it in Step 8 to return.

```bash
PREVIOUS_BRANCH=$(git branch --show-current)
```

Then, protect whatever you're in the middle of so nothing gets lost.

```bash
git status --porcelain
```

If there are uncommitted changes:
```bash
git stash push -u -m "hotfix: park work before switching to hotfix branch $(date +%Y-%m-%d-%H%M)"
```

Confirm: "Stashed your current work. It'll be waiting when you return."

If the working tree is clean: "Nothing to stash — workspace is clean."

### Step 2: Create Hotfix Branch from the Production Branch

Fetch first and determine where production lives. Default: the repo's default branch. If the repo has a `production` or `release/*` branch that deploys, use that instead — a hotfix must branch from what is actually deployed:

```bash
git fetch origin
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@'); [ -z "$BASE" ] && BASE=main
git branch -r | grep -E 'origin/(production|release/)' || true
```

Ask for a short description of the issue (used in the branch name):
```
What's broken? (brief, e.g. "login-crash" or "checkout-404")
```

Sanitize the input — lowercase, spaces to hyphens, remove special characters.

```bash
git checkout -b hotfix/<description> origin/$BASE
```

Confirm:
```
Hotfix branch created: hotfix/<description>
Starting from: origin/<base> (latest)
```

### Step 3: Apply the Fix

Tell the user: "Make your fix now. I'll wait."

Then assist with the fix if asked. When the user signals they're done (or commits manually), continue.

If Claude is helping write the fix:
- Read the relevant files first
- Make targeted, minimal changes — hotfixes should be surgical, not sweeping
- Avoid refactoring alongside the fix; that belongs in a normal branch

### Step 4: Audit the Fix

Even under time pressure, do a focused audit on the outgoing diff. A bad hotfix to production is worse than a slightly delayed one.

Run against `git diff origin/$BASE..HEAD`:

**Conflict markers** (would cause syntax errors in production):
```bash
git diff origin/$BASE..HEAD | grep -n "^+.*<<<<<<\|^+.*======\|^+.*>>>>>>"
```

**Secret patterns** — scan for patterns from `references/git-safety.md`. Block if found.

**Debug artifacts**:
- `console.log`, `debugger` in the fix

**Scope check**: Is this change minimal? If the diff is large (>10 files or >200 lines), flag it:
```
This diff is large for a hotfix (12 files, +245 lines).
Hotfixes should be targeted — large changes introduce new risk.
Are you sure this is all necessary for the emergency fix? (y/n)
```

If any issues are found, offer to fix them inline before committing.

### Step 5: Commit the Fix

Use a `fix:` prefix — this is required for semantic versioning pipelines to recognize hotfixes.

Propose a commit message from the branch name and diff:
```bash
git diff --stat origin/$BASE..HEAD
```

```
Proposed commit message:

fix(<scope>): <description of what was fixed>

OK, or change it?
```

Commit with HEREDOC format:
```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
fix(<scope>): <description>

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
```

Never use `git add .` — stage specific files only (safety rule).

### Step 6: Push the Hotfix Branch

```bash
git push origin hotfix/<description>
```

If push fails due to remote changes:
```bash
git pull --rebase origin hotfix/<description>
```

Then retry the push. Hotfix branches are new so this should never happen, but handle it anyway.

### Step 7: Create the PR

Create a PR to main with a HOTFIX label so it's visible in the review queue.

First, check if `gh` CLI is available:
```bash
gh auth status >/dev/null 2>&1 && echo ok || echo unavailable
```

If not available: push the branch and create the PR manually at the GitHub web interface. Skip to Step 8.

If available:
```bash
gh pr create \
  --title "fix: <description>" \
  --body "$(cat <<'EOF'
## HOTFIX

**Problem:** <what was broken in production>

**Fix:** <what was changed and why it resolves the issue>

## Changes
<diff summary>

## Test Plan
- [ ] Verify the fix resolves the reported issue
- [ ] Confirm no regressions in adjacent functionality
- [ ] Check production logs after deploy

🚨 This is a hotfix — please review and merge promptly.
EOF
)" \
  --base "$BASE" \
  --label "hotfix"
```

If the `hotfix` label doesn't exist yet (`gh` returns an error), create the PR without it and note: "Label 'hotfix' not found — add it manually on GitHub if needed."

Show the PR URL:
```
Hotfix PR created: https://github.com/<org>/<repo>/pull/<number>
Share this with reviewers now.
```

### Step 8: Return to Your Previous Work

Ask: **"Switch back to your previous branch?"**

Default is yes — suggest the branch the user was on before.

```bash
git checkout <previous-branch>
```

If a stash was created in Step 1:
```bash
git stash pop
```

Confirm:
```
Back on <previous-branch>. Your stashed work has been restored.
```

If `git stash pop` conflicts (rare but possible — stash was made before a file the hotfix touched):
```
Stash conflict in <file>. Your stashed changes and the hotfix both touched this file.
Let me help you resolve it.
```

Run the conflict resolution from `references/conflict-resolution.md`.

### Step 9: Remind About Post-Merge Sync

After the hotfix PR is merged, the main branch will have changed. Remind the user:

```
After the hotfix is merged to main, sync your branches:

What's next?
[s] Run /smart-sync on <previous-branch> to get the fix into your work
[o] Run /repo-overview to sync all repos
[d] Done — I'll sync later

Syncing prevents conflicts later and ensures your branches build on the fixed production code.
```

## Rules

- Always stash before branching — never risk losing in-progress work
- Always start the hotfix branch from the freshly fetched production branch, never from a feature branch
- The secret scan is mandatory even under time pressure — a leaked key in a hotfix is a catastrophe
- Commit message must use `fix:` prefix — hotfixes go through the same semantic versioning as everything else
- Always return the user to their original branch at the end — leave the workspace as found
- Always remind about post-merge sync — the hotfix changes main, and all branches need to know
