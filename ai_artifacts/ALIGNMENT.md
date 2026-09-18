# Pinch — Project Alignment

Captured from the planning session on 2026-09-11. This is the shared understanding before implementation started. Update this file if any decision below changes.

## Repo topology

Four GitHub repos under `github.com/maciej-jedral`, all **public**, **MIT licensed**, linked via **git submodules**:

| Repo | Purpose | Status |
|---|---|---|
| `pinch` | Meta-repo: `../docker-compose.yml`, `install.sh`, shared docs, submodule pointers. No app code. | Phase 1 |
| `pinch-backend` | Symfony backend | Phase 1 |
| `pinch-frontend` | Next.js frontend | Phase 1 |
| `pinch-terraform` | Infrastructure as code (Terraform, run via Docker) | Step 1 live since 2026-09-14 — see *Backend infrastructure* below |

Repo creation: via `gh` CLI, authenticated by the user (`gh auth login`, interactive/device-code — cannot be automated).

## Versions (verified 2026-09-11, superseding earlier stale defaults)

| Component | Version | Notes |
|---|---|---|
| PHP | 8.4 | 8.5 is technically latest (Nov 2025 GA) but 8.4 chosen for ecosystem maturity |
| Symfony | 7.4 LTS | Active support through Nov 2029 |
| PostgreSQL | 18 | 19 still in beta as of this writing |
| Node.js | 24 LTS | Primary active LTS line (Node 26 doesn't become LTS until Oct 2026) |
| Next.js | 16 (16.3.x) | App Router, TypeScript |
| Tailwind CSS | v4 (4.3.x) | |
| Backend runtime | FrankenPHP | Single container, via Caddy; current official Symfony Docker recommendation |

## Local dev architecture (Phase 1 goal: working hello-world)

- **Everything runs via `docker compose up`** — Postgres, backend (FrankenPHP), frontend (`next dev`, file-watch polling enabled). No local PHP/Node/Composer required for a newcomer.
- Backend Dockerfile: minimal, hand-rolled FrankenPHP setup (not the full `dunglas/symfony-docker` starter). **No Xdebug** pre-wired — added later only if needed.
- **Hello world proves full-stack wiring, not just "it boots":**
  - Next.js homepage fetches Symfony's `/api/hello`
  - That endpoint runs a Doctrine DBAL `SELECT 1` against Postgres and reports connectivity
  - One page confirms Next.js → Symfony → Postgres all work end-to-end

## Install script (`pinch/install.sh`)

For a newcomer with only Docker installed:

1. `git submodule update --init --recursive`
2. Copy `.env.example` → `.env` in both `pinch-backend` and `pinch-frontend` (if not present), auto-generating `APP_SECRET`
3. `docker compose build`
4. `docker compose up -d`
5. Print the URLs to hit once healthy

No Adminer/DB-UI service — everyone uses their own tooling (e.g. PhpStorm).

## Tooling (wired in during Phase 1, not deferred)

**Backend (`pinch-backend`)**
- phpstan — level 8 (max strictness from day one)
- php-cs-fixer — `@Symfony` + `@PER-CS2.0` rule sets
- PHPUnit (via `symfony/test-pack`) — one smoke test

**Frontend (`pinch-frontend`)**
- ESLint (`eslint-config-next`) + Prettier (`eslint-config-prettier` to avoid conflicts)
- TypeScript strict mode
- Vitest + React Testing Library — one smoke test

**CI**: GitHub Actions lint+test workflows are **Phase 2**, not Phase 1 — noted so it isn't forgotten, not because it's unimportant.

## Frontend deployment (decided 2026-09-12)

`pinch-frontend` is deployed to Vercel's free **Hobby** plan. Backend deployment is covered by *Backend infrastructure* and *Backend deployment* below.

**Status: live** — since 2026-09-18 at `https://pinchapp.fyi`; 2026-09-12 → 09-18 it was `https://pinch-frontend-eight.vercel.app` (never `pinch.vercel.app`, that's an unrelated third-party site). A push to `main` auto-deploys. Environment/workflow gotchas are in `WORKING_NOTES.md` next to this file.

- **Scope**: frontend only. `page.tsx`'s existing try/catch already falls back to `"Hello from Next.js"` / database `"unreachable"` when `BACKEND_INTERNAL_URL` doesn't resolve (it won't, on Vercel) — this is expected, not a bug, until the backend has a public deployment.
- **Mechanism**: Vercel's native GitHub integration (not GitHub Actions). Importing the repo once wires up: every push to `main` → production deploy, every PR → its own preview deployment. Zero pipeline config, no `vercel.json` needed — plain Next.js app, framework auto-detected.
- **Vercel domain**: `pinchapp.fyi` + `www` (redirect) since 2026-09-18 — see *TLS + domain*. Was Vercel's generated `pinch-frontend-eight.vercel.app` until then; that alias is gone.
- **Environment variables**: `BACKEND_INTERNAL_URL=https://api.pinchapp.fyi`. Changing it needs a redeploy (Vercel bakes env into the deployment).
- **Function region**: `vercel.json` pins `fra1` (decided 2026-09-15) so the server-side fetch to the Frankfurt EC2 box doesn't cross the Atlantic.
- **CI quality gate**: none added. Vercel's own `next build` (which typechecks) is the only gate on deploy; ESLint/Vitest are not run in CI. This stays consistent with the Phase 1 decision to defer GitHub Actions lint/test workflows to Phase 2 — not bolted on piecemeal here.
- **Setup ownership**: connecting a GitHub repo to Vercel requires an interactive OAuth click-through in the browser (installing Vercel's GitHub App), which only the account owner can do — this was walked through manually, not automated.

## Backend infrastructure (decided 2026-09-12, applied 2026-09-14)

Grilling session 2026-09-12; built and verified 2026-09-14. Code lives in `pinch-terraform` (submodule `terraform/`); its `README.md` is the how-to. This section records the *why*.

**Status: live.** `t4g.micro` at Elastic IP `63.182.98.240` (`http://63.182.98.240:8000` once the app is deployed), Neon project `small-bird-75248934` (PG 18.6, Frankfurt). Verified: SSH in, `docker compose version`, `hello-world`, and `psql` from the box to Neon returned `select 1`. The app has been deployed by the pipeline since 2026-09-15 (see *Backend deployment*).

- **Goal**: learn Terraform basics on a real AWS resource, at near-zero cost, in a way that *builds up* to EC2/VPC and later Fargate rather than being thrown away. This ruled out Lightsail (different resource family, no migration path) despite it being simplest.
- **AWS account**: **new, Free plan** (created 2026-09-14). $100 credit + up to $100 earnable, 6-month window. AWS states the Free plan *cannot* charge the card; the account **auto-closes ~2027-03-14** or when credits hit zero, then 90 days grace, then permanent deletion. Never switch it to the Paid plan by accident — that's the only path to a bill. Expected burn ≈ $12/month (instance ~$7 + public IPv4 ~$3.65 + 8 GB gp3 ~$0.80) → ~$70 for the full 6 months.
- **Compute: staged EC2**. Step 1 (done) = one `t4g.micro` (arm64, free-tier-eligible), Ubuntu 24.04 LTS, in the **default VPC**, security group 22+8000 in / all out, Elastic IP, cloud-init installs Docker + Compose from Docker's apt repo. Step 2 (own VPC/SSM/Identity Center) and Step 3 (Fargate) were the original learning ladder — **dropped 2026-09-18**, see *Infra scope* below.
- **OS: Ubuntu 24.04 arm64** over Amazon Linux 2023 — AL2023 has no Compose plugin package (must curl the binary); Ubuntu gets `docker-ce` + `docker-compose-plugin` from Docker's official repo. Ubuntu 26.04 exists but was judged too fresh for Docker's repo.
- **Database: Neon free tier**, Terraform-managed (`kislerdm/neon` provider, community but Neon-sponsored), region `aws-eu-central-1`, PG 18 (accepted by Neon's API). Chosen over Supabase (projects pause after 7 idle days; provider is alpha) and over RDS/Postgres-on-the-VM because the user wants **the data to outlive the Free-plan account**. Free tier: 0.5 GB, 100 CU-hours/month, scale-to-zero after 5 min (cold start ~0.5 s), 6 h PITR (`history_retention_seconds = 21600` — the provider default of 1 day is rejected on Free). Watch CU-hours the first month: a persistent Doctrine connection could keep the compute awake.
- **Terraform tooling**: Terraform **1.16.2** via the `hashicorp/terraform` Docker image through `./tf` (nothing installed on the host, same rule as the app repos). Terraform over OpenTofu: BUSL is irrelevant to a personal learner and the docs/tutorials are Terraform-first. AWS provider `~> 6.64`, Neon `~> 0.18`, lock file committed.
- **State: S3** bucket `pinch-tfstate-<account-id>` (versioned, SSE, public-access blocked, `prevent_destroy`), created by a separate `bootstrap/` module with local state; root uses `use_lockfile = true` (native S3 locking, no DynamoDB). Bucket name lives in gitignored `backend.hcl`. Known caveat: the bucket dies with the account — migration to the next account is `terraform init -migrate-state`; keep a local copy of the state before ~2027-03.
- **AWS auth**: IAM user `terraform` with the scoped policy in `iam/terraform-user-policy.json` (EC2 `*`, S3 on `pinch-tfstate-*`, Budgets `*`, `sts:GetCallerIdentity`), long-lived keys in `~/.aws/credentials`, mounted read-only into the Terraform container. Root user: MFA, no keys. Identity Center is a Step 2 item.
- **SSH**: dedicated `ed25519` key `~/.ssh/pinch-aws`, public half in tfvars → `aws_key_pair`. Port 22 open to `0.0.0.0/0` (key-only auth; home IP changes). Terraform-generated keys (`tls_private_key`) rejected — private key would sit in state.
- **Cost guard**: `aws_budgets_budget` $15/month **gross** (`include_credit = false`, otherwise it reads $0 on the Free plan), email at 100% actual and 133% forecast (~$20) → `maciej.jedral90@gmail.com`. No confirmation email is involved (that's only for SNS subscribers). Also earns Free-plan "Explore AWS" credit. Instance runs 24/7 — no destroy-between-sessions dance.
- **Backend URL: plain HTTP on the EIP** for now. `page.tsx` fetches server-side so no browser ever sees it; TLS needs a hostname (see next steps).
- **Public repo hygiene**: budget email, Neon org ID, AWS account ID, SSH public key, Neon API key are all in gitignored files (`terraform.tfvars`, `backend.hcl`, `.env`) with committed `.example` twins.

### Next steps (in rough order)

1. ~~Budget email confirmation~~ — not needed: direct email subscribers on a Budget need no confirmation (only SNS topics do). Verified via API 2026-09-14: both notifications `OK`. (What the console shows under *Cost monitors* is Cost Anomaly Detection's default monitor, a different, always-on feature.)
2. ~~Delete the auto-created Neon project~~ — done 2026-09-14 via API; only `small-bird-75248934` remains.
3. **App deploy** — decided 2026-09-15, see *Backend deployment* below (GitHub Actions + GHCR + SSH).
4. **Vercel**: `BACKEND_INTERNAL_URL=http://63.182.98.240:8000` — part of the *Backend deployment* definition of done.
5. ~~**TLS + domain**~~ — decided and **live 2026-09-18**, see *TLS + domain* below.
6. ~~Step 2 infra~~ / ~~Step 3 infra~~ — **dropped 2026-09-18**: the user chose to stop deepening the infra and build the app on Step 1 as-is (see *Infra scope*). Not deferred — dropped; re-open only with a new reason.
7. **Before ~2027-03-14** (not skippable — the Free-plan account auto-closes): back up the S3 state, then rebuild on a fresh account: `tf apply` → new EIP → `BACKEND_HOST` + `KNOWN_HOSTS` in the GitHub `production` environment → re-run the workflow → the Porkbun `api` A record follows the EIP via Terraform. Calendar reminder for ~2027-02. Data (Neon) and DNS (Porkbun) live outside the account and are untouched.

### Infra scope (decided 2026-09-18)

Step 1 (one `t4g.micro` in the default VPC, port 22 key-only, Neon) **is the destination**, not a stage. Steps 2 (own VPC / SSM / Identity Center) and 3 (Fargate) were learning goals, not app prerequisites, and the user doesn't want to spend time on them now. Known consequences, accepted: port 22 open to the world (key-only); 1 GB RAM — a second service (worker, Redis, …) will need a bigger instance; a few seconds of downtime per deploy; **rollback re-deploys old code against the current schema** — write expand/contract migrations, never drop a column in the same release that stops using it.

## Backend deployment (decided 2026-09-15)

Grilling session 2026-09-15 (the open Round 0 from `NEXT_PHASE.md`). This records the *why*; the workflow itself is `pinch-backend/.github/workflows/deploy.yml`, ops how-to in `WORKING_NOTES.md`.

- **Platform: GitHub Actions end-to-end**, chosen over AWS-native (CodePipeline/CodeBuild) and a GitHub-builds/AWS-deploys hybrid (OIDC + SSM). All three cost ≈ $0 on the Free plan (CodePipeline V2 and CodeBuild have always-free tiers; ECR is cents), so cost didn't decide it. Actions won on simplicity: zero AWS resources, no IAM, no manual console click (CodeConnections needs an OAuth click-through; CodeDeploy is reportedly excluded from the Free plan). The IAM/OIDC/SSM lesson is explicitly parked for Step 2 infra, not dropped.
- **Registry: GHCR**, public package `ghcr.io/maciej-jedral/pinch-backend`. Free for a public repo; the VM pulls anonymously. The first push creates the package *private* — a one-time manual visibility flip is part of setup. ECR rejected because it needs an instance IAM role just for pulls.
- **Flow**: PR → `check` job only (php-cs-fixer, phpstan, phpunit against a `postgres:18-alpine` service). Push to `main` → `check` → `build` (arm64 image on GitHub's free `ubuntu-24.04-arm` runner, no QEMU) → `deploy`. Merging to `main` *is* releasing, same as the frontend. `workflow_dispatch` for manual re-runs; **rollback = re-run an older workflow run** (it re-deploys that exact sha, no rebuild).
- **Prod image**: multi-stage `base → dev → prod` in the one `Dockerfile`. Root compose builds `target: dev`; prod = `composer install --no-dev`, `APP_ENV=prod` baked, cache warmed, no Composer binary. Separate `Dockerfile.prod` rejected (two files drift).
- **Tagging**: every build pushes `sha-<short>` (immutable) and `latest` (convenience). The VM runs the pinned sha: the workflow writes `BACKEND_IMAGE_TAG=sha-…` into `/opt/pinch/.env` and `compose.prod.yml` uses `${BACKEND_IMAGE_TAG}`. `cat /opt/pinch/.env` = what's live.
- **Runtime on the VM**: `compose.prod.yml` lives in `pinch-backend` and is `scp`'d to `/opt/pinch/` on every deploy — the VM is a dumb Docker host with no git checkout. Backend service only (DB is Neon): `restart: unless-stopped`, healthcheck on `/api/hello`, json-file logs capped 10 MB × 3, port 8000. Deploy = `pull` → `doctrine:migrations:migrate -n` (no-op until the first entity, but wired now) → `up -d --remove-orphans` → `image prune -f`.
- **Secrets**: GitHub **`production` Environment** (not plain repo secrets — scoped to the deploy job, gives a Deployments panel, optional approval gate later). The workflow rewrites `/opt/pinch/.env` on each deploy: `APP_ENV=prod`, `APP_SECRET` (generated once, canonical copy in the user's password manager), `DATABASE_URL` = Neon **direct** URI (pooler rejected: one container in FrankenPHP classic mode opens short-lived connections; migrations want direct anyway; Doctrine keeps `sslmode=require` and drops the unknown `channel_binding` param), `CORS_ALLOW_ORIGIN` (now `^https://pinchapp\.fyi$`; irrelevant while fetches are server-side, correct the day a browser calls the API), `DEFAULT_URI`. SSM Parameter Store rejected (needs the instance role).
- **Deploy identity**: dedicated `pinch-deploy` ed25519 key; public half via Terraform variable `deploy_ssh_public_key` → cloud-init `ssh_authorized_keys` (this **replaced the instance** — done while the box was empty on purpose); private half is a `production` secret. Personal `pinch-aws` key never leaves the laptop. VM host key **pinned** in a `KNOWN_HOSTS` repo variable (no `ssh-keyscan`-at-deploy TOFU). Logs in as `ubuntu`; a separate deploy Linux user rejected — `docker` group is root-equivalent anyway.
- **Terraform scope**: only the key variable + `/opt/pinch` dir in cloud-init. No IAM, no ECR, no SSM.
- **Smoke test fix** (was tech debt): root compose no longer passes `env_file` to `backend` — Symfony's Dotenv already reads `/app/.env*` via the bind mount, and the injected `APP_ENV=dev` was overriding PHPUnit's forced `test`. `composer test` now runs `doctrine:database:create --env=test --if-not-exists` before PHPUnit, so `pinch_test` exists locally, on fresh installs and in CI with one definition (Postgres init-script rejected: doesn't run on existing volumes, and CI would need it a second way).
- **First deploy** = the pipeline's first `main` run; no hand-deploy rehearsal.

### Definition of done

1. `curl http://63.182.98.240:8000/api/hello` → `{"database":"connected"}`.
2. `BACKEND_INTERNAL_URL` set on Vercel; `https://pinch-frontend-eight.vercel.app` shows *connected*.
3. Push to `pinch-backend/main` redeploys without manual steps; a PR runs checks only.
4. `composer test` green locally and in CI.
5. Rollback exercised once (re-run older run → older sha live → roll forward).
6. Docs updated; `NEXT_PHASE.md` deleted.

## TLS + domain (decided 2026-09-18)

Grilling session 2026-09-18; built and verified the same day. Goal: HTTPS for the API (a blocker the moment a browser calls it directly — Phase 2 auth) and one domain for both halves so cookies/CORS are same-site later.

**Status: live.** `https://pinchapp.fyi` (Vercel) shows *connected* via `https://api.pinchapp.fyi` (Let's Encrypt, auto-renewed by Caddy); `www` and `http://` redirect; `63.182.98.240:8000` is closed. `pinch-frontend-eight.vercel.app` no longer serves the app (Vercel returns `DEPLOYMENT_NOT_FOUND`) — the custom domain is the only frontend URL.

- **Domain: `pinchapp.fyi`**, bought 2026-09-18 at **Porkbun** ($5.66/yr, registration = renewal price, no promo bump; Identity Digital registry). `pinch.fyi` was registry-premium ($16.90/yr renewal) — not worth 3× for the short name; every other `pinch.<tld>` on offer was a first-year promo renewing at $14–31. Bought *outside AWS* on purpose: Route 53 registration can't be paid with Free-plan credits, and anything in the AWS account dies with it in 2027-03. **Auto-renew OFF, no card on file** (user's choice) — Porkbun emails at 60/30/7 days; the user keeps a calendar reminder ~2 weeks before expiry. A lapsed domain takes prod down and can be re-registered by anyone, so that reminder matters.
  - Price research: `.ovh` (~€3.50) is closed to new registrations; `pinch.eu`/`pinch.de` taken; `.top`/`.stream`/`.click` rejected on reputation or price. Free names (DuckDNS, is-a.dev, sslip.io) rejected: they're on the Public Suffix List, so app and API would still be cross-site, and the name wouldn't be ours.
- **DNS: Porkbun nameservers, records in Terraform** via `jianyuan/porkbun` (v0.3.x, actively maintained; `cullenmcdermott/porkbun` is archived — don't use it). Keys from `PORKBUN_API_KEY`/`PORKBUN_SECRET_KEY` in the gitignored `terraform/.env`, same pattern as Neon. Porkbun needs *API Access* toggled per domain in its dashboard. Route 53 hosted zone rejected: it would die with the account and it's the infra learning the user opted out of.
- **Layout**: `pinchapp.fyi` (apex) + `www.pinchapp.fyi` (Vercel 308 → apex) → Vercel; `api.pinchapp.fyi` → EC2 EIP (`A` record built from `aws_eip` output, so it follows an instance rebuild). Vercel's A/CNAME (and possible `_vercel` TXT) targets are copied from the Vercel dashboard when the domain is added, not assumed.
- **TLS terminates in the existing FrankenPHP/Caddy** on the box — no extra proxy, no Cloudflare. `SERVER_NAME="api.pinchapp.fyi, :8000"` (deploy-written `.env`): Caddy auto-issues/renews via Let's Encrypt on the hostname and keeps a plain `:8000` listener *inside* the container for the image's `HEALTHCHECK`. Compose publishes only 80 + 443; security group becomes 22/80/443 — **port 8000 is closed to the world**, no raw-IP fallback. Certs in named volumes `caddy_data`/`caddy_config`; an instance replacement loses them and Caddy re-issues (LE limit 5 identical certs/week — fine). No ACME email (public repo), no HTTP/3 (would need UDP 443), no HSTS yet — revisit when a browser talks to the API.
- **Pipeline**: hostname **hardcoded** in `deploy.yml` next to the existing `CORS_ALLOW_ORIGIN` (public info, one environment): `DEFAULT_URI=https://api.pinchapp.fyi`, `CORS_ALLOW_ORIGIN=^https://pinch\.fyi$`, environment URL and smoke test → `https://api.pinchapp.fyi/api/hello` (smoke test retries a few times — first deploy waits for cert issuance). `BACKEND_HOST` (IP) stays a variable for SSH.
- **Vercel**: custom domains added by the user in the dashboard; `BACKEND_INTERNAL_URL=https://api.pinchapp.fyi`. Local dev untouched (`SERVER_NAME=:8000` default in the Dockerfile).
- **Order followed**: user bought domain + API keys + added Vercel domains → Terraform (provider, 3 records, SG; `pinch-terraform#1`) → backend (`compose.prod.yml`, `deploy.yml`; `pinch-backend#2`) → merge deployed → Vercel redeploy for the new env var → docs.
- **Vercel records**: apex `A 216.198.79.1`, `www CNAME cname.vercel-dns.com` (Vercel's universal target; it also offered handing over the nameservers — declined, the `api` record must stay with Porkbun/Terraform).

### Definition of done — all met 2026-09-18

1. ~~`curl https://api.pinchapp.fyi/api/hello` → `{"database":"connected"}` with a valid Let's Encrypt cert; `http://` redirects to `https://`.~~
2. ~~`http://63.182.98.240:8000` no longer answers (SG closed).~~
3. ~~`https://pinchapp.fyi` serves the frontend showing *connected*; `www.pinchapp.fyi` redirects.~~
4. ~~`./tf plan` clean; DNS records visible in state.~~
5. ~~Docs updated (this file, `WORKING_NOTES.md`, `terraform/README.md`, backend README).~~

## Known tech debt (not deferred decisions — things to revisit and fix)

- ~~`pinch-backend` smoke test is red~~ — fixed 2026-09-15 in the deploy phase (see *Backend deployment* → smoke test fix).
- **`pinch-frontend` uses two different bundlers**: local dev runs `next dev --webpack` (Turbopack's watcher doesn't reliably detect file changes across the Docker bind mount from the host), while the Vercel production build uses Turbopack (Next 16's default — no bind mount involved there, so it works fine). `next.config.ts` has both a `webpack()` override (dev watch polling only, no loaders/transforms) and an empty `turbopack: {}` to make the split explicit. Low risk today since the webpack config doesn't touch actual code transforms, but if a real webpack customization (loader, alias, etc.) is ever added, it must be mirrored into the `turbopack` config too or dev/prod will silently diverge. Revisit once Turbopack's dev-mode file watching over bind mounts improves, or once the project drops Docker-bind-mount dev entirely.

## Explicitly deferred to Phase 2 (do not silently assume answers to these)

- App domain/purpose — what Pinch actually does; whether it has user accounts
- Frontend↔backend auth mechanism (JWT vs sessions vs third-party auth provider)
- Symfony API style: plain Symfony vs API Platform
- The real DDD layered architecture (`Domain/Application/Infrastructure/UI`) — Phase 1 uses a bare controller, no layering yet
- ~~Backend deployment: AWS — Lightsail floated but not committed — Terraform for infra~~ → decided, see *Backend infrastructure*
- ~~`pinch-terraform` repo creation~~ → done 2026-09-14
- CI/CD pipelines: ~~backend deploy~~ → decided, see *Backend deployment*. Still open: **frontend** lint/test workflow as a merge gate (see Frontend deployment note above)

## Rejected/superseded options (recorded so they aren't re-litigated without reason)

- Single true monorepo (one repo, no submodules) — rejected in favor of meta-repo + submodules, since backend/frontend/terraform deploy and version independently
- API Platform for the backend — rejected in favor of plain Symfony, since API Platform's "resource = entity" shortcut fights the planned DDD layering
- pnpm + Turborepo — rejected; only one JS package exists (`pinch-frontend`), so plain npm is sufficient until a second JS package appears
- AWS-native CI/CD (CodePipeline/CodeBuild/CodeDeploy + ECR) and the GitHub→AWS OIDC/SSM hybrid — not chosen for the backend deploy (2026-09-15); see *Backend deployment*. OIDC/SSM may return with Step 2 infra
- Session-cookie auth — deferred alongside the rest of Phase 2's auth decision, JWT is the current leaning but not committed
- Lightsail for the backend — rejected 2026-09-12: no upgrade path to EC2/VPC/Fargate, and on a Free-plan account it burns the same credits as EC2
- Supabase, RDS, Postgres-on-the-VM — rejected in favour of Neon (see *Backend infrastructure*)
- Amazon Linux 2023 — rejected in favour of Ubuntu 24.04 (no Compose plugin package)
- OpenTofu — not chosen; Terraform proper, since tutorials/docs target it and the licence doesn't affect a personal learner
- Terraform-generated SSH key (`tls_private_key`) — rejected; private key would live in state
- Route 53 (registration or hosted zone), Cloudflare (registrar/proxy/DNS), free DNS names (DuckDNS, is-a.dev, sslip.io), a separate reverse-proxy container — all rejected 2026-09-18 for TLS + domain; see that section
- `dunglas/symfony-docker` starter kit as the backend base — declined in favor of a minimal hand-rolled Dockerfile, to avoid pulling in pre-wired Xdebug/Dev Container tooling not currently wanted
