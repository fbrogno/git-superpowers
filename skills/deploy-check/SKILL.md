---
name: deploy-check
description: Catch deploy-config foot-guns before they crash the VM — port collisions against OTHER repos of the org (via gh, no cloning) and other branches, fixed container names, missing healthchecks, first-deploy gate with mandatory confirmation. Triggers: "deploy check", "port belegt", "port schon vergeben", "wird das deployment krachen", "container crash beim deploy", "docker-compose prüfen", "erster deploy", "neues repo deployen", "check before deploy", /deploy-check.
---

# Deploy Check

A deploy config that works alone can still crash a shared VM: a **new repo** claiming a host port that another project already uses, two branches declaring the same port, a fixed `container_name` colliding with the running stack, a zero-downtime setup without healthchecks. This skill finds those problems **before the deploy** — by reading configs across all repos of the org (git + gh, no cloning, no Docker) and gating first deploys behind an explicit confirmation.

## Safety (always apply)
- This skill only reads — it never deploys, restarts, or touches containers
- Findings name the concrete failure ("port 8080 also declared on origin/feature-x → bind error on shared VM"), not vague warnings
- The root fix is usually infra-side (dynamic ports, proxy) — always say so; a git check is the seatbelt, not the engine

## Workflow

### Step 1: Find the Deploy Surface

```bash
git ls-files | grep -iE '(^|/)(docker-)?compose[^/]*\.ya?ml$|(^|/)Dockerfile|\.service$|(^|/)Procfile$|(^|/)(k8s|deploy|manifests)/.*\.ya?ml$|(^|/)\.env(\.|$)|(^|/)(nginx|caddy|traefik)[^/]*\.(conf|ya?ml)$'
```

Nothing found → "No deploy configs tracked in this repo." Stop. Otherwise state what the deploy surface is (compose file(s), Dockerfiles, unit files, …) and which of it the current branch **changed** vs. the default branch (`git diff --name-only origin/<base>...HEAD` filtered by the same pattern).

### Step 2: Static Foot-Gun Audit

Read each deploy file the branch touches (full read for changed files only — unchanged configs just take part in Step 3). Check for:

**Port collisions waiting to happen**
- Hardcoded host ports: `- "8080:80"`, `- 127.0.0.1:8080:80`, long syntax `published: 8080`. A fixed host port means: second stack on the same VM (another branch, another project, the old container during deploy) → `bind: address already in use` → crash.
- Duplicate host ports *within* the same file (two services claiming one port).

**Zero-downtime killers**
- `container_name:` — fixed names prevent rolling replacement and collide across stacks; compose derives unique names when you drop it.
- No `healthcheck:` on services behind a proxy — the proxy/`--wait` cannot know when the new container is ready, so traffic switches into a booting container.
- Missing `restart:` policy — a VM reboot silently kills the service.

**Reproducibility & data risks**
- `image: something:latest` — the deploy you tested is not the deploy you get.
- Host-path volumes (`/opt/data:...`) shared by stacks that don't expect sharing.
- `.env` files with real-looking values committed (cross-check secret patterns from `references/git-safety.md`).

### Step 3: Collision Sources — Who Else Claims These Ports?

A hardcoded host port collides with whatever ALREADY runs on the target VM — usually **other repos**, not this one. Check the sources in order of reliability:

**3a. Other repos (the common case: a new repo claims a port some other project already uses).**

Local clones first — discover them the way repo-overview does, then read each repo's default-branch compose files:

```bash
for repo in <discovered-repo-paths>; do
  for f in $(git -C "$repo" ls-files 2>/dev/null | grep -iE '(docker-)?compose[^/]*\.ya?ml$'); do
    git -C "$repo" show "origin/HEAD:$f" 2>/dev/null || cat "$repo/$f"
  done | grep -hE '^\s*-?\s*"?([0-9.]+:)?[0-9]{2,5}:[0-9]+"?\s*$|published:\s*[0-9]+' | sed "s|^|$(basename $repo): |"
done
```

Then org repos that aren't cloned, via `gh` (no clone needed; 404s are normal, ignore them; `--limit 1000` because the default/small limits silently skip repos in larger orgs):

