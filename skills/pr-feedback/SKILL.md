---
name: pr-feedback
description: Use when a teammate left review comments on the user's own pull request and they need to be worked through — "review kommentare abarbeiten", "bobby hat kommentiert", "feedback einarbeiten", "address PR feedback", "resolve review comments", "changes requested". Not for reviewing someone else's PR (git-superpowers:pr-review) or failing CI (git-superpowers:ci-fix).
---

# PR Feedback

## Overview

Review feedback is a set of claims to verify, not orders to execute. Understand every comment first, fix what is right, push back with a technical reason on what is not, and reply where the reviewer will see it. This is the counterpart to `git-superpowers:pr-review`. If `superpowers:receiving-code-review` is installed, follow its rules for evaluating feedback alongside this procedure.

## When to Use

- The user's PR has comments, inline threads or a "changes requested" decision.
- Not for: reviewing a PR (`git-superpowers:pr-review`), red pipelines (`git-superpowers:ci-fix`), creating or updating the PR text (`git-superpowers:pr-prep`).

## Procedure

### 1. Collect everything unresolved

```bash
gh pr view --json number,reviewDecision,reviews,comments   # current branch's PR; add <n> for another
OWNER=$(gh repo view --json owner --jq .owner.login); REPO=$(gh repo view --json name --jq .name)
gh api "repos/$OWNER/$REPO/pulls/<n>/comments" --paginate   # inline comments (id, path, line, body)
gh api graphql --paginate -f query='
query($o:String!,$r:String!,$n:Int!,$endCursor:String){repository(owner:$o,name:$r){pullRequest(number:$n){
  reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{id isResolved isOutdated path line
    comments(first:20){nodes{databaseId author{login} body}}}}}}}' \
  -f o="$OWNER" -f r="$REPO" -F n=<n> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)'
```

The GraphQL `id` is the thread id (for resolving); `databaseId` of the first comment is the id for replies. Outdated threads (`isOutdated`) may already be fixed by later commits — check before acting.

### 2. Classify every item

Read all items before touching code; items can be related.

| Class | Meaning | Action |
|---|---|---|
| Clear + correct | Verified against the code | Implement |
| Unclear | Ambiguous, or you cannot tell what is wanted | Ask the reviewer; implement nothing from it yet |
| Disagree | Technically wrong for this codebase | Reply with the reason (evidence, not opinion) |
| "Implement properly" / add feature | Reviewer suggests extra functionality | YAGNI check: `grep -rn "<symbol>"` — unused → propose removing instead of building |

Show the user the classification table. Clarify all unclear items BEFORE implementing any — a misread comment can change how the clear ones should be solved.

### 3. Implement one at a time

Order: blocking issues (bugs, security, breakage) → simple fixes → complex refactors. After each fix run the relevant tests; one logical fix per commit (`git-superpowers:smart-commit`), so each reply can point to a commit SHA.

### 4. Push first, then reply

Run `git-superpowers:safe-push` before replying, so every reply can cite a SHA that exists on the remote (`git rev-parse --short HEAD`).

```bash
gh api -X POST "repos/$OWNER/$REPO/pulls/<n>/comments/<comment-id>/replies" -f body="Fixed in abc1234 — null case now returns early."
gh pr comment <n> --body "..."    # only for top-level conversation comments
```

State the fix or the reasoning, nothing more. No "You're absolutely right!", no thanks-spam, no apologies. For disagreements: facts, the code location, and an offer to change if the reviewer sees a case you missed.

### 5. Resolve only what is fixed (after the push and the reply)

```bash
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id="<thread-id>"
```

Leave disagreements and open questions unresolved — the reviewer closes them.

### 6. Re-request review

```bash
gh pr edit <n> --add-reviewer <login>    # re-requests review from someone who already reviewed
```

## Quick Reference

| Need | Command |
|---|---|
| Review decision | `gh pr view --json reviewDecision` |
| Unresolved threads | GraphQL `reviewThreads` + `isResolved` |
| Reply | `POST pulls/<n>/comments/<id>/replies` |
| Resolve | `resolveReviewThread` mutation |
| Re-request | `gh pr edit --add-reviewer` |

## Common Mistakes

- Implementing the easy comments before clarifying the unclear ones.
- Resolving threads for items that were only answered, not fixed.
- Replying with agreement phrases instead of the fix and its commit.
- Adding features a reviewer hinted at without checking that anything uses them.
- Forgetting the re-request, so the reviewer never learns the PR changed.
- Missing the 100-item limit: the query above paginates with `--paginate` and `$endCursor`; keep both.
