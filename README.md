<h1 align="center">git-superpowers</h1>

<p align="center">
  <img width="1376" height="768" alt="git-superpowers" src="https://github.com/user-attachments/assets/a92ccde2-920d-4b1a-8c99-742388568b8c" />
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge" alt="License: MIT" />
  </a>
  <img src="https://img.shields.io/badge/Skills-24-orange?style=for-the-badge" alt="24 Skills" />
  <img src="https://img.shields.io/badge/Agents-4-blue?style=for-the-badge" alt="4 Agents" />
  <img src="https://img.shields.io/badge/Guard_Hook-enforced-red?style=for-the-badge" alt="Guard Hook" />
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Code Plugin" />
  <img src="https://img.shields.io/badge/Dependencies-0-brightgreen?style=for-the-badge" alt="Zero Dependencies" />
  <a href="https://github.com/fbrogno/git-superpowers/actions/workflows/validate.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/fbrogno/git-superpowers/validate.yml?style=for-the-badge&label=validate" alt="CI" />
  </a>
</p>

<p align="center">
  AI-powered Git & GitHub workflows for Claude Code.<br>
  Topic-based commits, smart rebasing, the full PR lifecycle (create → review → CI-fix → release),<br>
  conflict prediction — with safety rules that are <em>enforced by a hook</em>, not just written down.
</p>

---

## Quick Start

```
/plugin marketplace add fbrogno/git-superpowers && /plugin install git-superpowers@git-superpowers
```

Then just talk to Claude:

```
"commit nur den bugfix, nicht das feature"     → smart-commit
"sync my branch"                               → smart-sync
"pushen"                                       → safe-push
"PR aufmachen"                                 → pr-prep
"review bobby's PR"                            → pr-review
"warum ist die CI rot?"                        → ci-fix
"neue version releasen"                        → release
"wird das deployment krachen?"                 → deploy-check
"wo steh ich überall"                          → repo-overview
"alles auf einmal — commit, push, PR"          → daily-workflow
```

---

## The Problem

| Problem | What happens | git-superpowers fix |
|---------|-------------|---------------------|
| Mixed changes | Multiple features in one branch, same files | Topic detection + hunk-level splitting |
| Merge conflict chaos | Conflicts in files with changes from different topics | Topic-aware conflict resolution |
| Unfinished code pushed | Debug statements, forgotten TODOs, missing files | Pre-push audit with auto-fix |
| No overview | Hard to see where all repos stand | Multi-repo dashboard |
| Avoidable mistakes | Secrets in diff, conflict markers, force push | Guard hook blocks them deterministically |
| PR friction | Unpushed branches, ignored templates, duplicate PRs, red CI | Full PR lifecycle: prep → review → ci-fix → release |
| Team damage | Force-push on shared/protected branches rewrites teammates' history | Protected-branch refusal + shared-branch detection |
| First deploy crashes the VM | New repo hardcodes a port another project already uses | Org-wide port inventory + first-deploy confirmation gate |
| Hard to trace | Who changed what, when, and why | Narrative git history |

---

## Skills

### Core Workflows

| Skill | What it does |
|---|---|
| `smart-commit` | Groups changes by topic. Splits mixed files at hunk level — one commit per topic. Offers separate, combined, or quick mode. |
| `smart-sync` | Rebases onto main with topic-aware conflict resolution. Detects merge commits, guides through conflicts, suggests abort when overwhelmed. |
| `safe-push` | Scans outgoing commits for debug statements, secrets, conflict markers, incomplete features. Predicts conflicts with main. Fixes issues directly. |
| `daily-workflow` | Chains skills into a pipeline: commit → review → sync → push → PR. Detects branch state and suggests the right flow. Quick mode for experienced users. |

### Overview & Analysis

