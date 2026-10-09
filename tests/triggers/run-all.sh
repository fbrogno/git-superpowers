#!/usr/bin/env bash
# Run all trigger tests (costs money). Usage: tests/triggers/run-all.sh [skill ...]
# Positive: prompts/<skill>/*.txt must trigger <skill>. Negative: negative/*.txt must trigger no git-superpowers skill.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
run() { if "$DIR/run.sh" "$@"; then pass=$((pass+1)); else fail=$((fail+1)); fi; }

if [[ $# -gt 0 ]]; then skills=("$@"); else skills=(); for d in "$DIR"/prompts/*/; do skills+=("$(basename "$d")"); done; fi
for s in "${skills[@]}"; do
  for p in "$DIR/prompts/$s"/*.txt; do [[ -f "$p" ]] && run "$s" "$p"; done
done
if [[ $# -eq 0 ]]; then
  for p in "$DIR"/negative/*.txt; do [[ -f "$p" ]] && run --none "$p"; done
fi
echo "---- passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
