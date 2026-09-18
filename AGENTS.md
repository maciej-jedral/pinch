# Pinch — agent briefing

Read this whole file before doing anything. It is the single source of truth for what exists and what was
decided. Keep it current: update it at the end of every session that changes any of it.
It is written for AI agents, not for people; per-repo READMEs hold the human-facing docs and the ops how-to.

## What this is

Pinch is a learning/portfolio project: a Symfony API + Next.js frontend, deployed for real. Four public
MIT repos under `github.com/maciej-jedral`, linked as git submodules of this meta-repo:

| Repo | Holds | Live |
|---|---|---|
| `pinch` (this) | `docker-compose.yml`, `install.sh`, this file | — |
| `pinch-backend` → `backend/` | Symfony 7.4 / PHP 8.4 on FrankenPHP; `Dockerfile`, `compose.prod.yml`, deploy workflow | `https://api.pinchapp.fyi` |
| `pinch-frontend` → `frontend/` | Next.js 16 (App Router, TS strict, Tailwind v4) | `https://pinchapp.fyi` |
| `pinch-terraform` → `terraform/` | AWS EC2 + Neon Postgres + Porkbun DNS + budget, Terraform 1.16 via `./tf` (Docker) | — |

Local dev: `./install.sh` → `docker compose up` (Postgres 18, backend on :8000, frontend on :3000). The
homepage fetches `GET /api/hello`, which does a `SELECT 1` — that is the entire app.

## Rules for agents

- **Grill, then confirm, then build.** For anything non-trivial run the grilling interview (numbered
  rounds with recommendations), get an explicit go-ahead, then implement. Record outcomes here.
- **Respect deferrals.** When the user says something is out of scope, leave it out entirely — no
  "small additions". Plans are not tracked in this repo; ask the user.
- **Nothing runs on the host.** No php/composer/node/npm/terraform/aws binaries: `docker compose exec
  backend composer …`, `docker compose exec frontend npm …`, `terraform/tf …`.
- **Submodule change = three steps**: commit+push inside `backend/`/`frontend/`/`terraform/` → in `pinch`:
  `git add <submodule> && git commit -m "Bump … submodule" && git push` → done. Skipping step 2 leaves
  `install.sh` checking out stale code.
- **Merging to `main` is releasing** for backend (Actions → deploy) and frontend (Vercel). PRs run
  checks/previews only. The user merges PRs in the browser.
- **Terraform**: `./tf plan -out=x.tfplan` → user reviews → `./tf apply x.tfplan`. Never a blind apply.
- Next 16 differs from training data: read `node_modules/next/dist/docs/` (via `docker compose exec
  frontend cat …`) before writing Next code.
- Dashboards (Vercel, Neon, Porkbun, AWS, GitHub settings) are the user's — hand them numbered steps.

## Current state

**Backend** — `pinch-backend/.github/workflows/deploy.yml`: PR → `check` (php-cs-fixer, phpstan level 8,
PHPUnit vs Postgres 18); push to `main` → `check` → `build` (arm64 `prod` image → GHCR `sha-<sha>` +
`latest`) → `deploy` (SSH as `ubuntu` to the box, write `/opt/pinch/{compose.yml,.env}`, `pull`,
`doctrine:migrations:migrate`, `up -d`, smoke test). Rollback = re-run an older run (code only — write expand/contract migrations). Secrets in the GitHub
`production` environment. GHCR package is private; the deploy job uses the job token. TLS terminates in the container: `SERVER_NAME="api.pinchapp.fyi, :8000"` gives
Caddy a Let's Encrypt cert on 80/443 (certs in the `caddy_data` volume) and an unpublished `:8000` for the
healthcheck. Ops how-to: `backend/README.md` → *Operations*.

**Frontend** — Vercel Hobby, GitHub integration (push to `main` → prod, PR → preview), functions pinned
to `fra1`, domains `pinchapp.fyi` + `www` (redirect). Server-side fetch to `BACKEND_INTERNAL_URL=
https://api.pinchapp.fyi` (env changes need a manual Redeploy). No CI workflow; Vercel's `next build`
(typecheck) is the only gate. Dev bundler is webpack, prod is Turbopack: `next.config.ts` has a `webpack()` override (watch
polling only) and a load-bearing empty `turbopack: {}` — any real webpack customisation must be mirrored.

