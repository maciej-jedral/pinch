#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for tool in docker openssl; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "==> '$tool' is required on the host but was not found" >&2
    exit 1
  fi
done

echo "==> Fetching backend/frontend submodules"
git submodule update --init --recursive

# .env.dev.local: Symfony loads .env.dev *after* .env.local, and the committed
# backend/.env.dev sets its own APP_SECRET, so a plain .env.local would be overridden.
if [ ! -f backend/.env.dev.local ]; then
  echo "==> Generating backend/.env.dev.local (APP_SECRET)"
  app_secret=$(openssl rand -hex 16)
  printf 'APP_SECRET=%s\n' "$app_secret" > backend/.env.dev.local
else
  echo "==> backend/.env.dev.local already exists, leaving it alone"
fi

if [ ! -f frontend/.env.local ]; then
  echo "==> Creating frontend/.env.local from .env.example"
  cp frontend/.env.example frontend/.env.local
else
  echo "==> frontend/.env.local already exists, leaving it alone"
fi

echo "==> Building images"
docker compose build

# Dependencies are installed into the bind-mounted checkout (backend/vendor,
# frontend/node_modules) so the IDE on the host sees exactly what the containers run.
echo "==> Installing backend dependencies (composer install)"
docker compose run --rm --no-deps backend composer install --no-interaction

echo "==> Installing frontend dependencies (npm ci)"
docker compose run --rm --no-deps frontend npm ci

echo "==> Starting the stack"
docker compose up -d

echo "==> Waiting for the backend to become healthy"
backend_ready=false
for _ in $(seq 1 30); do
  if docker compose exec -T backend curl -sf http://localhost:8000/api/hello > /dev/null 2>&1; then
    backend_ready=true
    break
  fi
  sleep 2
done

if [ "$backend_ready" != "true" ]; then
  echo "==> Backend didn't respond within 60s - check 'docker compose logs backend'" >&2
  exit 1
fi

cat <<'EOF'

Pinch is up:

  frontend  -> http://localhost:3000
  backend   -> http://localhost:8000/api/hello

Run "docker compose logs -f" to follow logs, "docker compose down" to stop.
EOF
