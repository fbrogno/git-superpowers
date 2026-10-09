---
name: bisect
description: Use when the user wants to find which commit introduced a bug or regression — "seit wann ist das kaputt", "which commit broke this", "regression finden", "wann ging das noch", "git bisect", "find the breaking commit". Not for reading a file's history (git-superpowers:git-history) or fixing a red pipeline (git-superpowers:ci-fix).
---

# Bisect

## Overview

Binary search over history finds the first bad commit in about log2(n) steps. The search runs in a temporary worktree, so the user's working tree, branch and uncommitted changes are never touched.

## When to Use

- Something worked before and is broken now, and the range is more than a handful of commits.
- Not for: understanding why code looks as it does (`git-superpowers:git-history`), CI failures with an obvious log (`git-superpowers:ci-fix`).

## Procedure

### 1. Fix the range

- **bad**: usually `HEAD` (confirm it really fails).
- **good**: the last known working point — user's answer, last release tag (`git describe --tags --abbrev=0`), or a date (`git rev-list -n1 --before="2 weeks ago" HEAD`).
- Verify the good commit really passes before starting; a wrong good commit gives a wrong answer.

### 2. Write the test script

Put it OUTSIDE the repo (e.g. the session scratch dir) so checkouts do not remove it. Exit codes: `0` good, `1`-`124` bad, `125` skip (cannot test this commit), `126`+ aborts the bisect.

```bash
#!/usr/bin/env bash
npm ci --silent >/dev/null 2>&1 || exit 125     # build/install broke: skip, do not blame
npm test -- path/to/failing.test.js              # exit code of the real check
```

Test the symptom, not the whole suite. Run it once on `good` and once on `bad` to prove it separates them.

### 3. Run in a temporary worktree

```bash
WT=$(mktemp -d)/bisect
git worktree add --detach "$WT" <bad>
cd "$WT"
git bisect start <bad> <good>
git bisect run /path/to/script.sh
git bisect log > /path/to/bisect.log
git bisect reset
cd - && git worktree remove "$WT"
```

Bisect state is per-worktree. Always run `git bisect reset`, also after errors or Ctrl-C. If a worktree cannot be used (user explicitly refuses), require a clean tree first (`git status --porcelain` empty) and note the starting branch for `git bisect reset`.

### 4. Handle trouble

- **Flaky test**: run the script 3 times inside it and treat any failure as bad (or any pass as good, whichever the symptom needs); say so in the report.
- **Does not build**: `exit 125`. Many skips make the result a range, not one commit; report it as such.
- **Merge-heavy history**: `git bisect start --first-parent` narrows to the merge that brought the bug.
- **Aborted run** (exit 126+): fix the script, `git bisect reset`, restart.

### 5. Report

```bash
git show --stat <first-bad-commit>
```

Give the commit, author, date, a short narrative of what changed and why that plausibly breaks the symptom, and the suggested next step (`git-superpowers:hotfix` for urgent fixes, `git-superpowers:git-undo` to revert). Verify the claim: the parent commit passes, the culprit fails.

## Quick Reference

| Need | Command |
|---|---|
| Start | `git bisect start <bad> <good>` |
| Automate | `git bisect run <script>` |
| Skip commit | script `exit 125` |
| Only merges | `--first-parent` |
| Finish | `git bisect reset` |

## Common Mistakes

- Running bisect in the user's tree with uncommitted changes.
- Test script inside the repo, deleted by a checkout.
- Treating a build failure as "bad" instead of exit 125.
- Not verifying the good commit first.
- Forgetting `git bisect reset` or leaving the temp worktree behind.
