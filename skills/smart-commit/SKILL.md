---
name: smart-commit
description: Group and commit changes by topic with hunk-level splitting. Triggers: commit, stage, push changes, "commit the bugfix not the feature", "nur die fixes committen", "commit nach themen", /smart-commit.
---

# Smart Commit

Commit changes grouped by topic — not by file. When a single file contains changes from multiple topics (a bugfix AND a feature), this skill splits them at hunk level (individual blocks of changed lines) so each commit is clean and focused.

## Safety (always apply)
- Never `git add .` or `git add -A` — always stage specific files
- Never `--force` — use `--force-with-lease`
- Confirm before destructive operations (reset --hard, force push)
- Scan for secrets before push (see `references/git-safety.md` for patterns)
- Check for detached HEAD, missing remote, shallow clone before starting

## Workflow

### Step 1: Preflight

```bash
git status
```

Check you're in a git repo. Show the current branch. If there are no changes, say so and stop.

### Step 2: Quick Scan

Gather an overview without reading full diffs — this keeps token usage low:

```bash
git diff --name-only                           # unstaged modified files
git diff --cached --name-only                  # already staged files
git ls-files --others --exclude-standard       # untracked files
git diff --stat                                # line-change summary
```

If there are already staged files, ask the user: "Some files are already staged. Should I include them in the topic grouping or leave them as-is?"

### Step 3: Topic Detection

For complex changes (>10 files or many shared files), spawn the `git-superpowers:topic-analyzer` agent with the list of changed files and repo path. For simpler changes, follow the strategy inline.

Read `references/topic-detection.md` for the full strategy.

Group all changed files by topic using progressive detail:
1. **Path-based grouping** — files in the same directory likely belong together
2. **Config-based** — if `.claude-git.yml` exists, use its topic mappings
3. **Semantic analysis** — for shared/ambiguous files only, read their diff with `git diff <file>` and determine the topic from code content (imports, function names, comments)

For each file, determine if it contains changes from multiple topics. If yes, mark it with ⚡.

### Step 4: Present Topics

Show a numbered list of topics with their files. Format: `[N] Topic Name (X files)` followed by file list with `M/A/D` status. Mark mixed-topic files with ⚡. Explain ⚡ means "contains changes from multiple topics — will be split at hunk level (only the parts belonging to your chosen topic get committed)."

Ask: **"Which topics do you want to commit? (e.g. '1,3' or 'all')"**

### Step 4.5: Commit Strategy

After the user selects topics, ask how they want to commit them:

```
How should these be committed?

[s] Separate commits — one per topic (recommended — keeps history clean and reviewable)
[c] Combined — all selected topics in one commit (simpler, but harder to review later)
[q] Quick — commit everything, auto-generate message, skip review (for when you know what you're doing)
```

**Separate (default):** Each topic gets its own commit with a focused message. This is the standard flow — continue to Step 5.

**Combined:** Stage all selected files at once, write one commit message that covers all topics. Skip the loop in Step 10.

**Quick mode:** Stage all files from selected topics, generate a commit message automatically, commit without asking for message confirmation, and show `git diff --cached --stat` only as a summary (not as a question). Useful when the user says things like "schnell committen", "just commit it", "alles rein". Still respects all safety rules (no `git add .`, secret scan if pushing).

If only 1 topic was selected, skip this question and go straight to Step 5 (there's nothing to combine).

### Step 5: Stage Selected Topics

Staging means marking files as "ready to commit" — only staged files go into the commit.

For **single-topic files**: simply `git add <file>`

For **⚡ mixed files** (files with changes from multiple topics): use hunk-level splitting to stage only the relevant parts. Read `references/hunk-analysis.md` for the detailed approach:
1. Use `git show HEAD:<file>` to see the original state of lines that need to be reverted for selective staging
2. Back up the file
3. Edit the file to remove changes belonging to OTHER topics (revert those lines to their original state)
4. `git add <file>`
5. Restore the full file from backup

### Step 6: Verify Staging

```bash
git diff --cached --stat
```

Show this to the user. Ask: "This is what will be committed. Look correct?"

If the user spots something wrong, `git reset HEAD <file>` for the problematic file and redo.

**Tip:** Run `/diff-review` before committing to catch bugs and logic errors in your changes.

### Step 7: Commit Message

Propose a commit message using Conventional Commits (a standard format that makes commit history easy to read):

**Prefix** based on change type:
- `feat:` — new functionality
- `fix:` — bugfix
- `refactor:` — restructuring without behavior change
- `chore:` — maintenance, dependencies
- `style:` — formatting only
- `docs:` — documentation

**Scope** from the topic: `feat(auth):`, `fix(amazon):`, `chore(deps):`

Show the proposed message and ask for confirmation. Let the user edit or accept with Enter.

### Step 8: Commit

Use HEREDOC format:
```bash
git commit -m "$(cat <<'EOF'
feat(amazon): add analytics dashboard with KPI grid and charts

- DashboardView with KPI cards and trend visualization
- ProductAnalysisView with cluster filtering

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
```

### Step 9: Push (Optional)

Ask: "Push to origin/<branch>?"

If yes, check for remote changes first:
```bash
git fetch origin
git log --oneline HEAD..origin/<branch>
```

If remote has new commits, warn and suggest `git pull --rebase origin <branch>` first.

Then push: `git push origin <branch>`

### Step 10: Loop and Next Steps

```bash
git status
```

If more changes remain, show them grouped by topic again and ask: "More topics to commit?"

If no changes remain (or the user is done):

```
All done. Next steps:
[r] Run /diff-review to check for bugs before pushing
[p] Run /safe-push to audit and push
[pr] Run /pr-prep to create a pull request
[d] Done — nothing else needed
```

Skip this menu in quick mode — just show "Committed. Run `/safe-push` when ready to push."

## Rules

- Never use `git add .` or `git add -A` — always stage specific files or hunks
- Always show `git diff --cached --stat` after staging for verification
- Always show the commit message for user approval before committing
- On pre-commit hook failure: fix the issue and create a NEW commit (never `--amend`)
- Append the co-author/attribution trailer your harness or the user's instructions specify (if any); never hard-code a model name
