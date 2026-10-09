---
name: ci-fix
description: Use when CI checks or a pipeline are failing and need diagnosing — "CI is red", "checks failing", "Pipeline kaputt", "warum failed der Build", "fix the build", "Tests laufen in CI nicht durch", "GitHub Action schlägt fehl". Not for opening a PR (pr-prep) or reviewing code (diff-review).
---

# CI Fix

Pull the failing logs, isolate the real error, fix the cause, push, and confirm the checks go green.

## Safety
- Fix the cause, never the symptom: no deleted tests, `as any`, `@ts-ignore`, `--no-verify`, file-wide lint disables
- Reproduce locally before pushing a fix when the step can run locally
- Cleanup commits only, never `--amend` pushed history (`references/common-snippets.md#standard-safety-lines`)
- "CI is green" / "fixed" is only true with fresh `gh pr checks` output from this turn (`references/common-snippets.md#verification`; with superpowers installed: `superpowers:verification-before-completion`)

## Workflow

### 1. What's failing?
```bash
gh auth status >/dev/null 2>&1 || echo "gh unavailable"
gh pr checks 2>/dev/null || gh run list --branch "$(git branch --show-current)" --limit 5
```
Show a compact status per check. All green: say so and stop.

### 2. Get the failure, not the whole log
Never dump a full log.
```bash
RUN_ID=$(gh run list --branch "$(git branch --show-current)" --status failure --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --log-failed 2>/dev/null | tail -150
```
Grep further if noisy (`error|Error|FAIL|AssertionError|Traceback|npm ERR`). Identify the failed step and the FIRST error (later ones cascade). Flaky (timeouts, network, unrelated change)? `gh run rerun "$RUN_ID" --failed` is legitimate only for flakes; say which case this is and why.

### 3. Reproduce locally
Read the exact command from `.github/workflows/*.yml` (`grep -A3 -B1 '<step>' .github/workflows/*.yml`) and run it. CI-only failure: compare runtime versions, env vars, OS, and say the loop must go through CI.

### 4. Fix the cause

| Failure | Real fix | Not a fix |
|---|---|---|
| Test fails after your change | Fix the code, or the test if the contract legitimately changed | Delete/skip the test |
| Type error | Fix type or code | `as any`, `@ts-ignore` |
| Snapshot mismatch | Verify new output is correct, then update | Blind `--update-snapshots` |
| Flaky timeout | Fix the race; re-run once | Timeout of 5 minutes |

Verify locally, then commit per `references/common-snippets.md#commit-template` (`fix(ci): <what was wrong>`) and `git push origin <branch>`.

### 5. Watch
`gh pr checks --watch 2>/dev/null || gh run watch`. Green: report from that output. Red: back to step 2; after two failed attempts stop and summarize what is known instead of push-guessing.

## Rules
- One focused commit per fix attempt
- Find the FIRST error; `--log-failed`, not full logs
- Name flaky vs broken explicitly; flag silencing as silencing
