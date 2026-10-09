#!/usr/bin/env bash
# Lint shell scripts: shellcheck (--severity=warning) + syntax check (bash -n / sh -n).
#
# Usage: bash scripts/lint-shell.sh [--all] [file ...]
#   (default)  only shell files changed vs HEAD (staged, unstaged, untracked)
#   --all      every shell file in the repo (CI mode)
#   file ...   exactly these files
# Shell files = *.sh or a bash/sh/dash/ksh shebang; .git and tests/**/fixtures are skipped.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

all=false
explicit=()
for arg in "$@"; do
  case "$arg" in
    --all) all=true ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) explicit+=("$arg") ;;
  esac
done

is_shell_file() {
  local f="$1" first=""
  [[ -f "$f" ]] || return 1
  case "$f" in
    .git/*|*/.git/*|tests/*/fixtures/*|tests/fixtures/*) return 1 ;;
    *.sh) return 0 ;;
  esac
  IFS= read -r first <"$f" 2>/dev/null || true
  [[ "$first" =~ ^#!.*[/[:space:]](bash|dash|ksh|sh)([[:space:]]|$) ]]
}

candidates=()
if [[ ${#explicit[@]} -gt 0 ]]; then
  candidates=("${explicit[@]}")
elif $all || ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  while IFS= read -r f; do candidates+=("$f"); done < <(find . -type f -not -path './.git/*' | sed 's|^\./||' | sort)
else
  while IFS= read -r f; do candidates+=("$f"); done < <(
    { git diff --name-only --diff-filter=ACMR HEAD; git ls-files --others --exclude-standard; } | sort -u
  )
fi

files=()
for f in ${candidates[@]+"${candidates[@]}"}; do
  is_shell_file "$f" && files+=("$f")
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "lint-shell: no shell files to check"
  exit 0
fi

fail=0
echo "lint-shell: ${#files[@]} file(s)"

for f in "${files[@]}"; do
  first=""; IFS= read -r first <"$f" || true
  sh_bin=bash; [[ "$first" =~ [/[:space:]](sh|dash)([[:space:]]|$) ]] && sh_bin=sh
  if ! out="$("$sh_bin" -n "$f" 2>&1)"; then
    echo "  x syntax: $f"; echo "$out" | sed 's/^/      /'; fail=1
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck --severity=warning "${files[@]}"; then
    echo "  ok shellcheck"
  else
    fail=1
  fi
else
  echo "  ! shellcheck not installed - skipped (brew install shellcheck / apt-get install shellcheck). CI runs it."
fi

if [[ $fail -ne 0 ]]; then echo "lint-shell: FAIL"; exit 1; fi
echo "lint-shell: OK"
