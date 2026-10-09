# Git Safety Rules

Shared safety rules that apply to all git-superpowers skills.

The most dangerous patterns (`git add .`, bare `--force`, `--no-verify`, force-pushing protected branches) are also blocked deterministically by the plugin's PreToolUse hook (`hooks/git-guard.sh`) — these rules explain the *why* and cover what a regex can't judge.

## Adaptive Output

Adjust your verbosity and explanation depth to the user's apparent experience level:

**Beginner signals:** asks "what does X mean?", hesitates, uses imprecise git terms ("upload" instead of "push"), asks for help, picks from numbered menus instead of typing commands.
→ Explain each step before executing. Use plain language. Add short explanations for git concepts in parentheses. Show full output examples. When asking questions, provide a **recommended default** in bold.

**Experienced signals:** uses correct git terminology, gives short commands ("just push it", "commit and push"), skips menus, types commit messages directly, says "quick" or "schnell".
→ Minimize questions. Skip "Next Steps" menus — just do the logical next thing or stop. Use terse output. Don't explain what `--force-with-lease` is. When the user says "all" or "quick", don't ask for confirmation on non-destructive steps.

**Default behavior (when unclear):** Lean towards safety — show what will happen, but keep explanations brief (one sentence, not a paragraph). Use recommended defaults with `[Enter]` to accept. Example:

```
Commit as separate commits per topic? (recommended) [y] / combined [c] / quick [q]
```

This lets beginners press Enter for the safe choice while experienced users type `q` instantly.

## Proactive Detection

Always check for these issues and act immediately when found:

| Situation | Response |
|---|---|
| File contains `<<<<<<<` conflict markers | Stop. Show the file and line. Offer to resolve. |
| Diff contains `console.log` or `debugger` | Warn. Show location. Offer to remove. |
| Diff contains patterns resembling secrets (API keys, tokens, passwords, connection strings) | Block the push. Show the pattern (redacted). Explain the risk. |
| Push includes incomplete features (component used but not defined, import without file) | Warn. Show what's missing. Ask if intentional. |
| Branch is >20 commits behind main | Suggest syncing before continuing work. |
| File appears in multiple topics | Mark with ⚡. Use hunk-level handling. |
| A forgotten stash exists | Remind the user with stash date and description. |
| Last commit is a merge commit but the repo convention is rebase (see Workflow Conventions) | Warn. Ask if this was intentional. |
| Force push is needed | Always `--force-with-lease --force-if-includes`. Explain why this is safer. |
| Force push or history rewrite targets a protected branch | Refuse. See Protected Branches. |
| Git history looks unusual (orphan commits, diverged branches) | Show what's happening. Ask before proceeding. |

## Staging Rules

- Never use `git add .` or `git add -A` — always stage specific files
- After staging, always show `git diff --cached --stat` for verification
- For mixed-topic files, use hunk-level staging (see references/hunk-analysis.md)

## Push Rules

- Always `git fetch origin` before pushing to check for remote changes
- When force is needed: `git push --force-with-lease --force-if-includes` (git ≥ 2.30). Plain `--force-with-lease` has a trap: any `git fetch` (including background fetches by IDEs) updates the remote-tracking ref and "blesses" the lease — teammate commits fetched but never integrated get silently overwritten. `--force-if-includes` closes that gap by requiring their commits to be part of your history.
- On git < 2.30, pin the lease explicitly: `--force-with-lease=<branch>:<expected-sha>`
- Only use bare `--force` with explicit user confirmation and an explanation of the risk
- Never bypass hooks: no `--no-verify`, no `-n` on commit/push. If a hook fails, fix the cause. If the user insists on bypassing, they must run that command themselves.
- Before pushing, check what will go out: `git log --oneline origin/<branch>..HEAD`

## Protected Branches

Never rewrite history on protected or shared-by-convention branches — no force push, no rebase of published commits, no `reset --hard` followed by force push. This applies to:

- The default branch (see Branch Detection)
- `master`, `main`, `develop`, `dev`, `staging`, `production`, and `release/*`
- Any branch protected on GitHub. When `gh` is available, check once per session:
  ```bash
  gh api "repos/{owner}/{repo}/branches/<branch>/protection" --jq .url 2>/dev/null
  ```
  HTTP 200 = protected (refuse rewrites), 404 = not protected, other errors = unknown (fall back to the name list).

