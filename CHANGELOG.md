# Changelog

All notable changes to git-superpowers. Format follows [Keep a Changelog](https://keepachangelog.com/), versioning follows [SemVer](https://semver.org/).

## [4.0.0] — 2026-10-09

Major because the guard now blocks considerably more (every force-push spelling, `commit -n`, deleting protected branches) and skill triggers were re-routed.

### Security
- **git-guard rewritten** with a shell-aware tokenizer (python3): closes force-push bypasses via `+refspec`, `git -C`/`-c`, combined flags (`-uf`), subshells/`bash -c`/`$( )`, quoted branch names, and a bare `--force-with-lease` while on a protected branch. Also blocks `git commit -n`, `push --mirror`, deleting protected branches, `git add :/` and `*`. Also covers abbreviated options (`--force-w`), `@`/`HEAD` refspecs, glued redirections, `bash -lc` and heredocs fed to a shell, `$'…'`/brace expansion, wrappers (`nice`, `timeout`, `xargs`, …), `-c core.hooksPath=` and force aliases, `--all`/`--prune`/wildcard pushes. Protected-branch detection looks at the refspec, not the remote name (no more false positives for a remote called `production`). Tests: 22 → 163, incl. macOS bash 3.2.

### Fixed
- `git-undo`: "discard all" also resets staged changes and offers a stash backup first; hard resets check for a dirty tree.
- `conflict-simulator`: fallback runs in a temporary worktree — truly read-only.
- `release`: detects `BREAKING CHANGE` footers, ignores lockfiles, release-PR path for protected base branches.
- `deploy-check` / `repo-overview`: no 50-repo cap; compose files found in subfolders.
- `smart-sync`: `--force-with-lease --force-if-includes`, no `--force` advice. All stashes use `-u`. No hard-coded co-author trailer.
- Owner moved to `fbrogno`.

### Added
- Skills **`pr-feedback`**, **`bisect`**, **`stash`**, **`worktree`** (24 total).
- `references/common-snippets.md` — shared BASE detection, preflight, commit template, verification rule.
- Tooling: `scripts/lint-shell.sh` (shellcheck), `scripts/bump-version.sh` (+ `--check` drift), `tests/triggers/` (opt-in `claude -p` trigger tests, de/en + negatives); `validate.py` enforces skill-authoring rules, word budgets, version and skill-count sync.

### Changed
- All descriptions follow the "Use when …" rule (when to use, never the workflow) with de/en phrasings and "Not for …" clauses; overlapping triggers untangled.
- Iron Law + Red Flags tables in the destructive skills; fresh-evidence rule before claiming "pushed" or "CI green".
- Skills shrink from ~20k to ~10k words; `hotfix` prefers a worktree; `smart-sync` resolves in-progress merge conflicts; `git-undo` covers amend/squash; `pr-prep` can merge on request.
- Agents: model set on all four, explicit read-only and no-subagent rules; `code-reviewer` diffs from the merge-base and returns a merge verdict.

## [3.2.0] — 2026-07-13

### Changed
- **deploy-check: collisions are cross-REPO, not just cross-branch.** The real incident: a *new repo* hardcodes a host port that another project on the shared VM already uses — its first deploy crashes. The port inventory now covers (a) all locally cloned repos, (b) all org repos via the gh contents API (no cloning), (c) branches of the current repo, and (d) an optional authoritative `port_registry` file (`.claude-git.yml`).
- **First-deploy gate**: a brand-new repo/deploy config with a hardcoded host port is no longer a warning — safe-push and deploy-check refuse to push/deploy until the port is explicitly verified ("checked free on the target") or the config is fixed so collisions can't happen. Fix-first is offered before verify-first.
- Optional `deploy_host` config (SSH **alias** only, never credentials): deploy-check may run exactly two read-only commands (`ss -tlnp`, `docker ps`) on the target after per-run user confirmation — the only check git cannot answer itself.

## [3.1.0] — 2026-07-13

### Added
- **`deploy-check` skill** — deploy-config safety via git, no Docker access needed: static foot-gun audit (hardcoded host ports, fixed `container_name`, missing healthcheck/restart policy, `:latest` tags, host-path volumes, committed `.env` values), **cross-branch collision matrix** (`git show branch:compose.yml` across all branches — catches two branches claiming the same host port or container name *before* the shared-VM bind error), first-deploy/new-repo audit, and infra-grade fix recommendations (auto-assigned ports + proxy routing, `${HOST_PORT:-…}` parameterization, `COMPOSE_PROJECT_NAME` scoping, healthcheck + `--wait` for zero-downtime).
- **safe-push Check 6** — when the outgoing diff touches deploy files, the audit scans added lines for the same foot-guns and hands off to `/deploy-check` for the cross-branch view; pr-prep's audit includes it too.

## [3.0.0] — 2026-07-13

Major because the new guard hook **changes runtime behavior**: commands that previously ran (with only prose rules against them) are now deterministically blocked.

### Added
- **`hooks/git-guard.sh`** — PreToolUse hook that enforces the safety rules as a system, not prose: blocks `git add .`/`-A`, `--no-verify`, bare `git push --force`, and any force-push to protected branches (`main`, `master`, `develop`, `staging`, `production`, `release/*`). Heredoc bodies and quoted strings are exempt, malformed input fails open. Escape hatch: `GIT_SUPERPOWERS_UNSAFE=1` (user-run only). Regression-tested by `hooks/test-git-guard.sh` (22 cases).
- **`pr-review` skill** — the reviewer side of PRs: fetch the diff via `gh`, senior-dev analysis, drafted verdict + inline comments, submit only after user approval.
- **`ci-fix` skill** — failing checks → `gh run view --log-failed`, first-error isolation, local reproduction from the workflow definition, honest fixes (flaky vs. broken distinguished explicitly).
- **`release` skill** — semver bump derived from commit history, version-file sync, annotated tag, `gh release create` with curated notes.
- **git-safety.md**: Protected Branches (name list + GitHub branch-protection check), Shared Branch Detection (multi-author check before any history rewrite), Workflow Conventions (merge-vs-rebase and commit-style detection instead of imposing preferences), `--force-with-lease --force-if-includes` as the force-push standard, hook-bypass ban.
- **CI for the plugin itself** — `scripts/validate.py` (frontmatter, reference links, manifest sync, claimed skill count, review-category sync, hook syntax) + guard tests, wired into `.github/workflows/validate.yml`.
- This changelog.

### Fixed
- **pr-prep**: pushed the branch nowhere before `gh pr create` (create failed on unpushed branches); base hardcoded to `main`; no `gh auth` check; no existing-PR detection (duplicate creates, review-destroying rebase advice); `.github/PULL_REQUEST_TEMPLATE.md` ignored; no draft/reviewer options; no post-create check status.
- **safe-push**: large-file check used `grep -E '\d{4,}'` (`\d` unsupported in POSIX grep — check never fired) and missed binaries entirely; now checks real blob sizes in outgoing commits.
- **git-undo** scenario 4 (wrong branch): `git reset --hard origin/<wrong-branch>` was a no-op exactly when the mistake was already pushed; now branches on pushed/unpushed and refuses force-push on protected/shared branches (revert path instead).
- **cross-compare**: conflict prediction compared hunk line numbers of two diverged branches (numbers refer to different file states — meaningless); now uses read-only `git merge-tree` between the branches.
- **commit-split**: no clean-worktree guard before `git reset --soft` (pre-existing changes leaked into split commits); "already pushed" false positive when the branch had no upstream at all.
- **repo-overview**: `mdfind` source could never find `.git` (Spotlight doesn't index hidden dirs) — replaced with pruned `find`; `gh repo list` claimed to list org repos but doesn't without an org argument — now iterates `gh api user/orgs`; per-repo default-branch detection instead of hardcoded `origin/main`.
- **cherry-pick**: duplicate check compared against `main` instead of the source branch — now uses `git cherry` (patch-equivalence); `<original-tip>` placeholder was never captured — now recorded before picking; picks use `-x` for traceability.
- **git-history**: `git log --oneline -L` still printed full diffs (`-L` forces patches) — token-saving variant needs `-s`.
- **conflict-simulator**: simulation announced as "rebase" but `merge-tree` simulates a single-step merge — caveat now stated in the report; duplicate abort/cleanup block removed upstream, "parallel" loop wording corrected.
- **selective-merge**: replace-mode used auto-staging `git checkout origin/<branch> -- <file>` contradicting the skill's own "not committed yet" flow — now `git restore --source --worktree`.
- **conflict-resolution.md**: post-rebase marker check greppped the whole worktree (node_modules) — now `git grep` over tracked files.
- **git-safety.md**: pre-commit-hook rule described amending a commit that doesn't exist on hook failure — corrected semantics.
- Hardcoded `origin/main` replaced by default-branch detection in daily-workflow, hotfix (production-branch aware), branch-inspect, cross-compare, cherry-pick.

### Changed
- All four agents: explicit read-only `tools` allowlist (`Bash, Read, Grep, Glob`); `repo-scanner` pinned to `model: haiku` (mechanical work); repo-scanner reports behind/ahead on the default branch too (unpulled/unpushed) instead of `-`.
- diff-review ↔ code-reviewer duplicated category list marked with a sync comment, enforced by the validator.
- Metadata: single source of truth enforced by CI; functionless `package.json` removed.

## [2.1.0] — 2026-05-04

- Token efficiency: inline safety blocks (no mandatory reference reads), tightened trigger descriptions, adaptive verbosity rules.
- New `daily-workflow` skill — chained pipeline (sync → commit → review → push → PR).
- Agents get YAML frontmatter; agent spawning via registered subagent types with size thresholds.
- `docs/specs/` removed — design lives in skills and references.

## [2.0.0] — 2026-04-11

- 4 subagents (topic-analyzer, conflict-resolver, code-reviewer, repo-scanner).
- 15 bugfixes across skills; `git merge-tree --write-tree` based conflict simulation with git < 2.38 fallback.

## [1.x] — 2026-04-10

- Initial 15 skills, 5 shared references, marketplace packaging.
