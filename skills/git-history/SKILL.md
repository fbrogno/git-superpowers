---
name: git-history
description: Use when the user asks who changed something and why, or how a file, function or lines evolved — "wer hat das geändert", "warum sieht das so aus", "who changed this", "git blame", "Historie von dieser Datei", "wann wurde das eingeführt". Read-only investigation of past changes.
---

# Git History

Investigate the history of a file, function or line range and tell it as a narrative, not a wall of hashes.

## Safety
- Never run `git log` without a range or limit; start with `--oneline`, full diffs only when asked
- Use `--follow` to track renames; efficient patterns in `references/branch-history.md`
- "this file/function" without context: ask which, never guess

## Workflow

### 1. Target
File history, function history, line range, or blame ("who wrote this").

### 2. File history
```bash
git log --oneline --follow -- <file>
git log --oneline --follow --diff-filter=R -- <file>     # renames
```
Summarize: created (when, who, message), number of changes and contributors, last change, renames, then a short timeline. More than 30 commits: show the 10 most recent and offer more. Ask which commit to inspect.

### 3. Function or line history
```bash
git log --oneline -s -L :<funcname>:<file>      # bare list first; -s suppresses the patches -L forces
git log -p -L :<funcname>:<file>                # details; read at most the last 5 commits at first
git log -p -L <start>,<end>:<file>
```
Show the commit list, then ask which commits to see in detail.

### 4. Blame
`git blame <file>` or `git blame -L <start>,<end> <file>`. Never dump raw output; group by author with line counts and last-change dates, highlight very recent (active) or very old (stable or abandoned) sections, and quote the notable lines with their commit.

### 5. Narrative
Synthesize who introduced it, how it evolved and why (from commit messages), what is current logic and whose change it is. This is the value of the skill, not the raw git output.

### 6. Go deeper
Offer: full diff of a commit (`git show <commit> -- <file>`), another file, when a string appeared or vanished (`git log -S "<string>" --oneline -- <file>`), which commit deleted code (`git log --all --full-history --oneline -- <file>`, then `git show`).
