---
name: pr-prep
description: Use when the user wants to open, update or merge a pull request for their own branch — "PR erstellen", "PR aufmachen", "pull request", "ready for merge", "branch fertig", "PR aktualisieren", "update PR", "PR mergen". Not for reviewing someone else's PR (pr-review) or fixing red checks (ci-fix).
---

# PR Prep

Turn the branch into a reviewable pull request, or update the existing one: audit, conflict dry-run, description from the repo's template, push, create.

## Safety
- Never create a PR with conflict markers or secrets in the diff (`references/git-safety.md#secret-patterns`)
- Never rebase/force-push a branch with an open, reviewed PR without explicit confirmation (invalidates reviews, re-runs CI)
- Description must have a Test Plan; respect the repo's PR template
- Claims such as "checks pass" or "PR is mergeable" need fresh `gh pr checks` / `gh pr view` output from this turn (`references/common-snippets.md#verification`; with superpowers installed: `superpowers:verification-before-completion`)

## Workflow

### 1. Preflight
`$BASE`/`$BRANCH` per `references/common-snippets.md#base-branch`, plus `git status --porcelain` and `gh auth status`.
- Uncommitted changes: stop, suggest `/smart-commit`.
- `gh` unavailable: continue the audit, end with title+body for copy-paste.
- On `$BASE` itself: stop, offer to create a feature branch.
- User-named base (develop, release, stacked PR) overrides `$BASE`.

### 2. Existing PR?
```bash
gh pr list --head "$BRANCH" --state open --json number,title,url,reviewDecision,isDraft --jq '.[0]'
```
Exists: update mode. Offer push new commits, `gh pr edit` title/body, mark ready, status only, and `gh pr comment` summarizing changes since the last review. Skip creation below.

**Merging** (only when the user asks "PR mergen"): hard gate from fresh output of `gh pr checks <n>` and `gh pr view <n> --json mergeable,reviewDecision,statusCheckRollup`. Stop if any check is failing or pending, `mergeable != MERGEABLE`, or `reviewDecision == CHANGES_REQUESTED`. Otherwise show PR, method (`--squash`, `--rebase`, `--merge` per repo convention, `references/git-safety.md#workflow-conventions`) and check results, wait for an explicit yes, then `gh pr merge <n> --<merge|squash|rebase>`; ask whether to add `--delete-branch`. Never `--admin` to bypass failing checks.

### 3. Status and audit
```bash
git log --oneline origin/$BASE..HEAD; git log --oneline HEAD..origin/$BASE | wc -l
```
No commits ahead: "Nothing to PR". Behind: recommend `/smart-sync` first. Audit `git diff origin/$BASE..HEAD` in one pass as in `/safe-push` (debug artifacts, conflict markers, secrets, TODO/FIXME, imports of missing files, deploy-config foot-guns via `/deploy-check`). Offer **[f] fix all, [s] skip, [c] cancel**.

### 4. Conflict dry-run
```bash
git merge-tree --write-tree HEAD origin/$BASE >/dev/null 2>&1   # 0 clean, 1 conflicts
```
Git < 2.38: use the file overlap check (`references/common-snippets.md#overlap`). Conflicts: name files, recommend `/smart-sync` or `/conflict-simulator`, continue only on confirmation.

### 5. Push
`git push -u origin "$BRANCH"` before `gh pr create`. Rejected (remote has newer commits): stop and handle as in `/safe-push`, no force.

### 6. Description and create
Template first: `ls .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE/*.md docs/pull_request_template.md 2>/dev/null`. Build content from `git log --format="%s%n%b" origin/$BASE..HEAD` plus `--stat`, grouped by topic (`references/topic-detection.md`). Without a template: `## Summary` (2-4 bullets from the reader's view), `## Changes` (by topic, behavior level), `## Test Plan` (checkable steps). Show the draft; ask Draft? (default no) and Reviewers? (suggest from CODEOWNERS).

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<description>
EOF
)" --base "$BASE" --head "$BRANCH" [--draft] [--reviewer <handles>]
```

### 7. After creation
`gh pr checks "$BRANCH"`; show URL and CI status. Failing or pending: `gh pr checks --watch` or `/ci-fix`. If the repo uses "Rebase and merge", run `/smart-sync` after merge (new SHAs make the local branch diverge).

## Rules
- Detect the base, never hardcode it
- Never call `gh pr create` before the branch is pushed and current
- No duplicate PRs: check first, update instead
- Conflict check is read-only (`merge-tree`), nothing to clean up
