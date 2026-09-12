# Pinch — Project Alignment

Captured from the planning session on 2026-09-11. This is the shared understanding before implementation started. Update this file if any decision below changes.

## Repo topology

Four GitHub repos under `github.com/maciej-jedral`, all **public**, **MIT licensed**, linked via **git submodules**:

| Repo | Purpose | Status |
|---|---|---|
| `pinch` | Meta-repo: `../docker-compose.yml`, `install.sh`, shared docs, submodule pointers. No app code. | Phase 1 |
| `pinch-backend` | Symfony backend | Phase 1 |
| `pinch-frontend` | Next.js frontend | Phase 1 |
| `pinch-terraform` | Infrastructure as code | **Deferred to Phase 2** — repo not created yet |

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

## Known tech debt (not deferred decisions — things to revisit and fix)

- **`pinch-frontend` uses two different bundlers**: local dev runs `next dev --webpack` (Turbopack's watcher doesn't reliably detect file changes across the Docker bind mount from the host), while the Vercel production build uses Turbopack (Next 16's default — no bind mount involved there, so it works fine). `next.config.ts` has both a `webpack()` override (dev watch polling only, no loaders/transforms) and an empty `turbopack: {}` to make the split explicit. Low risk today since the webpack config doesn't touch actual code transforms, but if a real webpack customization (loader, alias, etc.) is ever added, it must be mirrored into the `turbopack` config too or dev/prod will silently diverge. Revisit once Turbopack's dev-mode file watching over bind mounts improves, or once the project drops Docker-bind-mount dev entirely.

## Explicitly deferred to Phase 2 (do not silently assume answers to these)

- App domain/purpose — what Pinch actually does; whether it has user accounts
- Frontend↔backend auth mechanism (JWT vs sessions vs third-party auth provider)
- Symfony API style: plain Symfony vs API Platform
- The real DDD layered architecture (`Domain/Application/Infrastructure/UI`) — Phase 1 uses a bare controller, no layering yet
- Backend deployment: AWS — Lightsail floated but not committed — Terraform for infra
- `pinch-terraform` repo creation
- CI/CD pipelines: deploy workflows beyond Vercel's own, and lint/test workflows as merge gates (see Frontend deployment note above)

## Rejected/superseded options (recorded so they aren't re-litigated without reason)

- Single true monorepo (one repo, no submodules) — rejected in favor of meta-repo + submodules, since backend/frontend/terraform deploy and version independently
- API Platform for the backend — rejected in favor of plain Symfony, since API Platform's "resource = entity" shortcut fights the planned DDD layering
- pnpm + Turborepo — rejected; only one JS package exists (`pinch-frontend`), so plain npm is sufficient until a second JS package appears
- Session-cookie auth — deferred alongside the rest of Phase 2's auth decision, JWT is the current leaning but not committed
- `dunglas/symfony-docker` starter kit as the backend base — declined in favor of a minimal hand-rolled Dockerfile, to avoid pulling in pre-wired Xdebug/Dev Container tooling not currently wanted