**Infra** (`terraform/`, README is the how-to) — AWS **Free-plan** account (cannot bill; **auto-closes
~2027-03-14**; never upgrade it to Paid): `t4g.micro` Ubuntu 24.04 arm64 in the default VPC, Elastic IP
`63.182.98.240`, SG 22/80/443, cloud-init installs Docker and authorises the CI deploy key, Budgets alert
at $15 gross. State in S3 (`bootstrap/`), IAM user `terraform` with a scoped policy. **Neon** free-tier
Postgres (Frankfurt, PG 18, project `small-bird-75248934`) and **Porkbun** DNS records (`dns.tf`, provider
`jianyuan/porkbun`) both live outside AWS on purpose. Domain `pinchapp.fyi` at Porkbun, **auto-renew off,
no card on file — expires ~2027-09-18**. Never edit DNS in the Porkbun dashboard, never accept Vercel's
"use our nameservers" offer (it would take the `api` record away from Terraform).

## Decision log

Why the current setup is the way it is — one line each: *decision · instead of · why*.

| Decision | Instead of | Why |
|---|---|---|
| Meta-repo + submodules | single monorepo | backend/frontend/infra version and deploy independently |
| Plain Symfony controllers | API Platform | its resource=entity shortcut fights the planned DDD layering |
| FrankenPHP, hand-rolled Dockerfile | `dunglas/symfony-docker` starter | avoid pre-wired Xdebug/devcontainer tooling |
| Multi-stage `base→dev→prod` in one Dockerfile | separate `Dockerfile.prod` | two files drift |
| npm | pnpm + Turborepo | one JS package |
| phpstan level 8, php-cs-fixer `@Symfony`+`@PER-CS2.0`, PHPUnit; ESLint+Prettier, TS strict, Vitest | — | strictness from day one |
| Vercel Hobby via GitHub integration | GitHub Actions deploy | zero config, previews for free |
| EC2 `t4g.micro`, Ubuntu 24.04 | Lightsail; Amazon Linux 2023 | Lightsail has no path to VPC/ECS; AL2023 lacks a Compose plugin package |
| Neon free tier | RDS, Supabase, Postgres on the VM | data must outlive the Free-plan account; Supabase pauses idle projects |
| Terraform in Docker, S3 state with `use_lockfile` | OpenTofu; DynamoDB lock | docs are Terraform-first; native S3 locking suffices |
| Long-lived keys for IAM user `terraform` | Identity Center / OIDC | simplest thing that works for a single-user account |
| SSH key generated on the laptop | `tls_private_key` in Terraform | private key would sit in state |
| GitHub Actions end-to-end, `ubuntu-24.04-arm` runner | CodePipeline/CodeBuild; OIDC+SSM hybrid | zero AWS resources, no IAM, no console click-through |
| GHCR | ECR | free for public repos; ECR needs an instance role to pull |
| Immutable `sha-` tags, VM runs the pinned sha | `latest` | rollback = re-run older workflow run |
| Secrets in GitHub `production` environment | SSM Parameter Store | no instance role needed; deployment panel for free |
| Dedicated `pinch-deploy` key, host key pinned in `KNOWN_HOSTS` | reuse personal key; `ssh-keyscan` at deploy | personal key never leaves the laptop; no TOFU |
| Neon direct URI | pooler | short-lived connections from one container; migrations want direct |
| Domain bought at Porkbun (`.fyi`, $5.66/yr flat) | Route 53 registration; free DNS names; `.ovh` | Route 53 can't be paid with Free-plan credits and dies with the account; free names are on the PSL so app and API stay cross-site; `.ovh` is closed |
| DNS records in Terraform via `jianyuan/porkbun` | Route 53 zone; dashboard clicks | infra-as-code without an AWS dependency; `cullenmcdermott/porkbun` is archived |
| TLS in the app container's Caddy | separate proxy; Cloudflare | the app already is a Caddy server; one moving part |
| Port 8000 closed, 80/443 only | keep raw-IP fallback | one front door |
| Apex → Vercel, `api.` → EC2, same domain | separate free names | same-site cookies/CORS if a browser ever calls the API |
| Hostname hardcoded in `deploy.yml` | GitHub variable | public, single environment, greppable |
| Domain auto-renew off | card on file | user's choice; calendar reminder instead |
| `next dev --webpack` locally | Turbopack dev | Turbopack's watcher doesn't see changes through the Docker bind mount (tested) |
