#!/bin/bash
# Regression tests for git-guard.sh — run locally or in CI: bash hooks/test-git-guard.sh
set -u
GUARD="$(cd "$(dirname "$0")" && pwd)/git-guard.sh"
PASS=0; FAIL=0

check() { # check <expected-exit> <command-json-string> <label>
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$2" | bash "$GUARD" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$1" ]; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL ($3): expected exit $1, got $got — $2"; fi
}

# Must BLOCK (exit 2)
check 2 '"git add ."'                                            "add-dot"
check 2 '"git add -A"'                                           "add-A"
check 2 '"git add --all"'                                        "add-all"
check 2 '"git commit --no-verify -m x"'                          "no-verify"
check 2 '"git push --force origin fb"'                           "bare-force"
check 2 '"git push -f"'                                          "short-force"
check 2 '"git push --force-with-lease origin main"'              "lease-to-main"
check 2 '"git push -f origin master"'                            "force-to-master"
check 2 '"git push --force origin HEAD:release/1.2"'             "refspec-release"
check 2 '"git status && git push --force origin fb"'             "chained-force"

# Must ALLOW (exit 0)
check 0 '"git add ./src/file.ts"'                                "add-explicit-dotslash"
check 0 '"git add src/a.ts src/b.ts"'                            "add-files"
check 0 '"git push --force-with-lease origin fb"'                "lease-feature"
check 0 '"git push --force-with-lease --force-if-includes origin fb"' "lease-includes"
check 0 '"git push origin main"'                                 "plain-push-main"
check 0 '"git checkout main; git pull"'                          "checkout-main"
check 0 '"git commit -m \"fix --no-verify docs\""'               "no-verify-in-message"
check 0 '"legit push --force"'                                   "legit-not-git"
check 0 '"npm run build"'                                        "non-git"
check 0 '"git log --oneline"'                                    "read-only"

# Heredoc body quoting banned commands must not trigger
printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\ndocs: explain why git add . is banned\n\nAlso covers git push --force origin main.\nEOF\n)\""}}' \
  | bash "$GUARD" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL (heredoc-quoted)"; fi

# --- v4 hardening: bypasses that must BLOCK ---
check 2 '"git push origin +main"'                                "plus-main"
check 2 '"git push origin +HEAD:main"'                           "plus-head-main"
check 2 '"git push origin +feature"'                             "plus-feature"
check 2 '"git -C /x push -f"'                                    "global-C"
check 2 '"git -c k=v push --force"'                              "global-c"
check 2 '"git --no-pager push -f"'                               "global-no-pager"
check 2 '"git --git-dir=/x/.git push -f"'                        "global-git-dir"
check 2 '"git push -uf origin main"'                             "combined-uf"
check 2 '"git push -fu"'                                         "combined-fu"
check 2 '"(git push -f)"'                                        "subshell"
check 2 '"echo $(git push -f)"'                                  "cmd-subst"
check 2 '"echo `git push -f`"'                                   "backticks"
check 2 '"{ git push -f; }"'                                     "brace-group"
check 2 '"git push --force-with-lease \"origin\" \"main\""'      "quoted-lease-main"
check 2 '"git push -f '"'origin' 'master'"'"'                     "quoted-force-master"
check 2 '"git commit -n -m x"'                                   "commit-n"
check 2 '"git commit -nm x"'                                     "commit-nm"
check 2 '"git commit -an"'                                       "commit-an"
check 2 '"git push --no-verify"'                                 "push-no-verify"
check 2 '"git push --mirror"'                                    "mirror"
check 2 '"git push origin --delete main"'                        "delete-main"
check 2 '"git push origin :main"'                                "colon-main"
check 2 '"git add :/"'                                           "add-root-pathspec"
check 2 '"git add *"'                                            "add-star"
check 2 '"git -C /x add -A"'                                     "global-add-A"
check 2 '"env FOO=1 git push -f"'                                "env-prefix"
check 2 '"sudo git push --force"'                                "sudo-prefix"
check 2 '"bash -c \"git push -f\""'                              "bash-c"
check 2 '"echo \"$(git push -f)\""'                              "subst-in-dquote"
check 2 '"git commit -am x -n"'                                  "commit-trailing-n"

# --- must ALLOW ---
check 0 '"git push -u origin feature/x"'                         "push-u-feature"
check 0 '"git push --force-with-lease origin feature/x"'         "lease-feature-x"
check 0 '"git push origin feature/main-fix"'                     "branch-contains-main"
check 0 '"git push production feature/x"'                        "remote-production"
check 0 '"git push --force-with-lease main feature/x"'           "remote-named-main-feature"
check 0 '"git commit -m \"fix -n flag\""'                        "n-in-message"
check 0 '"git commit -m x"'                                      "commit-plain"
check 0 '"git log --oneline -n 5"'                               "log-n"
check 0 '"git stash -u"'                                         "stash-u"
check 0 '"git commit -m -n"'                                     "n-as-message-value"
check 0 '"git -C /x status"'                                     "global-C-status"
check 0 '"git push origin --delete feature/x"'                   "delete-feature"
check 0 '"echo \"git push -f\""'                                 "echo-quoted-allowed"

# --- cwd-aware: lease without refspec ---
T=$(mktemp -d); git -C "$T" init -q -b main 2>/dev/null || { git -C "$T" init -q; git -C "$T" checkout -q -b main; }
git -C "$T" -c user.email=a@b -c user.name=t commit -q --allow-empty -m i
checkc() { # checkc <expected> <command> <cwd> <label>
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$3" "$2" | bash "$GUARD" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL ($4): expected $1, got $got"; fi
}
checkc 2 'git push --force-with-lease' "$T" "lease-bare-on-main"
checkc 2 'git push --force-with-lease origin' "$T" "lease-remote-only-on-main"
checkc 0 'git push --force-with-lease origin feat' "$T" "lease-explicit-on-main-cwd"
git -C "$T" checkout -q -b feat
checkc 0 'git push --force-with-lease' "$T" "lease-bare-on-feature"
rm -rf "$T"

# Malformed input must fail open
printf 'not json' | bash "$GUARD" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL (malformed-input)"; fi

echo "git-guard tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
