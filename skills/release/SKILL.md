---
name: release
description: Use when the user wants to publish a new version — "release erstellen", "neue Version", "cut a release", "version bump", "Tag setzen", "tag v1.2.0", "release notes schreiben", "GitHub Release". Not for urgent production fixes (hotfix) or for opening a normal PR (pr-prep).
---

# Release

Turn the commits since the last release into a version bump, an annotated tag, human-readable notes and a GitHub release.

## Iron Law

```
NEVER MOVE OR DELETE A PUBLISHED TAG, AND NEVER PUSH A TAG OR RELEASE THE USER HAS NOT CONFIRMED
```

A broken release gets a follow-up release, not a rewritten tag.

## Red Flags

| Thought | Reality |
|---|---|
| "The tag is wrong, I'll just force-move it" | Consumers, caches and registries already saw it. Cut the next version. |
| "CI was green yesterday" | Check CI on THIS HEAD now (`gh run list --commit`). |
| "Small change, patch bump is fine" | A breaking change in a patch costs trust. When unsure, bump higher. |
| "I'll push the tag, then fix the changelog" | Tag and files must agree before anything is pushed. |
| "Direct push to the default branch, it's quicker" | Check branch protection; protected means release PR. |

## Workflow

### 1. Preflight
```bash
git fetch origin --tags
# $BASE per references/common-snippets.md#base-branch
git status --porcelain; git rev-list --count HEAD..origin/$BASE
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)   # empty = no tag yet
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"                     # no tag: full history
```
Required, each failure stops with a concrete instruction: on `$BASE` (release branches only on request), clean tree, 0 behind, CI green on HEAD (`gh run list --commit "$(git rev-parse HEAD)" --json conclusion --jq '.[].conclusion'`, skip if no `gh` or no CI).

### 2. What's in it
```bash
git log --oneline "$RANGE"               # no tag: suggest v0.1.0 or v1.0.0
git log --format=%B "$RANGE" | grep -E '^BREAKING[ -]CHANGE|^[a-z]+(\(.+\))?!:'
```
Group by Conventional-Commit type. `feat!:`/BREAKING footer = major, `feat:` = minor, otherwise patch. Not Conventional: read `git diff --stat "$LAST_TAG" HEAD` (no tag: `git log --stat`) and propose with reasoning. Pre-1.0: breaking = minor, rest = patch (say so). Show counts and the proposed version; let the user override.

### 3. Version files
Find every place the version lives: `git grep -ln '"version"' -- '*.json' ':!*lock*.json'`, `setup.py`, `pyproject.toml`, `Cargo.toml`, plugin/marketplace manifests. Update them, add a CHANGELOG.md section if the repo keeps one, commit `chore(release): v<X.Y.Z>` per `references/common-snippets.md#commit-template`.

### 4. Notes, tag, release
Write notes about impact for users ("faster repo scan"), not implementation. Show tag, version and notes; wait for confirmation. Check protection (`gh api repos/{owner}/{repo}/branches/$BASE/protection`) or ask: direct push or release PR.

Direct push:
```bash
git tag -a v<X.Y.Z> -m "v<X.Y.Z>" && git push origin "$BASE" --follow-tags
```
Release PR: branch `release/v<X.Y.Z>` carries the bump commit (create it before step 3's commit; if the commit is already on `$BASE` locally, in this order: (1) `git switch -c release/v<X.Y.Z>`, (2) then `git branch -f "$BASE" "origin/$BASE"`, only when `git log origin/$BASE..$BASE` shows nothing but the bump; `branch -f` cannot move the checked-out branch), push, `gh pr create`, and after merge `git switch "$BASE" && git pull --ff-only`, then tag and `git push origin v<X.Y.Z>`.

Then `gh release create v<X.Y.Z> --title "v<X.Y.Z>" --notes "<notes>"` (`--draft` if wanted, `--generate-notes` if the user does not care). No `gh`: the pushed annotated tag is the release; offer notes to copy.

### 5. Verify
Fresh output only: `gh release view v<X.Y.Z> --json url,tagName --jq .url` and `git ls-remote --tags origin v<X.Y.Z>`. Do not say "released" or "CI green" without them (`references/common-snippets.md#verification`; superpowers: `superpowers:verification-before-completion`). Mention follow-ups only if they exist (publish workflow, marketplace update, deploy trigger).

## Rules

- The tag points at the version-bump commit; file versions match the tag
- Existing tags are immutable
- Semver honestly; notes describe impact
