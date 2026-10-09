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

# === v4.1 hardening (independent review): every case below was a verified bypass ===
# 2. abbreviated long options
check 2 '"git push --force-w origin main"'                       "abbr-force-with-lease"
check 2 '"git push --delet origin main"'                         "abbr-delete"
check 2 '"git push --mirro origin"'                              "abbr-mirror"
check 2 '"git commit --no-verif -m x"'                           "abbr-no-verify"
check 2 '"git add --al"'                                         "abbr-add-all"
check 2 '"git push --force-with-lease --delet origin main"'      "abbr-delete-lease"
check 0 '"git push --for origin feat"'                           "abbr-ambiguous-git-rejects"
# 3. redirections glued to tokens
check 2 '"git push -f>/dev/null origin feat"'                    "redir-glued-f"
check 2 '"git push origin main --force>/dev/null"'               "redir-glued-force"
check 2 '"git add .>/dev/null"'                                  "redir-glued-add-dot"
check 2 '"git add -A>/dev/null"'                                 "redir-glued-add-A"
check 2 '"git commit --no-verify>/dev/null -m x"'                "redir-glued-no-verify"
check 2 '"git push -f 2>&1 origin feat"'                         "redir-2to1"
check 2 '"git push -f &>out.log origin feat"'                    "redir-amp-gt"
check 2 '"git push -f >>out.log origin feat"'                    "redir-append"
check 2 '"git push -f <in.txt origin feat"'                      "redir-input"
check 2 '"git add . 2>&1"'                                       "redir-add-dot"
check 0 '"git add src/a.ts 2>&1 >/dev/null"'                     "redir-ok-add"
check 0 '"git push origin feat >/dev/null 2>&1"'                 "redir-ok-push"
check 0 '"git status 2>/dev/null | head -3"'                     "redir-ok-status"
# 4. no prefilter: obfuscated 'git'
check 2 '"g\\it push -f origin main"'                            "obf-backslash"
check 2 '"gi\"\"t push -f origin main"'                          "obf-empty-quotes"
check 2 '"\"g\"it push -f origin main"'                          "obf-quote-join"
# 5. shell -c with option clusters
check 2 '"bash -lc \"git push -f origin main\""'                 "bash-lc"
check 2 '"sh -ec \"git push -f origin main\""'                   "sh-ec"
check 2 '"zsh -c \"git push -f origin main\""'                   "zsh-c"
check 2 '"bash -xc \"git push -f origin main\""'                 "bash-xc"
check 2 '"bash -o pipefail -c \"git push -f origin main\""'      "bash-o-c"
check 0 '"bash -lc \"git status\""'                              "bash-lc-ok"
check 0 '"bash scripts/lint-shell.sh"'                           "bash-script-ok"
# 6. heredoc fed to a shell
check 2 '"bash <<X\ngit push -f origin main\nX"'                 "heredoc-bash"
check 2 '"sh <<'"'"'X'"'"'\ngit push -f origin main\nX"'         "heredoc-sh-quoted"
check 2 '"bash -s <<X\ngit push -f origin main\nX"'              "heredoc-bash-s"
check 2 '"eval <<X\ngit push -f origin main\nX"'                 "heredoc-eval"
check 2 '"source /dev/stdin <<X\ngit push -f origin main\nX"'    "heredoc-source"
check 2 '"bash <<< \"git push -f origin main\""'                 "herestring-bash"
check 2 '"cat <<X\n$(git push -f origin main)\nX"'               "heredoc-unquoted-subst"
check 0 '"git commit -F - <<X\ngit push -f origin main\nX"'      "heredoc-commit-data"
check 0 '"cat <<X\ngit push -f origin main\nX"'                  "heredoc-cat-data"
check 0 '"cat <<'"'"'X'"'"'\n$(git push -f origin main)\nX"'     "heredoc-quoted-subst-data"
check 0 '"bash script.sh <<X\ngit push -f origin main\nX"'       "heredoc-script-stdin-data"
# 8. heredoc marker inside quotes is not a heredoc
check 2 '"echo \"<<Y\"\ngit push -f origin main"'               "fake-heredoc-in-quotes"
# 9. ANSI-C quoting and brace expansion
check 2 '"git push $'"'"'-f'"'"' origin feat"'                   "ansi-c-f"
check 2 '"git push $'"'"'\\x2df'"'"' origin feat"'               "ansi-c-hex"
check 2 '"git push origin {-f,feat}"'                            "brace-f"
check 2 '"git push {--force,x} origin feat"'                     "brace-force"
check 0 '"git commit -m \"{a,b}\""'                              "brace-quoted-ok"
check 0 '"git add src/{a,b}.ts"'                                 "brace-add-ok"
# 10. wrappers
check 2 '"nice git push -f origin main"'                         "wrap-nice"
check 2 '"nice -n 5 git push -f origin main"'                    "wrap-nice-n"
check 2 '"timeout 60 git push -f origin main"'                   "wrap-timeout"
check 2 '"timeout -k 5 60 git push -f origin main"'              "wrap-timeout-k"
check 2 '"caffeinate -i git push -f origin main"'                "wrap-caffeinate"
check 2 '"caffeinate -t 60 git push -f origin main"'             "wrap-caffeinate-t"
check 2 '"xargs git push -f origin main"'                        "wrap-xargs"
check 2 '"echo x | xargs -n 1 git push -f origin main"'          "wrap-xargs-n"
check 2 '"stdbuf -oL git push -f origin main"'                   "wrap-stdbuf"
check 2 '"ionice -c 3 git push -f origin main"'                  "wrap-ionice"
check 2 '"exec git push -f origin main"'                         "wrap-exec"
check 2 '"nohup git push -f origin main"'                        "wrap-nohup"
check 2 '"command git push -f origin main"'                      "wrap-command"
check 2 '"env -S \"git push -f origin main\""'                   "wrap-env-S"
check 0 '"timeout 60 git status"'                                "wrap-ok"
# 11. config injection
check 2 '"git -c core.hooksPath=/dev/null commit -m x"'          "cfg-hookspath"
check 2 '"git --config-env core.hooksPath=X commit -m x"'        "cfg-env-hookspath"
check 2 '"git --config-env=core.hooksPath=X commit -m x"'        "cfg-env-hookspath-eq"
check 2 '"git -c alias.p=\"push -f\" p origin main"'             "cfg-alias-push"
check 2 '"git -c alias.p=!sh p"'                                 "cfg-alias-bang"
check 0 '"git -c user.name=x commit -m y"'                       "cfg-ok"
# 12. force-if-includes is not a lease
check 2 '"git push -f --force-if-includes origin feat"'          "force-if-includes-not-lease"
check 0 '"git push --force-if-includes origin feat"'             "if-includes-alone-ok"
# 13. add path normalization
check 2 '"git add ./"'                                           "add-dotslash"
check 2 '"git add \"./\""'                                       "add-dotslash-quoted"
check 2 '"git add :/"'                                           "add-top"
check 2 '"git add \"**\""'                                       "add-doublestar"
check 2 '"git add .//"'                                          "add-dot-slashes"
check 2 '"git add ./*"'                                          "add-dotslash-star"
check 2 '"git add \":(top)\""'                                     "add-top-magic"
check 0 '"git add ./src ./docs/a.md"'                            "add-subdirs-ok"
check 0 '"git add -p file.ts"'                                   "add-patch-ok"
# 7. lease with wildcards / --all / --prune / matching refspec
check 2 '"git push --force-with-lease --all origin"'             "lease-all"
check 2 '"git push --force-with-lease --branches origin"'        "lease-branches"
check 2 '"git push --force-with-lease origin \"refs/heads/*:refs/heads/*\""' "lease-wildcard"
check 2 '"git push --prune origin \"refs/heads/*:refs/heads/*\""' "prune-wildcard"
check 2 '"git push --prune"'                                     "prune-bare"
check 2 '"git push --prune --all origin"'                        "prune-all"
check 2 '"git push --force-with-lease origin :"'                 "lease-matching-colon"
check 0 '"git push --prune origin feat"'                         "prune-explicit-ok"
check 0 '"git push --all origin"'                                "plain-all-ok"

# cwd-aware: @ and other symbolic refspecs resolve to the current branch
T2=$(mktemp -d); git -C "$T2" init -q -b main 2>/dev/null || { git -C "$T2" init -q; git -C "$T2" checkout -q -b main; }
git -C "$T2" -c user.email=a@b -c user.name=t commit -q --allow-empty -m i
checkc 2 'git push --force-with-lease origin @' "$T2" "lease-at-on-main"
checkc 2 'git push --force-with-lease origin HEAD' "$T2" "lease-head-on-main"
checkc 2 'git push --force-with-lease origin HEAD~0' "$T2" "lease-head-tilde-on-main"
checkc 2 'git push --force-with-lease origin main^0' "$T2" "lease-main-caret"
git -C "$T2" checkout -q -b feat
checkc 0 'git push --force-with-lease origin @' "$T2" "lease-at-on-feature"
rm -rf "$T2"

# Malformed input must fail open
printf 'not json' | bash "$GUARD" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL (malformed-input)"; fi

echo "git-guard tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
