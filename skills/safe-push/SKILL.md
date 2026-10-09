---
name: safe-push
description: Pre-push audit — scans for debug statements, secrets, conflict markers, incomplete features and fixes them. Triggers: push, "pushen", "ab damit", "hochladen", "check before push", /safe-push.
---

# Safe Push

Audit outgoing commits for common mistakes and fix them before pushing. This is not just a linter — it understands your code, catches semantic issues (unused imports from an unfinished feature, missing files that a component depends on), and actively fixes what it finds.

## Safety (always apply)
- Never push without showing what goes out first
- Always scan for secrets before push (see `references/git-safety.md` for patterns)
- Never `git add .` — stage specific files only
- Create separate cleanup commits (never amend already-pushed commits)
- Check for detached HEAD, missing remote, shallow clone before starting

## Workflow

### Step 1: What's Going Out?

```bash
git fetch origin
git log --oneline origin/<branch>..HEAD
```

If nothing to push: "Nothing to push — your branch is up to date with origin." Stop.

Show the outgoing commits and a file summary:
```bash
git diff --stat origin/<branch>..HEAD
```

Format: "N commits to push to origin/`<branch>`:" followed by commit list and file change summary.

### Step 1.5: Conflict Prediction

Before auditing code quality, check if your branch will have conflicts when rebasing onto the default branch later. Detect it first (see Branch Detection in `references/git-safety.md`), then run the overlap check:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null && BASE=main || BASE=master; }
# Quick overlap check: files changed in both your branch and $BASE
MERGE_BASE=$(git merge-base HEAD origin/$BASE)
comm -12 \
  <(git diff --name-only $MERGE_BASE..HEAD | sort) \
  <(git diff --name-only $MERGE_BASE..origin/$BASE | sort)
```

If overlapping files exist, warn:
```
⚠️ Conflict prediction: 2 files overlap with main
  src/routes.tsx — you and main both modified this
  package.json — different dependency changes

Consider running /smart-sync before pushing to avoid conflicts later.
```

If no overlap: continue silently (don't clutter the output).

For a deeper simulation with severity analysis, suggest: "Run `/conflict-simulator` for a full conflict analysis."

### Step 2: Audit

Run all audit checks in a single pass over the diff output — read `git diff origin/<branch>..HEAD` once and scan for all patterns simultaneously. Do not read the diff separately for each check.

Run these checks against the outgoing diff (`git diff origin/<branch>..HEAD`):

**Check 1: Debug Artifacts**
Scan for added lines containing:
- `console.log`, `console.debug` (not in test files or logging utilities)
- `debugger` statements
- `print(` that looks like debug output

**Check 2: Conflict Markers**
Scan the diff output from above for conflict marker patterns (`<<<<<<<`, `=======`, `>>>>>>>`).
(Already captured in the audit step — reuse the same output.)

**Check 3: Secret Patterns**
Scan added lines for patterns from `references/git-safety.md` secret patterns section.

**Check 4: Incomplete Features**
Read the diff semantically:
- Are there imports for files/modules that don't exist in the push?
- Are there components/functions referenced but not defined?
- Are there TODO/FIXME/HACK comments in new code?

**Check 5: Large Files**

`--stat` misses binaries (they show as `Bin`), and `\d` doesn't work in POSIX grep — check actual blob sizes in the outgoing commits instead:

```bash
git rev-list --objects origin/<branch>..HEAD \
  | git cat-file --batch-check='%(objectsize) %(objecttype) %(rest)' \
  | awk '$2 == "blob" && $1 > 1048576 {printf "%.1f MB  %s\n", $1/1048576, $3}' \
  | sort -rn
```

Anything over 1 MB gets flagged; over 50 MB will be rejected by GitHub outright. For accidentally committed binaries, offer to remove them from the outgoing commits before pushing (and suggest Git LFS if they're intentional).

**Check 6: Deploy Configs**
Only when the outgoing diff touches deploy files (`docker-compose*`/`compose*.yml`, `Dockerfile`, k8s manifests, `.service`, `.env*`, proxy configs): scan the added lines for the foot-guns that crash shared VMs instead of CI — hardcoded host ports (`- "8080:80"`), `container_name:`, `image: …:latest`, host-path volumes, committed `.env` values. These collide with whatever is already running on the VM (usually **other repos**) at deploy time, not at build time.

⚠️ **Gate, not warning — when this push triggers the FIRST deploy** (new repo without upstream, or the deploy config first appears in this diff) and a hardcoded host port is in it: do NOT push until the port is verified. Run the `/deploy-check` port inventory (other repos via gh, VM handoff `ss -tlnp | grep :<port>`), then require explicit confirmation naming the verification ("port 8080 checked free on the target — push"). Better: offer the config fix first (env-var port / proxy routing) so verification becomes unnecessary. For subsequent pushes, a normal numbered finding with `/deploy-check` handoff is enough.

### Step 3: Report and Fix

If all checks pass:
```
Safe Push Audit ✓

3 commits, 12 files — no issues found.
Push to origin/fb? (y/n)
```

If issues found, show them numbered with file:line and the actual code. Show ✓ for passed checks. Then ask which issues to fix (they can pick numbers, "all", or "ignore").
- Each numbered issue as an option
- "Fix all"
- "Ignore and push anyway"

### Step 4: Apply Fixes

For each selected fix:

**Debug artifacts**: Read the file, remove the debug line, save. If removing the line would break the code (e.g., it's the only statement in a block), replace with appropriate code or a comment.

**Missing files**: Check if the file exists but wasn't staged. If yes: `git add <file>`. If the file doesn't exist at all, warn: "This file doesn't exist yet — remove the import or create the file?"

**TODOs**: Ask what should happen — implement it, remove the comment, or leave it.

**Secrets**: Show the line (redacted), explain the risk, ask the user to remove it manually or offer to replace with an environment variable reference.

After fixes, create a cleanup commit:
```bash
git add <fixed-files>
git commit -m "$(cat <<'EOF'
chore: cleanup before push

- Remove debug statements
- [other fixes applied]

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
```

Show `git diff --cached --stat` before committing for verification.

### Step 5: Push

```bash
git push origin <branch>
```

If push fails due to remote changes:

```
Push failed — the remote has new commits you don't have yet.

Options:
[1] Run /smart-sync to rebase onto the latest remote (recommended — handles conflicts)
[2] Quick pull --rebase (only if you're confident there won't be conflicts)
```

If the user chooses option 2:
```bash
git pull --rebase origin <branch>
```

If `pull --rebase` causes conflicts, **abort immediately** and redirect to smart-sync:
```bash
git rebase --abort
```
"Conflicts during pull. Run `/smart-sync` for guided conflict resolution."

Show confirmation and suggest next steps:

```
Pushed 4 commits to origin/fb ✓

What's next?
[pr] Run /pr-prep to create a pull request
[o]  Run /repo-overview to check other repos
[d]  Done
```

## Rules

- Never push without showing what's going out first
- Always scan for secrets before pushing — this is non-negotiable
- Show each issue with file, line number, and the actual code
- Fix issues directly — don't just warn and leave it to the user
- Create a separate cleanup commit for fixes (never amend existing commits that might already be pushed)
- Use `git push` (not force push) — if force is needed, suggest smart-sync first
