---
name: selective-merge
description: Take specific files from another branch (not whole commits) with merge-parts option. Triggers: "hol mir die datei von", "get file from branch", "ich brauch die version von", "take file from", /selective-merge.
---

# Selective Merge

Take specific files from another branch without merging the whole branch. This brings the file's current state — not a commit — into your working tree. You decide what to commit afterward.

## Safety (always apply)
- Never overwrite uncommitted local changes without explicit confirmation
- Always show diff between branches before applying anything
- Never commit the result — leave that to the user or smart-commit
- Check for detached HEAD and missing remote before starting

## Workflow

### Step 1: Gather Intent

If the user hasn't specified everything, ask:

- **Which file(s)?** — exact path(s)
- **Which branch?** — local branch name, `origin/<branch>`, or a remote URL

Examples of how to interpret the request:
- "get api.ts from bobby's branch" → file: `src/api.ts` (or wherever it lives), branch: `bobby` (or `origin/bobby`)
- "ich brauch die version von main" → file: from context of current conversation, branch: `origin/main`

Resolve the branch to a full ref:
```bash
git fetch origin                          # make sure remote refs are current
git branch -a | grep <branch-name>        # find the branch
```

### Step 2: Show What Is Different

First, check if the file exists in both branches:

```bash
# Does the file exist on the source branch?
git cat-file -e origin/<branch>:<file> 2>/dev/null || echo "FILE_NOT_ON_SOURCE"

# Does the file exist on the current branch?
git ls-files --error-unmatch <file> 2>/dev/null || echo "FILE_NOT_LOCAL"
```

If the file doesn't exist on the source branch: "This file doesn't exist on origin/`<branch>`. Nothing to take." Stop.

If the file exists on the source but not locally, inform the user: "This file doesn't exist on your branch yet — it will be added as a new file."

Then show what would change:

```bash
git diff HEAD..origin/<branch> -- <file>
```

Present this clearly:
```
Difference in src/api/orders.ts between your branch and origin/feature-bobby:

  +  export async function getOrdersByCustomer(customerId: string) {
  +    const result = await db.query(...)
  +    return result.rows
  +  }
  -  // TODO: implement
```

If the diff is empty: "This file is identical in both branches. Nothing to do."

### Step 3: Check for Local Conflicts

Check whether the target file has uncommitted local changes that would be overwritten:

```bash
git status -- <file>
```

If the file is modified or staged locally:

```
⚠ src/api/orders.ts has uncommitted local changes:

<show the local diff>

Taking the version from origin/feature-bobby will overwrite these changes.
They are NOT in any commit — they would be permanently lost.

Options:
[1] Stash my changes first, then take the file from the other branch
[2] Commit my changes first, then take the file (creates a merge point)
[3] Take the file anyway — I don't need my local changes
[4] Cancel
```

Wait for the user's choice before proceeding.

If option 1: `git stash push -u -m "selective-merge: park work before taking <file>"`
If option 2: guide through a quick commit of the local file first

### Step 4: Choose Merge Strategy

Ask:

```
How do you want to take src/api/orders.ts from origin/feature-bobby?

[1] Replace completely — take their version as-is
[2] Merge specific parts — choose which changes to keep
```

**Replace (option 1):**

```bash
git restore --source=origin/<branch> --worktree -- <file>
```

The file now has the other branch's content in the working tree — deliberately NOT staged, so it goes through the normal staging flow in Step 6 like any other change. (The older `git checkout origin/<branch> -- <file>` would stage it as a side effect.)

**Merge parts (option 2):**

Show the diff from Step 2 again, broken into hunks. For each hunk, ask:
- "Take this change?"
- Show the hunk with context

For each selected hunk:
- Read the current file
- Apply the hunk manually (add the new lines, remove the old lines at the right position)
- Write the updated file

After all hunks: show the resulting file content and confirm it looks right.

### Step 5: Verify the Result

Show the file's new state in the working tree:

```bash
git diff HEAD -- <file>
```

Ask: "Does this look right?"

If the user stashed in Step 3, offer to pop the stash now:

```bash
git stash pop
```

If stash pop conflicts with the newly applied file, explain: "The stash conflicts with the file you just took. Resolve the conflict in <file>, then run `git stash drop` to discard the stash."

### Step 6: Inform — Do Not Commit

The file is now modified in the working tree. Do not commit automatically.

Tell the user:

```
src/api/orders.ts is now in your working tree with the version from
origin/feature-bobby. It is not committed yet.

When you're ready, commit it:
  git add src/api/orders.ts
  git commit -m "..."

Or use /smart-commit to group it with other changes.
```

## What This Skill Does Not Do

- It does not bring commit history from the other branch
- It does not create a merge commit
- It does not cherry-pick — it takes the file's current state, not a specific commit's changes
- It does not work with whole directories (ask the user to be specific about files)

## Rules

- Never overwrite uncommitted local changes without explicit confirmation
- Always show the diff between branches before applying anything
- Always show the result after applying so the user can verify
- Never commit the result — leave that to the user or to smart-commit
- If multiple files are requested, handle them one by one and confirm each
