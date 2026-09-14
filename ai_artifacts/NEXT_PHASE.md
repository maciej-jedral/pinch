# Next phase: deploy the backend to the EC2 box

Handoff written 2026-09-14 at the end of the infra Step 1 session. A grilling round
(`/mattpocock-skills:grilling`) was **started but not answered** — the user wants to continue it in a
fresh session. Start by re-reading `ALIGNMENT.md` (→ *Backend infrastructure*) and `WORKING_NOTES.md`,
then re-present the questions below (re-verify facts marked ⚠ first — they can go stale).

## Goal of the phase

`pinch.vercel.app` shows `database: connected` from the real backend, and every push to
`pinch-backend/main` redeploys it. Concretely:

1. production-grade image build (`target: prod`),
2. pushed to GHCR,
3. one-service Compose file on the VM under `/opt/pinch`, secrets in a `.env` there,
4. GitHub Actions: check → build+push → ssh → `compose pull && up -d` (+ migrations),
5. `BACKEND_INTERNAL_URL=http://63.182.98.240:8000` on the Vercel `pinch` project.

Terraform changes only if a separate deploy key is added to the VM (see Q7).

## Facts already established (don't re-ask the user)

- **Current `backend/Dockerfile`** is single-stage `dunglas/frankenphp:php8.4`: installs dev deps,
  bakes Composer, no `APP_ENV=prod`, no cache warm-up. Dev works because compose bind-mounts `./backend:/app`
  over it. Not a prod image. `.dockerignore` excludes `var/ vendor/ .git/ .idea/`.
- **Caddyfile**: `{$SERVER_NAME}` → `root * public`, `encode gzip`, `php_server` (classic mode, no worker mode).
  `ENV SERVER_NAME=:8000` in the Dockerfile.
- **Prod env needed**: `APP_ENV=prod`, `APP_SECRET`, `DATABASE_URL`, optionally `CORS_ALLOW_ORIGIN`
  (defaults to localhost regex in `.env`), `DEFAULT_URI`. `.env.dev` commits a dev `APP_SECRET` — fine.
  `config/packages/doctrine.yaml` has `server_version: '18'` and a `when@prod` cache-pool block already.
- **Neon URI**: `cd terraform && ./tf output -raw neon_connection_uri | tr -d '\r'` — Neon's URI carries
  `?sslmode=require&channel_binding=require`; Doctrine wants `serverVersion=18&charset=utf8` appended
  (or rely on `server_version` in yaml). Direct endpoint vs pooler (`connection_uri_pooler`) is undecided.
- **`migrations/` is empty, no entities** — nothing to migrate yet, but pipeline shape is decided now.
- **Frontend**: `src/lib/hello.ts` reads `BACKEND_INTERNAL_URL` server-side with `cache: "no-store"`;
  `src/app/page.tsx` falls back to "unreachable". Plain HTTP on the EIP works with **zero frontend code
  change**. No `vercel.json` → Vercel functions run in `iad1` (US East); `fra1` would match EC2 + Neon.
- **No CI in `pinch-backend`** (no `.github/`). Repo is public → GHCR is free; Actions pushes with
  `GITHUB_TOKEN` (`packages: write`). ⚠ **First GHCR push creates the package as *private*** even for a public
  repo — needs one manual visibility flip (GitHub → package → settings) or a pull token on the VM.
- ⚠ GitHub provides **free native arm64 hosted runners for public repos** (`runs-on: ubuntu-24.04-arm`) —
  avoids QEMU for the t4g (arm64) image. Verify still true.
- The local `gh` token lacks `read:packages`; irrelevant for Actions, matters only if the session
  wants to inspect GHCR from the CLI.
- **The backend smoke test is RED today** (pre-existing, discovered 2026-09-14):
  `docker compose exec backend composer test` →
  1. `LogicException: framework.test config is not set` — `APP_ENV=dev` from compose `env_file` wins
     over PHPUnit's `<server name="APP_ENV" value="test" force="true">`;
  2. with `APP_ENV=test` forced: `FATAL: database "pinch_test" does not exist` — `doctrine.yaml` adds
     `dbname_suffix: '_test'` in test env, and the compose Postgres only creates `pinch`.
  Any CI test gate needs a Postgres service + `bin/console doctrine:database:create --env=test`
  (or an init SQL creating `pinch_test`); the local run needs the same DB created. Logged as tech
  debt in `ALIGNMENT.md`.
