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

`pinch-frontend` is deployed to Vercel's free **Hobby** plan. Backend deployment (AWS/Terraform) is still deferred — see below.

**Status: live and verified 2026-09-12** at `pinch.vercel.app`; a push to `main` was confirmed to auto-deploy. Environment/workflow gotchas are in `WORKING_NOTES.md` next to this file.

- **Scope**: frontend only. `page.tsx`'s existing try/catch already falls back to `"Hello from Next.js"` / database `"unreachable"` when `BACKEND_INTERNAL_URL` doesn't resolve (it won't, on Vercel) — this is expected, not a bug, until the backend has a public deployment.
- **Mechanism**: Vercel's native GitHub integration (not GitHub Actions). Importing the repo once wires up: every push to `main` → production deploy, every PR → its own preview deployment. Zero pipeline config, no `vercel.json` needed — plain Next.js app, framework auto-detected.
- **Vercel project name**: `pinch` (deliberately not `pinch-frontend`, so the default domain is `pinch.vercel.app`).
- **Domain**: default `*.vercel.app` domain — no custom domain for now.
- **Environment variables**: none set. `BACKEND_INTERNAL_URL` stays unset in the Vercel project until a real public backend URL exists.
- **CI quality gate**: none added. Vercel's own `next build` (which typechecks) is the only gate on deploy; ESLint/Vitest are not run in CI. This stays consistent with the Phase 1 decision to defer GitHub Actions lint/test workflows to Phase 2 — not bolted on piecemeal here.
- **Setup ownership**: connecting a GitHub repo to Vercel requires an interactive OAuth click-through in the browser (installing Vercel's GitHub App), which only the account owner can do — this was walked through manually, not automated.

## Backend infrastructure (decided 2026-09-12, applied 2026-09-14)

Grilling session 2026-09-12; built and verified 2026-09-14. Code lives in `pinch-terraform` (submodule `terraform/`); its `README.md` is the how-to. This section records the *why*.

**Status: live.** `t4g.micro` at Elastic IP `63.182.98.240` (`http://63.182.98.240:8000` once the app is deployed), Neon project `small-bird-75248934` (PG 18.6, Frankfurt). Verified: SSH in, `docker compose version`, `hello-world`, and `psql` from the box to Neon returned `select 1`. **Nothing is deployed on the VM yet** — Docker is installed, that's all.

- **Goal**: learn Terraform basics on a real AWS resource, at near-zero cost, in a way that *builds up* to EC2/VPC and later Fargate rather than being thrown away. This ruled out Lightsail (different resource family, no migration path) despite it being simplest.
- **AWS account**: **new, Free plan** (created 2026-09-14). $100 credit + up to $100 earnable, 6-month window. AWS states the Free plan *cannot* charge the card; the account **auto-closes ~2027-03-14** or when credits hit zero, then 90 days grace, then permanent deletion. Never switch it to the Paid plan by accident — that's the only path to a bill. Expected burn ≈ $12/month (instance ~$7 + public IPv4 ~$3.65 + 8 GB gp3 ~$0.80) → ~$70 for the full 6 months.
- **Compute: staged EC2**. Step 1 (done) = one `t4g.micro` (arm64, free-tier-eligible), Ubuntu 24.04 LTS, in the **default VPC**, security group 22+8000 in / all out, Elastic IP, cloud-init installs Docker + Compose from Docker's apt repo. Step 2 = own VPC/subnets/IGW, SSM Session Manager (drop port 22), IAM Identity Center, optionally RDS. Step 3 = ECS/Fargate task from the same image — **pending a check that ECS is on the Free plan's allowed-service list** (not verified yet).
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
3. **App deploy** — grilling started 2026-09-14, questions + facts in `NEXT_PHASE.md`: prod-ready `backend/Dockerfile` (no bind mount, `APP_ENV=prod`), image built for `linux/arm64` and pushed to **GHCR** (free for public repos) by GitHub Actions, a one-service `compose.prod.yml` on the VM (`restart: unless-stopped`, port 8000, `.env` with `DATABASE_URL` = Neon URI + `APP_SECRET`). Deploy = `docker compose pull && up -d` over SSH from Actions. Where `compose.prod.yml` lives (backend repo, leaning yes) is a decision for that step.
4. **Vercel**: set `BACKEND_INTERNAL_URL=http://63.182.98.240:8000` on the `pinch` project once the app answers — the homepage's "unreachable" fallback goes away.
5. **TLS + domain** (deferred from this step on purpose): sslip.io + Caddy auto-TLS is flaky (Let's Encrypt rate limits on shared domains); a real domain (~$10/yr) + Route 53 zone ($0.50/mo credits) + FrankenPHP/Caddy auto-TLS is the clean path. Decide together with whether the same domain fronts Vercel.
6. **Step 2 infra**: own VPC, SSM Session Manager (close port 22), IAM Identity Center; RDS only if credits allow and there's a learning reason.
7. **Step 3 infra**: Fargate — after verifying ECS is on the Free plan.
8. **Before ~2027-03-14**: decide upgrade-to-Paid (~$12/mo) vs. let the account close and rebuild on a fresh one; back up state first.

## Known tech debt (not deferred decisions — things to revisit and fix)

- **`pinch-backend` smoke test is red** (found 2026-09-14, pre-existing): `composer test` in the compose container fails because (1) `APP_ENV=dev` from compose's `env_file` overrides PHPUnit's forced `APP_ENV=test`, and (2) the test env's `dbname_suffix: '_test'` points at a `pinch_test` database that the compose Postgres never creates. Phase 1 claimed "one smoke test" — it doesn't currently pass. Fix planned as part of the deploy phase (see `NEXT_PHASE.md`, Q8).
- **`pinch-frontend` uses two different bundlers**: local dev runs `next dev --webpack` (Turbopack's watcher doesn't reliably detect file changes across the Docker bind mount from the host), while the Vercel production build uses Turbopack (Next 16's default — no bind mount involved there, so it works fine). `next.config.ts` has both a `webpack()` override (dev watch polling only, no loaders/transforms) and an empty `turbopack: {}` to make the split explicit. Low risk today since the webpack config doesn't touch actual code transforms, but if a real webpack customization (loader, alias, etc.) is ever added, it must be mirrored into the `turbopack` config too or dev/prod will silently diverge. Revisit once Turbopack's dev-mode file watching over bind mounts improves, or once the project drops Docker-bind-mount dev entirely.

## Explicitly deferred to Phase 2 (do not silently assume answers to these)

- App domain/purpose — what Pinch actually does; whether it has user accounts
- Frontend↔backend auth mechanism (JWT vs sessions vs third-party auth provider)
- Symfony API style: plain Symfony vs API Platform
- The real DDD layered architecture (`Domain/Application/Infrastructure/UI`) — Phase 1 uses a bare controller, no layering yet
- ~~Backend deployment: AWS — Lightsail floated but not committed — Terraform for infra~~ → decided, see *Backend infrastructure*
- ~~`pinch-terraform` repo creation~~ → done 2026-09-14
- CI/CD pipelines: deploy workflows beyond Vercel's own, and lint/test workflows as merge gates (see Frontend deployment note above); backend deploy pipeline is *Next steps* item 3 under *Backend infrastructure*

## Rejected/superseded options (recorded so they aren't re-litigated without reason)

- Single true monorepo (one repo, no submodules) — rejected in favor of meta-repo + submodules, since backend/frontend/terraform deploy and version independently
- API Platform for the backend — rejected in favor of plain Symfony, since API Platform's "resource = entity" shortcut fights the planned DDD layering
- pnpm + Turborepo — rejected; only one JS package exists (`pinch-frontend`), so plain npm is sufficient until a second JS package appears
- Session-cookie auth — deferred alongside the rest of Phase 2's auth decision, JWT is the current leaning but not committed
- Lightsail for the backend — rejected 2026-09-12: no upgrade path to EC2/VPC/Fargate, and on a Free-plan account it burns the same credits as EC2
- Supabase, RDS, Postgres-on-the-VM — rejected in favour of Neon (see *Backend infrastructure*)
- Amazon Linux 2023 — rejected in favour of Ubuntu 24.04 (no Compose plugin package)
- OpenTofu — not chosen; Terraform proper, since tutorials/docs target it and the licence doesn't affect a personal learner
- Terraform-generated SSH key (`tls_private_key`) — rejected; private key would live in state
- `dunglas/symfony-docker` starter kit as the backend base — declined in favor of a minimal hand-rolled Dockerfile, to avoid pulling in pre-wired Xdebug/Dev Container tooling not currently wanted
