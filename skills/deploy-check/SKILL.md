---
name: deploy-check
description: Use when a deploy config might crash a shared server — "port belegt", "port schon vergeben", "wird das Deployment krachen", "docker-compose prüfen", "erster Deploy", "neues Repo deployen", "container crash beim Deploy", "check before deploy". Read-only check of compose, Dockerfile and service configs for port collisions across repos and branches.
---

# Deploy Check

A config that works alone can crash a shared VM: a new repo claiming a host port another project uses, two branches declaring the same port, a fixed `container_name`, no healthchecks. Find these before the deploy by reading configs across the org (git + gh, no cloning, no Docker) and gate first deploys behind an explicit confirmation.

## Safety
- Read-only: never deploys, restarts or touches containers
- Findings name the concrete failure ("port 8080 also declared on origin/feature-x, bind error on shared VM") and both sides (repo/branch, file, line)
- The root fix is infra-side (dynamic ports, proxy); a git check is the seatbelt, say so
- Cross-repo analysis via `git show` and the gh contents API, never clone or check out

## Workflow

### 1. Deploy surface
```bash
git ls-files | grep -iE '(^|/)(docker-)?compose[^/]*\.ya?ml$|(^|/)Dockerfile|\.service$|(^|/)Procfile$|(^|/)(k8s|deploy|manifests)/.*\.ya?ml$|(^|/)\.env(\.|$)|(^|/)(nginx|caddy|traefik)[^/]*\.(conf|ya?ml)$'
```
Nothing: "No deploy configs tracked", stop. Else list the surface and which files this branch changed (`git diff --name-only origin/$BASE...HEAD`, `$BASE` per `references/common-snippets.md#base-branch`).

### 2. Static audit (changed deploy files only)
- **Ports**: hardcoded host ports (`"8080:80"`, `127.0.0.1:8080:80`, `published: 8080`) collide with any second stack on the VM; duplicate host ports within one file.
- **Zero-downtime**: `container_name:` (blocks rolling replacement), no `healthcheck:` behind a proxy, no `restart:` policy.
- **Reproducibility**: `image: x:latest`, shared host-path volumes, committed real-looking `.env` values (`references/git-safety.md#secret-patterns`).

### 3. Who else claims these ports?
**3a. Other repos** (the common case). Local clones: for each discovered repo, read compose files from the default branch (`git -C "$repo" show "origin/HEAD:$f"`) and grep port mappings (`^\s*-?\s*"?([0-9.]+:)?[0-9]{2,5}:[0-9]+"?\s*$|published:\s*[0-9]+`). Uncloned org repos via gh (404s are normal; `--limit 1000`):
```bash
for r in $(gh repo list <org> --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner'); do
  for f in $(gh api "repos/$r/git/trees/HEAD?recursive=1" --jq '.tree[].path' 2>/dev/null | grep -iE '(^|/)(docker-)?compose[^/]*\.ya?ml$'); do
    gh api "repos/$r/contents/$f" --jq .content 2>/dev/null | base64 -d 2>/dev/null | grep -hE '"?([0-9.]+:)?[0-9]{2,5}:[0-9]+"?' | sed "s|^|$r/$f: |"
  done   # tree API truncates above ~100k entries: for such monorepos say the scan may be incomplete
done
```
Build the port-to-repo inventory and report every port this repo claims that another claims. `.claude-git.yml` `port_registry: <path>` is authoritative if set; offer to append this repo's claim.

**3b. Branches of this repo**: same extraction via `git show <branch>:<file>` over `git branch -r`; report ports and container names claimed by more than one branch.

**3c. The VM** is the only definitive answer (git sees intentions, not reality). Hand off: `ss -tlnp | grep -E ':(8080|5432)\b'` and `docker ps --format '{{.Names}}  {{.Ports}}'`. If `.claude-git.yml` has `deploy_host: <ssh-alias>`, offer to run exactly these two read-only commands via `ssh <alias>`, each only after the user confirms. Never credentials.

### 4. First-deploy gate
A new repo with a hardcoded host port heading for its first deploy is the riskiest moment (the push is the trigger). This is a gate, not a warning: do not push or deploy until either (1) inventory and VM check are clean AND the user explicitly confirms ("port 8080 verified free on <VM>, deploy"), or (2) the config is changed so collisions cannot happen (step 5, options 1-3; offer first). For new repos also audit everything: `.env` ignored plus `.env.example` without real values, pinned tags, restart policy, healthcheck.

### 5. Recommend the real fix
1. Let Docker assign host ports (`ports: - "80"`) and route by name via a reverse proxy.
2. Or parameterize: `"${HOST_PORT:-8080}:80"` derived per repo/branch/PR in CI.
3. Scope stacks with `COMPOSE_PROJECT_NAME`; drop `container_name:`.
4. Healthcheck plus `docker compose up -d --wait` for zero downtime.
5. Port registry if fixed ports must stay (options 1-3 beat it).

Offer to apply config edits, which then follow `/smart-commit` → `/safe-push` → `/pr-prep`. Even when the config is fine on a shared VM, mention options 1-3 once.

## Rules
- Remote commands limited to the two read-only ones above, each confirmed by the user
- Detection is grep-based; if real YAML parsing is needed, say so instead of guessing
