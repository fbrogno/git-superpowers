---
name: diff-review
description: Use when the user wants their own changes checked for bugs before committing or pushing — "review my changes", "check my code", "schau dir meine Änderungen an", "review before commit", "kurz drüberschauen bevor ich pushe". Reviews your uncommitted or branch diff; for someone else's pull request by number or URL use pr-review.
---

# Diff Review

Review your changes for real problems before they become commits: logic, security, async correctness. Few findings that matter, not 20 nitpicks.

## Safety
- Never commit in this skill; the user commits when ready
- Flag correctness, security and reliability only, no style preferences, nothing a compiler or ESLint already reports
- Apply fixes directly to files instead of only describing them

For diffs over 500 lines spawn the `git-superpowers:code-reviewer` agent with the diff to keep the conversation clean.

## Workflow

### 1. Scope
`git status`; no changes: say so and stop. Staged files present: ask staged, unstaged or both (default: staged if any, else unstaged). Branch review (nothing uncommitted): use `git diff origin/<base>..HEAD` with `<base>` per `references/common-snippets.md#base-branch`. Show `git diff --stat`; if >500 lines ask whether to review all or specific files.

### 2. Read
`git diff` / `git diff --cached`. For each file understand its role (path, imports), the intent of the change, and the unchanged lines around it.

### 3. Review each file
Flag only genuine issues, not hypotheticals.

<!-- sync:review-categories — keep this category list identical to agents/code-reviewer.md -->

**Logic errors and bugs**
- Control flow that can't work as written, off-by-one errors
- Conditions always true or false, wrong operator

**Missing error handling at system boundaries**
- `fetch` / `axios` without catch, file system operations without error checks
- Database results without null handling, `JSON.parse` on external data without try/catch

**Security issues**
- SQL injection via string concatenation, XSS from unsanitized HTML
- Hardcoded secrets or credentials
- User-provided IDs used without an authorization check

**Dead code and unused imports being added**
- New imports never used, functions never called, variables never read

**Async and race conditions**
- Missing `await`, out-of-order state mutation in callbacks
- Sequential awaits where independent calls should run in parallel

**Null and undefined safety**
- Property chains on possibly null external data
- Array access without bounds check on API or user data

**Hardcoded values that belong in config**
- URLs, ports, hostnames as literals, unexplained magic numbers
- Environment-specific values baked into code

**Consistency with surrounding code**
- Only when the inconsistency would cause a real bug or is jarring

### 4. Present findings
Group by severity (🔴 CRITICAL, 🟡 WARNING, 🟢 SUGGESTION; only severities that occur). Each finding: number, `file:line`, the actual code, what is wrong and why, a concrete fix. End with counts and the code-reviewer's `verdict` (or your own equivalent) as "Ready to merge: yes | no | with fixes". No issues: say so confidently ("No significant issues found. Ready to commit.").

### 5. Fix and verify
Ask which to fix (numbers, all, skip). Read the file, apply, show the changed lines. Show the updated diff and flag any new problem a fix introduced.

### 6. Next
Offer `/smart-commit`, `/safe-push` (if already committed), or nothing.
