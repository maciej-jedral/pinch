# pinch

Meta-repo for **Pinch** — Symfony backend, Next.js frontend, Postgres, all wired together with Docker for local development.

- [`pinch-backend`](https://github.com/maciej-jedral/pinch-backend) — Symfony 7.4 (PHP 8.4), via FrankenPHP
- [`pinch-frontend`](https://github.com/maciej-jedral/pinch-frontend) — Next.js 16, TypeScript, Tailwind v4
- [`pinch-terraform`](https://github.com/maciej-jedral/pinch-terraform) — the AWS/Neon/DNS infrastructure as Terraform

**Live**: https://pinchapp.fyi (frontend on Vercel) → https://api.pinchapp.fyi (backend on EC2, TLS by Caddy).

This repo holds no application code of its own — just the submodule pointers to the repos above, the Docker Compose setup, and the install script.

## Getting started

You need only [Docker](https://docs.docker.com/get-docker/) installed. Then:

```bash
./install.sh
```

This fetches the `backend`/`frontend` submodules, sets up local env files, builds the images, and starts the stack:

- frontend: http://localhost:3000
- backend: http://localhost:8000/api/hello

## Running it day to day

After the first `./install.sh`, you don't need it again — the images are built and the env files exist. From then on it's plain Docker Compose from the repo root:

```bash
docker compose up -d        # start Postgres, backend and frontend
docker compose logs -f      # follow logs (add a service name to filter, e.g. `logs -f backend`)
docker compose down         # stop; the database keeps its data in a named volume
docker compose down -v      # stop AND wipe the database / vendor / node_modules volumes
```

Same URLs as above: frontend on http://localhost:3000, backend on http://localhost:8000/api/hello. Source directories are bind-mounted into the containers, so edits are picked up live — the frontend hot-reloads (via webpack polling), the backend re-reads PHP on each request.

Nothing needs PHP, Composer, Node or npm on the host. Run all tooling inside the containers:

```bash
# backend
docker compose exec backend composer test        # PHPUnit (creates the test DB itself)
docker compose exec backend composer stan        # phpstan
docker compose exec backend composer cs-check    # php-cs-fixer (cs-fix to apply)
docker compose exec backend bin/console <cmd>    # any Symfony console command

# frontend
docker compose exec frontend npm test            # Vitest
docker compose exec frontend npm run lint
docker compose exec frontend npm run typecheck
docker compose exec frontend npm run format
```

When you need to rebuild:

- **Dependencies changed** (`composer.json` / `package.json`): `docker compose build backend` or `docker compose build frontend`, then `docker compose up -d`. Dependencies live in named volumes (`backend_vendor`, `frontend_node_modules`), not in your checkout.
- **Database schema changed** (new Doctrine migration): `docker compose exec backend bin/console doctrine:migrations:migrate`.

## Plan

See [`ai_artifacts/ALIGNMENT.md`](ai_artifacts/ALIGNMENT.md) for the full project plan — what's decided, what's deliberately deferred to Phase 2 (app purpose, auth, API style), and why.
