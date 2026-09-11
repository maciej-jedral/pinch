#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> Fetching backend/frontend submodules"
git submodule update --init --recursive

if [ ! -f backend/.env.local ]; then
  echo "==> Generating backend/.env.local (APP_SECRET)"
  app_secret=$(openssl rand -hex 16)
  printf 'APP_SECRET=%s\n' "$app_secret" > backend/.env.local
else
  echo "==> backend/.env.local already exists, leaving it alone"
fi

if [ ! -f frontend/.env.local ]; then
  echo "==> Creating frontend/.env.local from .env.example"
  cp frontend/.env.example frontend/.env.local
else
  echo "==> frontend/.env.local already exists, leaving it alone"
fi

echo "==> Building images"
docker compose build

echo "==> Starting the stack"
docker compose up -d

echo "==> Waiting for the backend to become healthy"
backend_ready=false
for _ in $(seq 1 30); do
  if curl -sf http://localhost:8000/api/hello > /dev/null 2>&1; then
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
