---
name: daily-workflow
description: Use when the user wants the whole ship-it chain in one go — "alles auf einmal", "commit und push und PR", "full workflow", "Tagesablauf", "daily workflow", "was muss ich machen" at the start or end of the day. Not for a single operation: a lone "commit" goes to smart-commit, a lone "push" to safe-push.
---

# Daily Workflow

Orchestrator: look at the repo state, propose the right chain of skills, run them in order. It never replaces the skills; each step follows its own skill's full workflow and safety rules.

## Safety
- Each step keeps its own skill's safety rules, including in quick mode
- Destructive steps still need confirmation; the user can exit at any point
- A failing step pauses the pipeline, nothing is skipped silently

## Workflow

### 1. Assess
One Bash call (`$BASE` per `references/common-snippets.md#base-branch`):
```bash
BRANCH=$(git branch --show-current); git fetch origin --quiet
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@'); [ -z "$BASE" ] && BASE=main
echo "branch:$BRANCH behind:$(git rev-list --count HEAD..origin/$BASE 2>/dev/null || echo ?) ahead:$(git rev-list --count origin/$BASE..HEAD 2>/dev/null || echo ?) uncommitted:$(git status --porcelain | wc -l | tr -d ' ') unpushed:$(git log --oneline origin/$BRANCH..HEAD 2>/dev/null | wc -l | tr -d ' ')"
```
Show a short status block.

### 2. Suggest a chain from the state

| State | Suggested chains |
|---|---|
| Behind + uncommitted | commit first (safer): `/smart-commit` → `/smart-sync` → `/safe-push`; or full: + `/diff-review` before sync and `/pr-prep` after push; or quick |
| Behind, clean | `/smart-sync`; then `/safe-push`; then `/pr-prep` |
| Uncommitted, not behind | `/smart-commit` → optionally `/diff-review` → `/safe-push` → optionally `/pr-prep`; or quick |
| Unpushed only | `/safe-push`, optionally `/diff-review` before and `/pr-prep` after |
| Clean and current | `/pr-review` for waiting PRs, `/ci-fix` for red checks, `/repo-overview`, `/branch-inspect`, or nothing |

Let the user pick a number or describe it.

### 3. Run the chain
Between skills show progress (`✓ commit → ▶ review → ○ sync → ○ push`) and ask "continue / skip / stop". If a skill hits trouble (conflicts, audit findings), resolve it inside that skill first; if the user aborts a step, ask whether to skip it or stop.

### 4. Quick mode ("schnell", "quick", "just do it")
Commit as one combined commit with auto-message, sync if behind (conflicts: leave quick mode), push via safe-push (secrets or conflict markers: leave quick mode; debug lines and TODOs auto-fixed). Only optional questions are skipped.

### 5. Summary
List what was committed, synced, pushed, skipped, and the final branch state from fresh `git status -sb` output.

## Rules
- Safety checks are never skipped, even in quick mode
- Always show pipeline progress and allow exit
- Orchestrator only: use the single skill directly when the user asks for one operation
