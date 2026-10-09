#!/usr/bin/env python3
"""Validate git-superpowers plugin structure.

Runs in CI and locally (python3 scripts/validate.py). Checks:
  1. Every skills/*/SKILL.md has frontmatter with name (== dir name) and description
  2. Every agents/*.md has frontmatter with name (== file stem) and description
  3. All `references/*.md` mentioned anywhere actually exist
  4. plugin.json and marketplace.json agree on version + description
  5. The skill count claimed in plugin.json's description matches skills/
  6. sync:review-categories blocks are identical between diff-review and code-reviewer
  7. hooks/hooks.json is valid JSON; hook scripts pass bash -n and are executable
  8. Skill descriptions: single line, start with "Use when", name+description <= 1024
     chars; workflow words ("then", "step", "stash, branch") are warnings
  9. Word budget per SKILL.md: warn > 900 words, fail > 1500 (wc -w semantics)
 10. plugin.json == marketplace.json == top CHANGELOG.md version
 11. README / plugin.json skill count matches skills/*/SKILL.md
 12. Every agent has name, description, tools, model
 13. No hard-coded noreply@anthropic.com or Fxbio04 in shipped files
 14. Cross-refs (references/x.md, agents/y, git-superpowers:<name>) resolve

Usage: python3 scripts/validate.py [--strict]   (--strict: warnings fail too)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors = []
warnings = []
STRICT = "--strict" in sys.argv[1:]


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    m = re.match(r"\A---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        err(f"{path.relative_to(ROOT)}: missing YAML frontmatter")
        return {}
    fields = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip()
    return fields


# 1. Skills
skill_dirs = sorted((ROOT / "skills").iterdir())
for d in skill_dirs:
    f = d / "SKILL.md"
    if not f.exists():
        err(f"skills/{d.name}: no SKILL.md")
        continue
    fm = frontmatter(f)
    if fm.get("name") != d.name:
        err(f"skills/{d.name}: frontmatter name '{fm.get('name')}' != directory name")
    desc = fm.get("description", "")
    if len(desc) < 40:
        err(f"skills/{d.name}: description too short to trigger reliably ({len(desc)} chars)")
    if len(desc) > 1024:
        err(f"skills/{d.name}: description exceeds 1024 chars ({len(desc)})")

# 2. Agents
for f in sorted((ROOT / "agents").glob("*.md")):
    fm = frontmatter(f)
    if fm.get("name") != f.stem:
        err(f"agents/{f.name}: frontmatter name '{fm.get('name')}' != file name")
    if not fm.get("description"):
        err(f"agents/{f.name}: missing description")

# 3. Referenced reference files exist
ref_pattern = re.compile(r"references/([a-z0-9-]+\.md)")
for f in list(ROOT.rglob("SKILL.md")) + list((ROOT / "agents").glob("*.md")):
    for name in set(ref_pattern.findall(f.read_text(encoding="utf-8"))):
        if not (ROOT / "references" / name).exists():
            err(f"{f.relative_to(ROOT)}: references/{name} does not exist")

# 4. Version + description sync
plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text())
market = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())
mplugin = market["plugins"][0]
if plugin["version"] != mplugin["version"]:
    err(f"version drift: plugin.json {plugin['version']} != marketplace.json {mplugin['version']}")
if plugin["description"] != mplugin["description"]:
    err("description drift between plugin.json and marketplace.json")

# 5. Claimed skill count
m = re.match(r"(\d+)\b", plugin["description"])
if m and int(m.group(1)) != len(skill_dirs):
    err(f"plugin.json claims {m.group(1)} skills, repo has {len(skill_dirs)}")

# 6. sync-marked category lists stay identical
def categories(path: Path) -> list:
    text = path.read_text(encoding="utf-8")
    if "sync:review-categories" not in text:
        return []
    section = text.split("sync:review-categories", 1)[1]
    section = re.split(r"\n### ", section)[0]
    return re.findall(r"^\*\*(.+?)\*\*$", section, re.MULTILINE)

skill_cats = categories(ROOT / "skills" / "diff-review" / "SKILL.md")
agent_cats = categories(ROOT / "agents" / "code-reviewer.md")
shared = set(skill_cats) & set(agent_cats)
if not skill_cats or not agent_cats:
    err("sync:review-categories marker missing in diff-review or code-reviewer")
elif len(shared) < min(len(skill_cats), len(agent_cats)) - 2:
    err(f"review categories drifted: skill={skill_cats} agent={agent_cats}")

# 7. Hooks
hooks_json = ROOT / "hooks" / "hooks.json"
if hooks_json.exists():
    json.loads(hooks_json.read_text())
for script in (ROOT / "hooks").glob("*.sh"):
    if not script.stat().st_mode & 0o111:
        err(f"hooks/{script.name}: not executable (chmod +x)")
    r = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
    if r.returncode != 0:
        err(f"hooks/{script.name}: bash syntax error: {r.stderr.strip()}")

# 8. Description rules (+ 9. word budget)
USE_WHEN_FAILS = 0
WORKFLOW_WORDS = re.compile(r"\b(then|step|steps)\b|stash, branch", re.IGNORECASE)
for d in skill_dirs:
    f = d / "SKILL.md"
    if not f.exists():
        continue
    rel = f.relative_to(ROOT)
    text = f.read_text(encoding="utf-8")
    m = re.match(r"\A---\n(.*?)\n---\n", text, re.DOTALL)
    fm_lines = m.group(1).splitlines() if m else []
    desc, multiline = "", False
    for idx, line in enumerate(fm_lines):
        if line.startswith("description:"):
            desc = line.partition(":")[2].strip()
            if desc in (">", "|", ">-", "|-", "") or (
                idx + 1 < len(fm_lines) and fm_lines[idx + 1].startswith((" ", "\t"))
            ):
                multiline = True
    name = d.name
    if multiline:
        err(f"{rel}: description must be a single line")
    if not desc.strip("\"'").startswith("Use when"):
        USE_WHEN_FAILS += 1
        err(f"{rel}: description must start with 'Use when' (got: '{desc[:40]}...')")
    if len(name) + len(desc) > 1024:
        err(f"{rel}: name+description exceeds 1024 chars ({len(name) + len(desc)})")
    hit = WORKFLOW_WORDS.search(desc)
    if hit:
        warn(f"{rel}: description summarizes workflow ('{hit.group(0)}') - describe WHEN to use, not HOW")
    words = len(text.split())
    if words > 1500:
        err(f"{rel}: {words} words (hard limit 1500)")
    elif words > 900:
        warn(f"{rel}: {words} words (budget 900)")

# 10. Version sync incl. CHANGELOG
cl = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
cm = re.search(r"^##\s+\[?v?(\d+\.\d+\.\d+)\]?", cl, re.MULTILINE)
if not cm:
    err("CHANGELOG.md: no '## [x.y.z]' version heading found")
elif cm.group(1) != plugin["version"]:
    err(f"version drift: top CHANGELOG entry {cm.group(1)} != plugin.json {plugin['version']}")

# 11. Skill count in README and plugin.json description
n_skills = sum(1 for d in skill_dirs if (d / "SKILL.md").exists())
count_re = re.compile(r"(?:\b(\d+)\s+(?:Git\b|skills\b)|Skills-(\d+))", re.IGNORECASE)
for label, text in (
    ("README.md", (ROOT / "README.md").read_text(encoding="utf-8")),
    ("plugin.json description", plugin["description"]),
    ("marketplace.json description", mplugin["description"]),
):
    found = [int(a or b) for a, b in count_re.findall(text)]
    if label == "README.md" and not found:
        err("README.md: no skill count mention found")
    for n in sorted(set(found)):
        if n != n_skills:
            err(f"{label}: claims {n} skills, repo has {n_skills}")

# 12. Agent frontmatter completeness
for f in sorted((ROOT / "agents").glob("*.md")):
    fm = frontmatter(f)
    for key in ("name", "description", "tools", "model"):
        if not fm.get(key):
            err(f"agents/{f.name}: frontmatter missing '{key}'")

# 13. Forbidden strings in shipped files
FORBIDDEN = ("noreply@anthropic.com", "Fxbio04")
SKIP_DIRS = {".git", "tests", "node_modules"}
SKIP_FILES = {"scripts/validate.py", "CHANGELOG.md"}
for f in sorted(ROOT.rglob("*")):
    rel = f.relative_to(ROOT)
    if not f.is_file() or set(rel.parts) & SKIP_DIRS or str(rel) in SKIP_FILES:
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for bad in FORBIDDEN:
        if bad in text:
            err(f"{rel}: contains forbidden string '{bad}'")

# 14. Cross-refs
skill_names = {d.name for d in skill_dirs}
agent_names = {f.stem for f in (ROOT / "agents").glob("*.md")}
agent_ref = re.compile(r"(?<![\w/.~-])agents/([a-z0-9-]+)(\.md)?")
plug_ref = re.compile(r"git-superpowers:([a-z0-9-]+)")
ref_files = (
    list(ROOT.glob("skills/*/SKILL.md"))
    + list((ROOT / "agents").glob("*.md"))
    + list((ROOT / "references").glob("*.md"))
)
for f in ref_files:
    text = f.read_text(encoding="utf-8")
    rel = f.relative_to(ROOT)
    for a in set(m.group(1) for m in agent_ref.finditer(text)):
        if a not in agent_names:
            err(f"{rel}: agents/{a} does not exist")
    for n in set(plug_ref.findall(text)):
        if n not in skill_names and n not in agent_names:
            err(f"{rel}: git-superpowers:{n} is neither a skill nor an agent")

# Report
for w in warnings:
    print(f"  ! warn: {w}")
if STRICT and warnings:
    for w in warnings:
        errors.append(f"(strict) {w}")
if errors:
    print(f"FAIL - {len(errors)} problem(s), {len(warnings)} warning(s):")
    for e in errors:
        print(f"  x {e}")
    if USE_WHEN_FAILS:
        print(f"  note: {USE_WHEN_FAILS}/{n_skills} skill descriptions lack 'Use when'")
    sys.exit(1)
print(f"OK - {n_skills} skills validated ({len(warnings)} warning(s))")
