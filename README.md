# pinch

Meta-repo for **Pinch** — Symfony backend, Next.js frontend, Postgres, all wired together with Docker for local development.

- [`pinch-backend`](https://github.com/maciej-jedral/pinch-backend) — Symfony 7.4 (PHP 8.4), via FrankenPHP
- [`pinch-frontend`](https://github.com/maciej-jedral/pinch-frontend) — Next.js 16, TypeScript, Tailwind v4
- [`pinch-terraform`](https://github.com/maciej-jedral/pinch-terraform) — the AWS/Neon/DNS infrastructure as Terraform

**Live**: https://pinchapp.fyi (frontend on Vercel) → https://api.pinchapp.fyi (backend on EC2, TLS by Caddy).

This repo holds no application code of its own — just the submodule pointers to the repos above, the Docker Compose setup, and the install script.

## Getting started

You need [Docker](https://docs.docker.com/get-docker/) and `openssl` (for the one-time secret) on the host. Then:

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
docker compose down -v      # stop AND wipe the database volume
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

- **Dependencies changed** (`composer.json` / `package.json`): `docker compose exec backend composer install` or `docker compose exec frontend npm install`. Dependencies live in your checkout (`backend/vendor`, `frontend/node_modules`, both git-ignored), written there by the containers — so your IDE indexes exactly what runs. Never run Composer/npm on the host against them.
- **Dockerfile changed**: `docker compose build backend` or `docker compose build frontend`, then `docker compose up -d`.
- **Database schema changed** (new Doctrine migration): `docker compose exec backend bin/console doctrine:migrations:migrate`.

## Decisions and state

[`AGENTS.md`](AGENTS.md) is the briefing every AI agent reads first: current state of each repo, a one-line-per-decision log with the rejected alternatives, and what's still open. It's written for agents, but it's also the shortest accurate summary of the project.
