---
name: pr-review
description: Use when the user wants a teammate's pull request reviewed, named by number, URL or author — "review PR #123", "schau dir den PR an", "check bobby's PR", "PR reviewen", "was hältst du von dem PR". Not for your own uncommitted or branch changes (diff-review) or creating your own PR (pr-prep).
---

# PR Review

Review a teammate's PR end to end and submit an actionable review: approve, comment, or request changes. Counterpart to `/pr-prep`.

## Safety
- Never submit a review without showing the user the full draft first; the user is the reviewer of record, Claude drafts
- Criticize code, never people: concrete, actionable, with a suggested fix
- Never approve with unresolved critical findings
- Never push commits onto someone else's PR branch unless the author asked

## Workflow

### 1. Identify
`gh auth status >/dev/null 2>&1 || echo "gh unavailable"`. If the user named a PR, `gh pr view <ref>`. Otherwise list open PRs (`gh pr list --state open --json number,title,author,updatedAt,reviewDecision`) and highlight review requests (`gh pr list --search "review-requested:@me"`).

### 2. Understand (cheap first)
```bash
gh pr view <n> --json title,body,author,baseRefName,additions,deletions,changedFiles,commits
gh pr diff <n> --name-only
```
Summarize in 2-3 sentences what it claims versus what it touches; a mismatch is already a finding. Large PR (>30 files or >1000 lines): ask for focus or review riskiest files first (source over tests, logic over config).

### 3. Read
`gh pr diff <n>`. Need more context or to run tests: `gh pr checkout <n>`, remembering the previous branch and returning with `git checkout -` in step 6 (dirty tree: stash first, pop after).

### 4. Analyze
Use the categories from `/diff-review` plus PR-level checks: scope (one thing? drive-by changes), tests for new behavior, breaking changes (API, schema, config), whether the Test Plan covers the risky parts. Two findings that matter beat fifteen nitpicks.

### 5. Draft
Show the full draft: verdict (bugs/security: request changes; suggestions only: comment; clean: approve), numbered findings with severity, `file:line`, why, suggested fix, and an overall comment. Ask: approve, comment, request changes, edit, cancel.

### 6. Submit
```bash
gh pr review <n> --request-changes --body "$(cat <<'EOF'
<overall comment>
EOF
)"
```
(`--approve` or `--comment` accordingly.) Inline comments: `gh api repos/{owner}/{repo}/pulls/<n>/comments -f body='<c>' -f commit_id='<head-sha>' -f path='<file>' -F line=<line> -f side=RIGHT`. Return to the previous branch if checked out. Confirm what was submitted.

An approval states what was checked, not just "LGTM".