- Local stack was left running (`docker compose up -d` in `pinch/`) at session end.

## Round 1 questions (asked, NOT yet answered) — with the recommendations given

| # | Decision | Options | Recommended |
|---|---|---|---|
| Q1 | Prod image | (a) multi-stage `base→dev→prod` in the existing Dockerfile, compose `target: dev`; (b) separate `Dockerfile.prod`; (c) run current image with prod env | **(a)** — `--no-dev`, `APP_ENV=prod` baked, cache warmed, no Composer in final image |
| Q2 | Where built | (a) Actions on `ubuntu-24.04-arm`, arm64-only; (b) QEMU multi-arch; (c) build on the VM | **(a)** |
| Q3 | GHCR visibility | (a) flip package public once, VM pulls anonymously; (b) private + PAT on VM | **(a)** |
| Q4 | Tagging | (a) `sha-<short>` + `latest`, VM runs `latest`; (b) VM `.env` pins `BACKEND_IMAGE_TAG=sha-…` written by the pipeline, `latest` only as convenience | **(b)** |
| Q5 | `compose.prod.yml` home | (a) `pinch-backend`, `scp`'d on deploy, VM has no git checkout; (b) `pinch-terraform` via cloud-init; (c) git clone on VM | **(a)** — VM stays a dumb Docker host (`/opt/pinch/{compose.yml,.env}`) |
| Q6 | Secrets on VM | (a) GitHub Actions secrets → workflow writes `/opt/pinch/.env` each deploy; (b) hand-written once over SSH; (c) SSM Parameter Store (needs Step 2 instance role) | **(a)**; SSM later |
| Q7 | Deploy SSH identity | (a) dedicated `pinch-deploy` ed25519 key, public half via new Terraform var → cloud-init `ssh_authorized_keys` (**replaces the instance** — harmless now), private half as GitHub secret; (b) reuse personal `pinch-aws` key | **(a)** — last free moment to replace the instance |
| Q8 | Trigger + gates | (a) push `main` → check (cs-fixer, phpstan, phpunit w/ Postgres service) → build+push → deploy, `workflow_dispatch` too, PRs run check only — **requires fixing the red smoke test in this phase**; (b) gates without phpunit until test fixed; (c) no gates | **(a)** — ALIGNMENT deferred lint/test CI to "land with the first pipeline"; this is it |
| Q9 | Migrations on deploy | (a) `doctrine:migrations:migrate --no-interaction` via `compose run --rm` before `up -d`; (b) manual until an entity exists | **(a)** |
| Q10 | Vercel region | (a) `vercel.json` `{"regions":["fra1"]}` in `pinch-frontend`; (b) leave `iad1` | **(a)** |

## Round 2 (planned, depends on Round 1)

- Exact prod `DATABASE_URL`: Neon direct vs pooler endpoint; `serverVersion`/`charset` params.
- `CORS_ALLOW_ORIGIN` value (`^https://pinch\.vercel\.app$`? — not strictly needed for server-side fetch).
- Compose service details: `restart: unless-stopped`, healthcheck on `/api/hello`, json-file log rotation, port `8000:8000`.
- GitHub repo secrets vs a `production` Environment (with its own secrets, optional approval).
- How `APP_SECRET` for prod is generated and where it's recorded.
- Whether `install.sh` / root `docker-compose.yml` need `target: dev` (yes if Q1=a) and the `pinch_test` DB init.
- Definition of done: `curl http://63.182.98.240:8000/api/hello` → `connected`; `pinch.vercel.app` shows it;
  a push to `main` redeploys end-to-end; rollback by re-running an older workflow; docs updated
  (ALIGNMENT next-steps, WORKING_NOTES, backend README, this file deleted or rewritten for the phase after).

## Out of scope for this phase (already decided)

TLS + domain (own step after this); Step 2 infra (own VPC, SSM, Identity Center, RDS); Fargate.
