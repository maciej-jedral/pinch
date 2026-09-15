# Pinch — Working Notes for AI sessions

Environment facts and workflow gotchas learned in practice. Not decisions (those live in
`ALIGNMENT.md`) — this is "how to actually get things done on this machine without tripping".
Last updated 2026-09-15.

## Current state (as of 2026-09-15)

- Phase 1 complete: `docker compose up` runs Postgres + Symfony (FrankenPHP) + Next.js locally,
  homepage fetches `/api/hello` end-to-end. `./install.sh` verified from a fresh clone.
- Frontend is **live on Vercel** at `https://pinch-frontend-eight.vercel.app` (Hobby plan).
  **Not** `pinch.vercel.app` — that's an unrelated third-party site; earlier notes had it wrong.
  Push to `main` on `pinch-frontend` → auto production deploy. PRs get preview URLs. Functions pinned to `fra1`.
- Backend infra **Step 1 is live** (2026-09-14): EC2 `t4g.micro` at `63.182.98.240`, Neon Postgres,
  Budgets alert, S3 state. Decisions in `ALIGNMENT.md` → *Backend infrastructure*; how-to in `terraform/README.md`.
- Backend **deploy pipeline is live** (2026-09-15): push to `pinch-backend/main` → GitHub Actions
  check → build (GHCR) → SSH deploy to the box. Decisions in `ALIGNMENT.md` → *Backend deployment*;
  ops how-to in the section below.
- Four repos. `terraform/` is a submodule with **no standalone clone** (deliberately — see below).
- Next: TLS + domain (needs its own grilling), then Step 2 infra. See ALIGNMENT next steps.

## Two clones of each app repo exist on disk — this WILL bite you

```
/home/maciej/projects/pinch/frontend    <- git submodule checkout. THIS is what Docker bind-mounts.
/home/maciej/projects/pinch-frontend    <- separate standalone clone of the same GitHub repo.
/home/maciej/projects/pinch/backend     <- git submodule checkout. THIS is what Docker bind-mounts.
/home/maciej/projects/pinch-backend     <- separate standalone clone of the same GitHub repo.
```

- Editing the standalone clone does **nothing** to the running containers. Edit the submodule copy.
- The user edits via PhpStorm/browser against the running stack, so their uncommitted changes
  appear in the **submodule** copies (`pinch/frontend`, `pinch/backend`). Check there first.
- After pushing from a submodule, `git pull` in the standalone clone to keep them identical,
  otherwise the next session finds a confusing "modified but identical" diff.
- Consider deleting the standalone clones in a future session to remove the footgun — ask first.
- `pinch/terraform` has **no** standalone twin. Edit and commit it in place; step 3 below doesn't apply.

## Submodule change workflow (do all three steps every time)

1. In `pinch/frontend` (or `pinch/backend`): `git add … && git commit && git push`
2. In `pinch`: `git add frontend && git commit -m "Bump frontend submodule (...)" && git push`
3. In `pinch-frontend` standalone: `git pull`

Skipping step 2 leaves the meta-repo pointing at a stale commit; `install.sh` for a newcomer
then checks out old code.

## Git identity

- **No global git identity** on this machine, and it must not be set globally (user instruction).
- Each repo/checkout has **local** `user.name "Maciej Jedral"` / `user.email maciej.jedral90@gmail.com`.
  Already set in: `pinch`, `pinch-frontend`, `pinch-backend`, `pinch/frontend`, `pinch/backend`, `pinch/terraform`.
- A fresh submodule checkout (e.g. after re-clone) will fail with "Author identity unknown" —
  set it locally again, never `--global`.
- Commits end with the `Co-Authored-By` + `Claude-Session` trailers.

## AWS / Terraform (added 2026-09-14)

- **Everything goes through `terraform/tf`** (Terraform 1.16.2 in Docker). `./tf -chdir=bootstrap …`
  for the state-bucket module. No `terraform`/`aws` binaries on the host. For ad-hoc AWS CLI calls:
  `docker run --rm -v ~/.aws:/root/.aws:ro -e AWS_REGION=eu-central-1 public.ecr.aws/aws-cli/aws-cli:latest <cmd>`.
