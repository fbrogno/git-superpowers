---
name: release
description: Cut a clean release — semver bump from commit history, tag, generated notes, gh release create. Triggers: "release erstellen", "neue version", "cut a release", "version bump", "tag setzen", "release notes", /release.
---

# Release

Turn the commits since the last release into a versioned, documented release: correct semver bump, annotated tag, human-readable notes, GitHub release. Works for libraries, services, and plugins.

## Safety (always apply)
- Releases are cut from the default branch, up to date, with green checks — never from a dirty or diverged state
- Never move or delete an existing tag — a broken release gets a follow-up release
- Show tag, version, and notes for confirmation before anything is pushed
- Adapt verbosity to the user (see Adaptive Output in `references/git-safety.md`)

## Workflow

### Step 1: Preflight

```bash
git fetch origin --tags
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@'); [ -z "$BASE" ] && BASE=main
BRANCH=$(git branch --show-current)
git status --porcelain
git rev-list --count HEAD..origin/$BASE
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
echo "branch:$BRANCH base:$BASE last_tag:$LAST_TAG"
```

Requirements before continuing — each failure stops with a concrete instruction:
- On `$BASE` (releases from feature branches only on explicit request, e.g. release branches)
- Clean worktree, 0 behind origin
- CI green on HEAD: `gh run list --commit "$(git rev-parse HEAD)" --json conclusion --jq '.[].conclusion'` (skip silently if `gh` unavailable or repo has no CI)

### Step 2: What's in This Release?

```bash
git log --oneline ${LAST_TAG}..HEAD              # overview; "none" → use full history, suggest v0.1.0 or v1.0.0
git log --format=%B ${LAST_TAG}..HEAD | grep -E '^BREAKING[ -]CHANGE|^[a-z]+(\(.+\))?!:'   # full bodies: catches footers --oneline misses
```

Group by Conventional-Commit type. Derive the version bump:

- `feat!:` / `BREAKING CHANGE:` footer → **major**
- `feat:` → **minor**
- only `fix:`/`chore:`/`docs:`/`refactor:` → **patch**
- Repo doesn't use Conventional Commits → read the diffs (`git diff --stat ${LAST_TAG}..HEAD`), propose a bump, explain the reasoning

```
Since v2.1.0 (14 commits):

  Features:  3 (new pr-review skill, ci-fix skill, release skill)
  Fixes:     8 (safe-push large-file check, git-undo scenario 4, …)
  Breaking:  0

Proposed version: v2.2.0 (minor — features, no breaks)
OK, or different version?
```

### Step 3: Version Files

Find every place the version lives — tag and files must agree:

```bash
git grep -ln '"version"' -- '*.json' ':!*lock*.json' | head; ls setup.py pyproject.toml Cargo.toml 2>/dev/null
```

Update them (package.json, plugin manifest, marketplace.json, …), then commit:

```bash
git add <version-files>
git commit -m "$(cat <<'EOF'
chore(release): v<X.Y.Z>

<attribution trailer, if your harness or the user's instructions specify one>
EOF
)"
```

If a CHANGELOG.md exists (Keep-a-Changelog format), add the new section in the same commit.

### Step 4: Notes, Tag, Release

Generate notes from the grouped commits — what changed *for the user of the software*, not a raw commit list. Show everything for confirmation, then:

First decide how the version-bump commit reaches `$BASE`: check `gh api repos/{owner}/{repo}/branches/$BASE/protection` (success = protected) or simply ask the user: "direct push (unprotected repos) or release PR?"

**Direct push** (unprotected):
```bash
git tag -a v<X.Y.Z> -m "v<X.Y.Z>"
git push origin "$BASE" --follow-tags
```

**Release PR** (protected, or user prefers it): the bump commit goes via a branch, the tag comes after merge:
```bash
git switch -c release/v<X.Y.Z>        # ideally before Step 3's commit
# bump already committed on $BASE? the commit now lives on release/v<X.Y.Z> too, so move local $BASE back
# without touching the worktree (only if `git log origin/$BASE..$BASE` shows nothing but the bump commit):
git branch -f "$BASE" "origin/$BASE"
git push -u origin release/v<X.Y.Z>
gh pr create --base "$BASE" --title "chore(release): v<X.Y.Z>" --body "Version bump + changelog"
# after the PR is merged:
git switch "$BASE" && git pull --ff-only
git tag -a v<X.Y.Z> -m "v<X.Y.Z>" && git push origin v<X.Y.Z>
```

Then create the release:
```bash
gh release create v<X.Y.Z> --title "v<X.Y.Z>" --notes "$(cat <<'EOF'
<grouped notes>
EOF
)"
```

No `gh` → the pushed annotated tag is the release; offer the notes for copy-paste. Draft wanted → `--draft`. Fully automated notes → `--generate-notes` as fallback when the user doesn't care about curation.

### Step 5: Verify

```bash
gh release view v<X.Y.Z> --json url,tagName --jq .url
```

Show the URL. Remind about follow-ups only when they exist in the repo: publish workflows (`.github/workflows/*publish*`), plugin marketplace update, deployment triggers.

## Rules

- The tag always points at the version-bump commit, and file versions always match the tag
- Semver honestly: a breaking change in a "patch" costs users trust — when unsure, bump higher
- Release notes describe impact, not implementation ("faster repo scan" not "refactored loop")
- Existing tags are immutable — fixes go in the next version
- Pre-1.0 rules: breaking changes bump minor, everything else patch — say so when applying it