```bash
for r in $(gh repo list <org> --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner'); do
  # tree API finds compose files in subfolders too, still without cloning
  for f in $(gh api "repos/$r/git/trees/HEAD?recursive=1" --jq '.tree[].path' 2>/dev/null \
             | grep -E '(^|/)(docker-)?compose[^/]*\.ya?ml$'); do
    gh api "repos/$r/contents/$f" --jq .content 2>/dev/null | base64 -d 2>/dev/null \
      | grep -hE '"?([0-9.]+:)?[0-9]{2,5}:[0-9]+"?' | sed "s|^|$r/$f: |"
  done
done
```

Build the port→repo inventory and report every port this repo claims that another repo already claims. If a **port registry file** is configured (`.claude-git.yml` → `port_registry: <path>`), it is the authoritative inventory — check against it and offer to append this repo's claim after a successful deploy decision.

**3b. Branches of this repo** (branch-preview deploys): same extraction via `git show <branch>:<file>` across `git branch -r` — report ports/container_names claimed by more than one branch.

**3c. The VM itself — the only definitive answer.** Git sees intentions, not reality (manually started containers, non-git services). Hand off the check:

```
Before the first deploy, verify on the target VM:
  ss -tlnp | grep -E ':(8080|5432)\b'      # the ports this config claims
  docker ps --format '{{.Names}}  {{.Ports}}'
```

If `.claude-git.yml` defines `deploy_host: <ssh-alias>` (an SSH alias — never credentials), offer to run exactly these read-only commands via `ssh <alias>` — only after the user confirms, and nothing but these.

```
Port inventory for host port 8080:

  ⚠️ shop-backend (org repo, not cloned) also claims 8080
  ⚠️ VM check: 8080 currently bound by container "legacy-api"
  → deploying this repo as-is WILL crash. Options below.
```

### Step 4: First-Deploy Gate — Ask, Don't Assume

A brand-new repo with a hardcoded host port heading for its **first** deploy is the highest-risk moment: nothing has ever verified that port, and the push IS the deploy trigger. This is a **gate, not a warning** — do not proceed to push/deploy until one of these is true:

1. The port inventory (Step 3a) and the VM check (3c) both come back clean, **and the user explicitly confirms** ("port 8080 verified free on <VM> — deploy"), or
2. The config is changed so the collision cannot happen (Step 5, options 1-3) — the better answer; offer it first.

Additionally for new repos, audit everything (not just the diff): `.env` in `.gitignore` + `.env.example` without real values, image tags pinned, restart policy set, healthcheck present.

### Step 5: Recommend the Real Fix

Findings from Steps 2-3 get the infra-grade recommendation, not just "change the number":

1. **Let Docker assign host ports** (`ports: - "80"`) and route by name via a reverse proxy (traefik labels / nginx upstream) — collisions become impossible, for new repos too.
2. **Or parameterize**: `"${HOST_PORT:-8080}:80"` plus derivation per repo/branch/PR in CI — deploys stop sharing ports by construction.
3. **Scope the stack**: set `COMPOSE_PROJECT_NAME` per repo/environment so container/network/volume names never collide; drop `container_name:` entirely.
4. **Zero-downtime**: healthcheck + `docker compose up -d --wait` (or rolling `deploy.replicas` behind the proxy) — the old container keeps serving until the new one is healthy.
5. **Port registry** (when fixed ports must stay): one authoritative file (e.g. in the infra repo), every repo's claim recorded; `.claude-git.yml` → `port_registry: <path>` makes this skill check and maintain it. A registry beats tribal knowledge, but options 1-3 beat the registry.

Offer to apply the config changes (edit compose, add healthcheck, parameterize ports) — those edits then go through the normal /smart-commit → /safe-push → /pr-prep flow.

## Rules

- Read-only toward infrastructure: git and `gh` reads, plus at most the two read-only VM commands (`ss`, `docker ps`) via a configured SSH alias — each remote run individually confirmed by the user, nothing else, ever
- First deploy of a config with hardcoded host ports is a GATE: explicit user confirmation naming the verification, or the config gets fixed first — never push-and-hope
- Every collision finding names both sides (which repo/branch, which file, which line)
- Cross-repo/cross-branch analysis uses `git show` and the gh contents API — never clone or check out for this
- No new dependencies: detection is grep-based on YAML/config text; if a repo needs real YAML parsing, say so instead of guessing
- When the config is fine but the incident class is possible (shared VM, fixed ports), still surface recommendations 1-3 once — prevention beats detection