- Creds: `~/.aws/credentials` (IAM user `terraform`, `[default]` profile), region in `~/.aws/config`.
  Neon API key in `terraform/.env`. All gitignored — never print them; mask account ids in output
  (`sed -E 's/[0-9]{12}/<account-id>/g'`) since the repos are public.
- Local-only files in `terraform/`: `terraform.tfvars`, `backend.hcl`, `.env`, `bootstrap/terraform.tfstate`.
  If any is missing, recreate from the `.example` twin; bucket name = `./tf -chdir=bootstrap output -raw state_bucket_name`.
- SSH: `ssh -i ~/.ssh/pinch-aws ubuntu@$(cd terraform && ./tf output -raw backend_public_ip)`.
  Right after first boot, `sudo cloud-init status --wait` before touching Docker. A session opened
  *before* cloud-init finished won't have the `docker` group — reconnect.
- `./tf output` values contain `\r` when captured from the Docker TTY — pipe through `tr -d '\r'`.
- Changing `cloud-init.yaml.tftpl` (or `deploy_ssh_public_key`) makes Terraform **replace the instance**
  (`user_data_replace_on_change = true` — without it the provider would update in place and cloud-init
  would silently *not* re-run). EIP survives, the app doesn't: afterwards update `KNOWN_HOSTS` in the
  GitHub `production` environment and re-run the latest `pinch-backend` workflow. Also run
  `ssh-keygen -R 63.182.98.240` locally.
- The auto-mode classifier refuses `./tf apply -auto-approve` ("blind apply"). Use
  `./tf plan -out=x.tfplan` then `./tf apply x.tfplan` (`*.tfplan` is gitignored).
- AWS account is **Free plan** (new 2026-09-14): cannot bill the card, closes ~2027-03-14 or when the
  ~$100–200 credits run out. Don't upgrade it to Paid. Budget alert tracks gross usage.
- Neon: org `org-crimson-haze-69015012`, Terraform project `small-bird-75248934` (PG 18, Frankfurt).
  (Onboarding had auto-created `tiny-boat-47874989`; deleted via API 2026-09-14.)
  Org id / projects are queryable: `curl -H "Authorization: Bearer $NEON_API_KEY" https://console.neon.tech/api/v2/users/me/organizations`.
- Budgets API lives in `us-east-1` only: `-e AWS_REGION=us-east-1 … budgets describe-budget --account-id <id> --budget-name pinch-monthly`.
- Neon's console pushes `npm i -g neon`, `neon link`, `neon deploy`, MCP setup etc. — ignore all of it;
  Terraform talks to the API directly.
- The Claude Code auto-mode classifier **refuses to create public GitHub repos** (`gh repo create --public`).
  The user runs that one command via `! gh repo create …`; everything after (push, submodule add) is fine.

## Backend deploy ops (added 2026-09-15)

