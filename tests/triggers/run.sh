#!/usr/bin/env bash
# Skill-trigger test: does the prompt make Claude invoke the expected skill?
#
# Usage: tests/triggers/run.sh <skill> <prompt-file>        expect Skill call for <skill>
#        tests/triggers/run.sh --none <prompt-file>         expect NO git-superpowers Skill call
# Env:   TRIGGER_MODEL (optional, passed as --model), TRIGGER_MAX_TURNS (default 3), TRIGGER_MAX_BUDGET (USD, default 0.50)
# Costs money (real claude -p run). Only the Skill tool is available, so nothing else executes.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="${1:-}"; PROMPT_FILE="${2:-}"
if [[ -z "$SKILL" || ! -f "$PROMPT_FILE" ]]; then
  echo "usage: $0 <skill>|--none <prompt-file>" >&2; exit 2
fi
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
command -v claude >/dev/null || { echo "SKIP: claude CLI not on PATH" >&2; exit 3; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
git -C "$WORK" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init

model_args=(); [[ -n "${TRIGGER_MODEL:-}" ]] && model_args=(--model "$TRIGGER_MODEL")
OUT="$WORK/stream.jsonl"
( cd "$WORK" && claude -p "$(cat "$PROMPT_FILE")" \
    --plugin-dir "$REPO" \
    --tools Skill --allowedTools Skill --permission-mode dontAsk \
    --strict-mcp-config --setting-sources project \
    --max-budget-usd "${TRIGGER_MAX_BUDGET:-0.50}" \
    --output-format stream-json --verbose \
    --max-turns "${TRIGGER_MAX_TURNS:-3}" "${model_args[@]}" ) >"$OUT" 2>"$WORK/stderr.txt" </dev/null

# All Skill tool_use names in the stream
called="$(python3 - "$OUT" <<'PY'
import json, sys
for line in open(sys.argv[1], errors="replace"):
    try: ev = json.loads(line)
    except ValueError: continue
    if ev.get("type") != "assistant": continue
    for b in ev.get("message", {}).get("content", []) or []:
        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
            print((b.get("input") or {}).get("skill", ""))
PY
)"

label="$(basename "$(dirname "$PROMPT_FILE")")/$(basename "$PROMPT_FILE")"
if [[ ! -s "$OUT" ]]; then
  echo "ERROR $label: no output from claude: $(head -c 300 "$WORK/stderr.txt")"; exit 3
fi

if [[ "$SKILL" == "--none" ]]; then
  if grep -qE '^(git-superpowers:)' <<<"$called"; then
    echo "FAIL $label: unexpected skill(s): $(tr '\n' ' ' <<<"$called")"; exit 1
  fi
  echo "PASS $label: no git-superpowers skill triggered"; exit 0
fi

if grep -qE "^(git-superpowers:)?${SKILL}\$" <<<"$called"; then
  echo "PASS $label: $SKILL triggered"; exit 0
fi
echo "FAIL $label: expected $SKILL, got: ${called:-<no skill call>}" | tr '\n' ' '; echo
exit 1