| Skill | What it does |
|---|---|
| `repo-overview` | Dashboard across all repos: branch, behind/ahead, uncommitted changes. Discovers repos via config/locate/pruned find, plus uncloned org repos via `gh`. |
| `branch-inspect` | Shows what other branches are doing. Who committed what, file overlaps, predicted conflicts. Cross-branch overlap matrix. |
| `cross-compare` | Compares a file or module across branches side-by-side. Collision forecast for each pair. |
| `conflict-simulator` | Predicts conflicts without touching your branch (read-only). Uses `git merge-tree` for accurate simulation. Severity ratings per file. |

### Code Quality

| Skill | What it does |
|---|---|
| `diff-review` | Senior-dev code review: bugs, security, async mistakes, missing error handling. Not a linter — semantic understanding. Fixes issues directly. |
| `commit-split` | Splits an oversized commit into focused topic commits. Auto-detects topics, handles hunk-level splitting for mixed files. |

### Branch Operations

| Skill | What it does |
|---|---|
| `cherry-pick` | Picks specific commits from other branches. Shows preview, checks for duplicates, handles conflicts. |
| `selective-merge` | Takes specific files (not commits) from another branch. Replace completely or merge specific parts. |
| `hotfix` | Emergency workflow for production: fix in a separate worktree (your work stays untouched; stash only as fallback) → audit → PR → back. |
| `worktree` | Work on a second branch in parallel without stashing — create, list and safely remove worktrees. |
| `stash` | Inspect stashes, apply by message, recover dropped stashes — never drops without showing the contents first. |

### Pull Requests, CI & Releases

| Skill | What it does |
|---|---|
| `pr-prep` | Audits branch, conflict dry-run, pushes, respects the repo's PR template, creates or updates the PR via `gh` (draft, reviewers, base override, stacked PRs). |
| `pr-review` | The other side: reviews a teammate's PR — diff analysis, drafted verdict + inline comments, submitted only after your approval. |
| `pr-feedback` | Your own PR got review comments — verify each, clarify unclear ones first, fix one by one, reply in the thread, resolve only what was fixed. |
| `ci-fix` | Red checks → fetches only the failed step logs, isolates the first real error, reproduces locally, fixes the cause (never the symptom), watches it go green. |
| `release` | Semver bump derived from commits, version-file sync, annotated tag, `gh release create` with curated notes. |

### Deploy Safety

| Skill | What it does |
|---|---|
| `deploy-check` | Finds deploy-config foot-guns before the VM does — port inventory across **all repos of the org** (via gh, no cloning) and all branches, fixed `container_name`, missing healthchecks, `:latest` tags. First deploys with hardcoded ports are **gated behind explicit confirmation**, not warned about. Recommends the infra-grade fix (dynamic ports, proxy, `COMPOSE_PROJECT_NAME`, port registry). |

### History & Recovery

| Skill | What it does |
|---|---|
| `git-history` | File/function/line history as a readable narrative. Who changed what, when, why — not raw git output. |
| `bisect` | Finds the commit that broke something with `git bisect run` in a temporary worktree — your tree is never touched. |
| `git-undo` | Safe recovery: undo commits, revert pushes, restore files, escape bad rebases. Always shows the safest option first — and never force-pushes shared branches. |

### Agents (spawned by skills for complex tasks)

| Agent | Used by | Task |
|---|---|---|
| `topic-analyzer` | smart-commit, commit-split | Groups changes by topic via diff analysis |
| `conflict-resolver` | smart-sync | Analyzes conflicts, produces resolution plan with severity ratings |
| `code-reviewer` | diff-review | Semantic code review, returns structured JSON findings |
| `repo-scanner` | repo-overview | Parallel multi-repo status scan in minimal bash calls |

---

## Installation

### Claude Code

```
/plugin marketplace add fbrogno/git-superpowers && /plugin install git-superpowers@git-superpowers
```

### CLI

```bash
claude plugin marketplace add fbrogno/git-superpowers && claude plugin install git-superpowers@git-superpowers
```

### Update

```
/plugin marketplace update git-superpowers && /plugin update git-superpowers@git-superpowers
```

---

## Design Principles

### Token Efficiency