- **Where things are**: workflow `pinch-backend/.github/workflows/deploy.yml`; on the VM `/opt/pinch/{compose.yml,.env}`
  (both rewritten on every deploy — edits there don't survive). Image `ghcr.io/maciej-jedral/pinch-backend:sha-<full commit sha>`.
- **What's live**: `ssh -i ~/.ssh/pinch-aws ubuntu@63.182.98.240 'grep BACKEND_IMAGE_TAG /opt/pinch/.env; docker compose -f /opt/pinch/compose.yml ps'`.
- **Logs**: `… 'docker compose -f /opt/pinch/compose.yml logs --tail 100 -f'`.
- **Redeploy / rollback**: `gh run list --repo maciej-jedral/pinch-backend`, then `gh run rerun <id> --repo …`
  (or Actions UI → *Re-run all jobs*). Re-running an older run deploys that commit's sha. Only `main` may
  deploy to the `production` environment (deployment-branch policy).
- **Secrets/variables** (GitHub `production` environment, all set via `gh secret set … --env production`):
  `APP_SECRET`, `DATABASE_URL` (Neon direct URI, `postgres://…/neondb?sslmode=require` — Doctrine accepts the
  `postgres` scheme), `DEPLOY_SSH_KEY` (private half of `~/.ssh/pinch-deploy`); variables `BACKEND_HOST`,
  `KNOWN_HOSTS` (`ssh-keyscan -t ed25519 63.182.98.240`). `CORS_ALLOW_ORIGIN` and `DEFAULT_URI` are hardcoded in the workflow.
  The canonical `APP_SECRET` copy is in the user's password manager; GitHub never shows it again.
- **Rotate the deploy key**: `ssh-keygen -t ed25519 -f ~/.ssh/pinch-deploy` → new pub into `terraform.tfvars`
  → `./tf plan/apply` (replaces the instance, see AWS section) → `gh secret set DEPLOY_SSH_KEY --env production < ~/.ssh/pinch-deploy`
  → update `KNOWN_HOSTS` → re-run the workflow.
- **GHCR**: the deploy job logs in with the ephemeral job token before `pull` and logs out after, so it works
  even while the package is private. Flip the package public (GitHub → Packages → pinch-backend → settings)
  if you want anonymous `docker pull` from anywhere.
- **Migrations** run on every deploy (`--allow-no-migration` while `migrations/` is empty). The build stage
  runs `composer dump-env prod`, so the image carries a compiled `.env.local.php`; real env vars still win.
- **Test DB**: `composer test` = `doctrine:database:create --env=test --if-not-exists` + phpunit. The root
  compose no longer passes `env_file` to `backend` (Symfony reads `/app/.env*` itself); the container has no
  `APP_ENV` env var, which is what lets phpunit force `test`.

## Docker on this machine

- Docker Desktop for Linux (QEMU VM). If `docker` says it can't connect to the socket:
  `systemctl --user start docker-desktop`, then poll `docker version` for ~5–10s.
- Only `/home/...` is shared into the VM. Bind mounts from `/tmp/...` fail with "mounts denied"
  — run any from-scratch clone tests under `/home/maciej/projects/`.
- **No `npm`, `node`, `php`, or `composer` on the host.** Run everything through the containers:
  - `docker compose exec frontend npm run build|lint|test|typecheck`
  - `docker compose exec backend composer stan|cs-check|test`
- Containers: `pinch-database-1`, `pinch-backend-1`, `pinch-frontend-1`. Ports 8000 (backend), 3000 (frontend).
- Docker Desktop goes to sleep between sessions; the `systemctl --user start docker-desktop` dance was needed twice in one day.
- The frontend dev server auto-restarts when `next.config.ts` changes; source edits hot-reload
  within ~6s via webpack polling (see bundler note below).

## Next.js 16 gotchas

- `pinch/frontend/AGENTS.md` (auto-generated by `next dev`) says: this Next version differs from
  training data — read `node_modules/next/dist/docs/` before writing Next code. Do that via
  `docker compose exec frontend cat node_modules/next/dist/docs/<path>`.
- Dev = webpack (`next dev --webpack`), prod build = Turbopack (default). Both configured in
  `next.config.ts`; the empty `turbopack: {}` is load-bearing — removing it breaks the Vercel build.
  Recorded as tech debt in `ALIGNMENT.md`.
- Turbopack's file watcher does not see changes through the Docker bind mount, even with
  `watchOptions.pollIntervalMs` set — that was tested and failed. Don't re-try it without a new Next version.

## Vercel

- Vercel project ← GitHub `maciej-jedral/pinch-frontend`, root dir `./`, framework auto-detected. Domain
  `pinch-frontend-eight.vercel.app`.
- `vercel.json` pins `regions: ["fra1"]`. No GitHub Actions. Deploy trigger is Vercel's GitHub App.
- Env var `BACKEND_INTERNAL_URL=http://63.182.98.240:8000` (set 2026-09-15 by the user in the dashboard).
- Anything needing the Vercel dashboard/OAuth must be done by the user; give them steps.

## User preferences observed

- Wants the grilling-style interview (`/mattpocock-skills:grilling`) before non-trivial work,
  then confirms before implementation starts.
- Defers eagerly: "later", "Phase 2" — respect that, don't sneak deferred work in.
- Doesn't want workarounds for problems they've already removed (e.g. reverted a hydration
  warning suppression once they uninstalled the offending browser extension).
- Uses PhpStorm; no DB admin UI in the stack.
