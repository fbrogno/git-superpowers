---
name: pr-prep
description: Audit branch, generate PR description from commits, create or update the PR via gh CLI — with template, draft, reviewer and base-branch support. Triggers: "PR erstellen", "pull request", "ready for merge", "branch fertig", "PR aufmachen", "PR aktualisieren", "update PR", /pr-prep.
---

# PR Prep

Turn your branch into a clean, reviewable pull request — or update the one that already exists. This skill audits for issues, checks for conflicts with the base branch, generates a description that follows the repo's template, pushes the branch, and creates the PR.

## Safety (always apply)
- Never create a PR with conflict markers or secrets in the diff (see `references/git-safety.md` for patterns)
- Always run the conflict dry-run — reviewers will notice conflicts
- Never rebase/force-push a branch with an open, reviewed PR without explicit confirmation — it invalidates review context and re-triggers CI
- PR description must have a Test Plan section
- Adapt verbosity to the user (see Adaptive Output in `references/git-safety.md`)

## Workflow

### Step 1: Preflight

Run in one Bash call:

```bash
git fetch origin
BRANCH=$(git branch --show-current)
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null && BASE=main || BASE=master; }
git status --porcelain
gh auth status >/dev/null 2>&1 && echo "gh:ok" || echo "gh:unavailable"
```

- **Uncommitted changes** → stop: "Commit or stash first — run /smart-commit, or: `git stash push -u -m 'pr-prep: before audit'`"
- **`gh:unavailable`** → continue through the audit, but end with title + description formatted for copy-paste instead of creating the PR. If `gh` is installed but not authenticated, say so: `gh auth login` fixes it.
- **On the base branch itself** (`$BRANCH` = `$BASE`) → stop: PRs need a feature branch. Offer to create one from the current state.
- **Base override:** If the user targets a different base (`develop`, a release branch, or another feature branch for a stacked PR), set `$BASE` accordingly — everything below uses `$BASE`, never a hardcoded `main`.

### Step 2: Does a PR Already Exist?

```bash
gh pr list --head "$BRANCH" --state open --json number,title,url,reviewDecision,isDraft --jq '.[0]'
```

**If a PR exists → switch to update mode:**

```
PR #142 already exists for this branch: "feat: amazon dashboard" (review: CHANGES_REQUESTED)

[1] Push new commits to the PR (updates it automatically)
[2] Also update title/description (gh pr edit)
[3] Mark ready for review (currently draft)
[4] Just show me the PR status
```

In update mode: skip Step 6's create, push the new commits (Step 5), then `gh pr edit` if requested. If the PR has reviews and the user wants to rebase, warn first (see Safety). Offer `gh pr comment` to summarize what changed since the last review — reviewers shouldn't have to re-read the whole diff.

**If no PR exists** → continue.

### Step 3: Branch Status + Audit

```bash
git log --oneline origin/$BASE..HEAD
git log --oneline HEAD..origin/$BASE | wc -l
```

If no commits ahead: "Nothing to PR." Stop. Show the outgoing commits (these become the PR).

If behind `$BASE`: warn — reviewers may see conflicts; recommend /smart-sync first (re-fetch after). Skip only on explicit confirmation.

Then audit `git diff origin/$BASE..HEAD` in a single pass (same checks as safe-push): debug artifacts, conflict markers, secret patterns (`references/git-safety.md`), TODO/FIXME in new code, imports referencing files missing from the branch — and if the diff touches deploy configs, the deploy foot-guns from safe-push Check 6 (hardcoded host ports, `container_name:`, `:latest`; deeper analysis via `/deploy-check`). If issues found, list them numbered and offer: **[f] Fix all  [s] Skip  [c] Cancel**.

### Step 4: Conflict Dry-Run

Read-only simulation against the base:

```bash
git merge-tree --write-tree HEAD origin/$BASE >/dev/null 2>&1   # 0 = clean, 1 = conflicts
```

Fallback for git < 2.38 — file overlap:
```bash
MERGE_BASE=$(git merge-base HEAD origin/$BASE)
comm -12 \
  <(git diff --name-only $MERGE_BASE..HEAD | sort) \
  <(git diff --name-only $MERGE_BASE..origin/$BASE | sort)
```

Conflicts predicted → name the files, recommend /smart-sync (or /conflict-simulator for detail), continue only on confirmation. Clean → say so in one line.

### Step 5: Push the Branch

`gh pr create` needs the branch on the remote — push before creating, never assume:

```bash
git rev-parse --verify -q origin/$BRANCH >/dev/null \
  && git log --oneline origin/$BRANCH..HEAD \
  || echo "no upstream"
git push -u origin "$BRANCH"
```

If the push is rejected because the remote branch has newer commits (someone else pushed to it), stop and run the remote-changes handling from safe-push — do not force-push here.

### Step 6: Generate Description + Create

**Template first:** check for a repo template and use its structure if present — teams with a required template will reject free-form bodies:

```bash
ls .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
   .github/PULL_REQUEST_TEMPLATE/*.md docs/pull_request_template.md 2>/dev/null
```

Build the content from the commits (`git log --format="%s%n%b" origin/$BASE..HEAD` + `git diff --stat origin/$BASE..HEAD`), grouped by topic (`references/topic-detection.md`). No template → use this structure:

```markdown
## Summary
- <what changed, from the reader's perspective — 2-4 bullets>

## Changes
### <Topic>
- <component/behavior level, not file level>

## Test Plan
- [ ] <concrete verification steps a reviewer can run>
```

Show the draft; let the user edit title and body. Title: from the most significant commit, in the repo's commit style. Then ask two quick options in one question: **Draft PR?** (default no; yes if work-in-progress) and **Reviewers?** (suggest from `CODEOWNERS` if present; skip if none).

```bash
gh pr create \
  --title "<title>" \
  --body "$(cat <<'EOF'
<description>
EOF
)" \
  --base "$BASE" \
  --head "$BRANCH" \
  [--draft] [--reviewer <handles>]
```

### Step 7: After Creation

```bash
gh pr checks "$BRANCH" 2>/dev/null
```

Show the PR URL and CI status. If checks are failing or pending, offer to watch them (`gh pr checks --watch`) or diagnose failures with /ci-fix. Suggest next steps:

```
PR created: <url>   (checks: 2 pending)

- Reviewers notified: <handles or "add on GitHub">
- When checks fail: /ci-fix
- After merge: /smart-sync your other branches
```

**Note on GitHub Rebase:** If the repo uses "Rebase and merge", GitHub creates new commit SHAs even for identical changes — after merge, your local branch diverges from the base although the code is the same. Run /smart-sync after merge to clean up.

## Rules

- Never hardcode the base branch — detect it, and honor user overrides (develop, release/*, stacked PRs)
- Never call `gh pr create` before the branch is pushed and up to date on origin
- Never create a duplicate PR — check for an existing one first and update it instead
- Never create a PR with conflict markers in the diff
- Respect `.github/PULL_REQUEST_TEMPLATE.md` when it exists
- The PR description must have a Test Plan section — reviewers need to know what to verify
- The conflict check uses read-only `git merge-tree` — no cleanup needed