- `--stat` and `--name-only` first — full diffs only when semantic analysis is needed
- Skill descriptions say only *when* to use a skill; shared boilerplate lives once in `references/common-snippets.md`
- Agents spawn only for complex tasks (>10 files, >500 line diffs, >5 repos)
- Example outputs described, not shown — Claude knows how to format

### Adaptive Output

Skills adjust to your experience level:
- **Beginners**: Explanations, recommended defaults, guided flow
- **Experienced**: Terse output, skip menus, quick mode
- **Default**: Brief explanations, `[Enter]` for safe choice

### Safety — enforced, not just written down

A PreToolUse hook (`hooks/git-guard.sh`) deterministically blocks the dangerous patterns, so safety doesn't depend on the model remembering rules:

- `git add .` / `-A` → blocked (stage specific files)
- bare `git push --force` → blocked (use `--force-with-lease --force-if-includes`)
- `--no-verify` → blocked (fix the hook failure instead)
- any force-push to `main`/`master`/`develop`/`staging`/`production`/`release/*` → blocked
- force in every spelling: `+refspec`, `-uf`, `git -C dir push -f`, subshells, `bash -c`, quoted branch names, a bare `--force-with-lease` while on a protected branch
- `git commit -n`, deleting or mirroring protected branches, `git add :/` / `*`

The guard parses commands like a shell (quotes, heredocs, `;`/`&&`/`|`, `$( )`, abbreviated options, wrappers like `nice`/`timeout`) and needs `python3`; without it, it fails open with a warning. It exists to stop *accidental* dangerous commands — it is not a security boundary against deliberate evasion (shell variables, aliases defined elsewhere, scripts).

The prose rules cover what a regex can't judge:

- Protected & shared branches: history rewrites refused, `git revert` offered instead
- Shared-branch detection (multi-author check) before any force push
- Repo conventions respected: merge-vs-rebase and commit style detected, not imposed
- Always show what will happen before it happens; confirm before destructive operations
- Secret scanning before every push (non-negotiable)
- Worktree, detached HEAD, shallow clone detection

Deliberate exception (run it yourself, not via Claude): `GIT_SUPERPOWERS_UNSAFE=1 <command>`

---

## Optional Configuration

Works without any config in any git repo.

Optional `.claude-git.yml` in repo root for custom topic mappings:

```yaml
scan_dirs:
  - ~/source/
  - ~/projects/

topics:
  payments:
    paths: ["src/payments/", "lib/stripe/"]
  auth:
    paths: ["src/auth/", "middleware/auth"]

# deploy-check (optional)
deploy_host: my-vm        # SSH alias only — never credentials; enables the
                          # confirmed read-only port check (ss, docker ps)
port_registry: ~/infra/ports.yml   # authoritative port claims per repo
```

---

## Architecture

```
git-superpowers/
├── skills/              # 24 Skills (SKILL.md each)
├── agents/              # 4 Subagents (read-only tools, spawned by skills)
├── hooks/               # git-guard.sh (PreToolUse) + its test suite
├── references/          # 6 Shared references
│   ├── common-snippets.md   # BASE detection, preflight, commit template, verification
│   ├── git-safety.md        # Safety rules, protected branches, adaptive output
│   ├── topic-detection.md   # Progressive topic grouping
│   ├── hunk-analysis.md     # Hunk-level selective staging
│   ├── conflict-resolution.md  # Topic-aware conflict strategy
│   └── branch-history.md    # Efficient git history commands
├── scripts/             # validate.py (skill-authoring rules), lint-shell.sh, bump-version.sh
├── tests/triggers/      # opt-in trigger tests: does "pushen" really fire safe-push?
└── .github/workflows/   # CI: validation + hook regression tests
```

**Zero dependencies.** The skills run entirely through Claude's native capabilities — reading diffs, understanding code, executing git commands. The only executable code is the safety guard hook and the CI tooling (bash + Python 3 stdlib, nothing to install).

---

## Author

[@fbrogno](https://github.com/fbrogno)

## License

MIT
