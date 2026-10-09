#!/usr/bin/env bash
# Bump / check the plugin version across all files listed in .version-bump.json.
#
# Usage:
#   bash scripts/bump-version.sh <x.y.z>   set the version in all files (reads all first)
#   bash scripts/bump-version.sh --check   report drift between files (exit 1 on drift)
#   bash scripts/bump-version.sh --audit   grep repo for the current version string outside CHANGELOG
# Remember to add a "## [x.y.z]" entry to CHANGELOG.md yourself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/.version-bump.json"
[[ -f "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

MODE="${1:-}"
[[ -n "$MODE" ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

BUMP_ROOT="$ROOT" BUMP_CONFIG="$CONFIG" python3 - "$MODE" <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

root = Path(os.environ["BUMP_ROOT"])
cfg = json.loads(Path(os.environ["BUMP_CONFIG"]).read_text())
mode = sys.argv[1]


def get(doc, field):
    cur = doc
    for part in field.split("."):
        cur = cur[int(part)] if isinstance(cur, list) else cur[part]
    return cur


def put(doc, field, value):
    parts = field.split(".")
    cur = doc
    for part in parts[:-1]:
        cur = cur[int(part)] if isinstance(cur, list) else cur[part]
    last = parts[-1]
    if isinstance(cur, list):
        cur[int(last)] = value
    else:
        cur[last] = value


# Preflight: read everything first, fail before writing anything
entries = []
for e in cfg["files"]:
    path = root / e["path"]
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        cur = get(doc, e["field"])
    except Exception as ex:
        sys.exit(f"preflight failed for {e['path']} ({e['field']}): {ex}")
    entries.append((e, path, doc, cur))

versions = {cur for *_, cur in entries}

if mode == "--check":
    for e, _, _, cur in entries:
        print(f"  {e['path']} [{e['field']}] = {cur}")
    if len(versions) > 1:
        print("DRIFT: files disagree on version")
        sys.exit(1)
    print(f"OK: all files at {next(iter(versions))}")

elif mode == "--audit":
    if len(versions) > 1:
        sys.exit(f"drift present ({sorted(versions)}); run --check first")
    ver = next(iter(versions))
    excl = set(cfg.get("audit", {}).get("exclude", []))
    pat = re.compile(r"(?<![\d.])" + re.escape(ver) + r"(?![\d])")
    hits = 0
    for f in sorted(root.rglob("*")):
        rel = f.relative_to(root)
        if not f.is_file() or rel.parts[0] in excl or str(rel) in excl or ".git" in rel.parts:
            continue
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        for n, line in enumerate(lines, 1):
            if pat.search(line):
                hits += 1
                print(f"  {rel}:{n}: {line.strip()[:120]}")
    print(f"audit: {hits} occurrence(s) of {ver} outside CHANGELOG (declared bump targets are expected)")

else:
    new = mode
    if not re.fullmatch(r"\d+\.\d+\.\d+", new):
        sys.exit(f"invalid version '{new}' (expected x.y.z, or --check / --audit)")
    for e, path, doc, old in entries:
        put(doc, e["field"], new)
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"  {e['path']}: {old} -> {new}")
    print("bumped. Next: add '## [%s]' to CHANGELOG.md, then run: bash scripts/bump-version.sh --audit" % new)
PY
