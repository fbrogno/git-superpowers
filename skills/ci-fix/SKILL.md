---
name: ci-fix
description: Diagnose and fix failing CI checks — fetch failing run logs via gh, find the root cause, fix, push, re-watch. Triggers: "CI is red", "checks failing", "pipeline kaputt", "warum failed der build", "fix the build", "tests laufen nicht durch", /ci-fix.
---

# CI Fix

A PR with red checks doesn't get reviewed. This skill pulls the failing logs, isolates the actual error (not the 400 lines of noise around it), fixes the cause, and pushes — then watches the checks go green.

## Safety (always apply)
- Fix the cause, never the symptom — deleting a failing test or adding `--no-verify` is not a fix
- Never push a "fix attempt" without running the failing check locally first, when it can run locally
- Cleanup commits, never `--amend` on pushed history
- Adapt verbosity to the user (see Adaptive Output in `references/git-safety.md`)

## Workflow

### Step 1: What's Failing?

```bash
gh auth status >/dev/null 2>&1 || echo "gh unavailable"
gh pr checks 2>/dev/null || gh run list --branch "$(git branch --show-current)" --limit 5
```

No PR yet → use the run list for the branch. Show a compact status:

```
Checks for #142:
  ✓ lint            (32s)
  ✗ test            (2m 11s)  ← failing
  ✗ build           (1m 40s)  ← failing
  ○ deploy-preview  (skipped)
```

If everything is green: say so, done.

### Step 2: Get the Failure — Not the Whole Log

CI logs are huge; never dump a full log into the conversation. Fetch only the failed steps:

```bash
RUN_ID=$(gh run list --branch "$(git branch --show-current)" --status failure --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --log-failed 2>/dev/null | tail -150
```

If `--log-failed` output is still noisy, grep it for the first real error before reading further (`error|Error|FAIL|✗|AssertionError|Traceback|npm ERR`). Identify:

- **Which step failed** (test? build? lint? typecheck?)
- **The first error** — later errors are usually cascade noise
- **Deterministic or flaky?** If the log shows timeouts/network errors and the code change is unrelated, check whether a re-run passes before touching code:
  ```bash
  gh run rerun "$RUN_ID" --failed
  ```
  A re-run is legitimate for flakes, never for real failures — say which one this is and why.

### Step 3: Reproduce Locally (when possible)

Map the failing CI step to its local command — read `.github/workflows/*.yml` for the exact command the step runs (npm test, pytest, tsc, eslint, …):

```bash
grep -A3 -B1 '<failing-step-name>' .github/workflows/*.yml
```

Run that command locally. Local reproduction confirms the diagnosis and makes the fix verifiable without burning CI cycles. If it only fails in CI (env-dependent): compare versions (`node --version` vs. the workflow's matrix), env vars, OS differences — and say clearly that the loop has to go through CI.

### Step 4: Fix the Cause

Standard debugging discipline: understand why it fails before editing. Typical cases and their honest fixes:

| Failure | Real fix | Not a fix |
|---|---|---|
| Test fails after your change | Your code broke the contract — fix code, or fix test if the contract legitimately changed | Deleting/skipping the test |
| Type error | Fix the type or the code | `as any`, `@ts-ignore` |
| Lint error | Fix the code | Disabling the rule file-wide |
| Snapshot mismatch | Verify new output is CORRECT, then update snapshot | Blind `--update-snapshots` |
| Flaky timeout | Re-run; if recurring, fix the race/timeout | Raising the timeout to 5 minutes |

Verify locally (the Step 3 command passes), then commit and push:

```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
fix(ci): <what was actually wrong>

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
git push origin <branch>
```

### Step 5: Watch It Go Green

```bash
gh pr checks --watch 2>/dev/null || gh run watch
```

Green → confirm: "All checks passing ✓". Still red → back to Step 2 with the new log; after two failed fix attempts, stop and summarize what's known instead of push-guessing.

## Rules

- One fix attempt = one focused commit — no "try things" commit chains
- Read `--log-failed`, never full logs; find the FIRST error
- Distinguish flaky from broken explicitly, and say which one it is
- A fix that only makes CI silent (skip, ignore, any-cast) gets flagged as such, not sold as a fix
- After two failed attempts: stop, summarize findings, involve the user
