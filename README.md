# pinch

Meta-repo for **Pinch** — Symfony backend, Next.js frontend, Postgres, all wired together with Docker for local development.

- [`pinch-backend`](https://github.com/maciej-jedral/pinch-backend) — Symfony 7.4 (PHP 8.4), via FrankenPHP
- [`pinch-frontend`](https://github.com/maciej-jedral/pinch-frontend) — Next.js 16, TypeScript, Tailwind v4

This repo holds no application code of its own — just the submodule pointers to the two repos above, the Docker Compose setup, and the install script.

## Getting started

You need only [Docker](https://docs.docker.com/get-docker/) installed. Then:

```bash
./install.sh
```

This fetches the `backend`/`frontend` submodules, sets up local env files, builds the images, and starts the stack:

- frontend: http://localhost:3000
- backend: http://localhost:8000/api/hello

## Plan

See [`ai_artifacts/ALIGNMENT.md`](ai_artifacts/ALIGNMENT.md) for the full project plan — what's decided, what's deliberately deferred to Phase 2 (domain, auth, API style, deployment/Terraform), and why.
