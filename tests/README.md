# Tests

## Skill trigger tests (manual, opt-in, cost money)

Check that realistic prompts make Claude invoke the right git-superpowers skill (and that
conceptual questions invoke none). Each run starts `claude -p` in an empty temp git repo with
`--plugin-dir <repo>`, only the `Skill` tool available (`--tools Skill`, `--permission-mode dontAsk`),
and inspects the stream-json output for a `Skill` tool_use.

Requirements: `claude` CLI on PATH, logged in. Every prompt is a real model call.

```bash
tests/triggers/run.sh safe-push tests/triggers/prompts/safe-push/1-de.txt   # one prompt
tests/triggers/run.sh --none tests/triggers/negative/1-de-explain-rebase.txt # negative
tests/triggers/run-all.sh                 # everything
tests/triggers/run-all.sh hotfix ci-fix   # selected skills (no negatives)
```

Env: `TRIGGER_MODEL` (e.g. `haiku` to save cost), `TRIGGER_MAX_TURNS` (default 3), `TRIGGER_MAX_BUDGET` (USD per run, default 0.50).
Exit codes: 0 pass, 1 fail, 3 claude unavailable / no output.
Add prompts as `tests/triggers/prompts/<skill>/<n>-<lang>.txt`; negatives in `tests/triggers/negative/`.
Note: model behavior is non-deterministic - re-run a failing prompt before treating it as a regression.

## Static validation (free, runs in CI)

```bash
python3 scripts/validate.py [--strict]   # structure, descriptions, word budgets, version sync, cross-refs
bash scripts/lint-shell.sh --all         # shellcheck + bash -n
bash scripts/bump-version.sh --check     # version drift across manifests
bash hooks/test-git-guard.sh             # guard hook tests
```