If the user asks for a history rewrite on such a branch: refuse, explain why (teammates' clones break, CI reruns, open PRs invalidated), and offer `git revert` as the safe alternative. Do not offer an override — the user can run the command manually if they truly mean it.

## Shared Branch Detection

Before rewriting history on ANY branch, check whether others work on it:

```bash
git log origin/<branch> --format='%ae' | sort -u
```

More than one author email (ignoring bot addresses) → treat the branch as shared: warn that a force push rewrites teammates' history, recommend coordinating first, and require explicit confirmation naming the risk. One author (the user) → proceed with the normal force-with-lease rules.

## Workflow Conventions

Adapt to the repo instead of imposing preferences:

- **Merge vs. rebase:** `git log --merges --first-parent -20 --oneline origin/<default-branch>` — many merge commits means the team merges; don't flag merge commits as mistakes and offer `git merge` where the skill would default to rebase. `.claude-git.yml` may pin this via `workflow: rebase|merge`.
- **Commit style:** Look at `git log --oneline -20`. If the repo doesn't use Conventional Commits, match the existing style instead.
- **PR template:** If `.github/PULL_REQUEST_TEMPLATE.md` exists, PR bodies must follow it.

## Commit Rules

- Always show the proposed commit message and get user confirmation
- Default to Conventional Commits format (feat, fix, refactor, chore, style, docs) unless the repo's history uses a different style — see Workflow Conventions
- If a pre-commit hook fails, no commit was created — fix the cause and run `git commit` again (never `--no-verify`). If hooks auto-modified files, re-stage those files and commit again. Never `--amend` a commit that might already be pushed.
- Append the co-author/attribution trailer your harness or the user's instructions specify (if any); never hard-code a model name

## Destructive Operation Safety

Before any destructive operation, always:
1. Show exactly what will happen
2. Explain what could go wrong
3. Ask for explicit confirmation

Destructive operations include:
- `git reset --hard`
- `git checkout -- <file>` (discards changes)
- `git clean -f`
- `git push --force`
- `git rebase` (rewrites history)
- `git stash drop`

## Branch Detection

Detect the main branch automatically:
```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Fallback: check if `origin/main` exists, then `origin/master`.

The user's working branch is always the current branch (`git branch --show-current`).

## Secret Patterns

Scan diffs for these patterns before pushing:
- Strings starting with `sk-`, `pk-`, `api_`, `token_`, `secret_`
- Base64-encoded strings longer than 40 characters in assignment context
- Connection strings containing `://` with credentials
- `.env` file content patterns (`KEY=value`)
- AWS access keys (`AKIA...`)
- Private keys (`-----BEGIN`)

When detected: show the line (with value partially redacted), explain the risk, and do not proceed with push until resolved.

## Edge Cases

Check for these situations at the start of any skill:

**Detached HEAD:**
```bash
git branch --show-current
```
If empty, you're in detached HEAD. Warn the user and ask if they want to checkout a branch first. Most skills (push, sync, commit) need a branch name.

**No remote:**
```bash
git remote | head -1
```
If empty, there's no remote configured. Skills that fetch/push won't work. Inform the user.

**Shallow clone:**
```bash
git rev-parse --is-shallow-repository
```
If "true", warn that history commands (log ranges, merge-base, rev-list --count) may produce incomplete results. Suggest `git fetch --unshallow` if needed.

**Not a git repo:**
```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```
If this fails or returns "false", inform the user. Most skills require a git repository.

**Empty repo (no commits):**
```bash
git rev-parse HEAD 2>/dev/null
```
If this fails, the repo has no commits. Most skills won't work. Inform the user.

**Git worktree:**
```bash
git rev-parse --show-toplevel 2>/dev/null
```
If the toplevel path differs from the current working directory's parent `.git` location, you may be inside a worktree. In worktrees:
- `git stash` is shared across all worktrees — stashing here affects the main checkout
- `git checkout` to another branch may fail if that branch is checked out in another worktree
- `git branch -d` will refuse to delete a branch that's active in another worktree

When detected, inform the user: "You appear to be in a git worktree. Stash operations are shared with the main checkout."
