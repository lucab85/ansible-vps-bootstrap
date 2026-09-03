# App stack: n8n + Medusa backend + monitoring

Deployed on top of the `ansible-vps-bootstrap` base. Not run by the Ansible
playbook — deployed over SSH, directly on the VPS under `/opt/apps`. This
directory is the version-controlled mirror of the infra config that's
actually deployed; it does **not** contain application source code (see
"Where the code lives" below).

## Domains

| Service                          | Domain                            | Hosted on |
|-----------------------------------|-------------------------------------|-----------|
| n8n                                | `n8n.openempower.com`              | VPS |
| Medusa backend/admin (techmeout)   | `admin.techmeout.it`               | VPS |
| Medusa storefront (techmeout)      | `shop.techmeout.it`                | Vercel |
| Grafana                            | `monitor.openempower.com`          | VPS |
| Medusa backend (puntofeste)        | `admin-puntofeste.techmeout.it`    | VPS |
| Medusa storefront (puntofeste)     | `puntofeste.techmeout.it`          | Vercel |
| Medusa backend (smoothclothingbrand) | `admin-smoothclothingbrand.techmeout.it` | VPS |
| Medusa storefront (smoothclothingbrand) | `smoothclothingbrand.techmeout.it` | Vercel |

`puntofeste`/`smoothclothingbrand` are on **dev-phase URLs** (subdomains of
`techmeout.it`, both backend and storefront) rather than their real brand
domains (`shop.puntofeste.com`, `shop.smoothclothingbrand.com`) — deliberate,
per the user: prove the setup works here first, move to the final domains
once it's ready.

DNS A records must point at the VPS IP for every VPS-hosted domain above
before Caddy can issue Let's Encrypt certificates — it retries automatically
once they resolve, but if it already exhausted its retry attempts it backs
off for up to 2 hours; `docker exec apps-caddy-1 caddy reload --config
/etc/caddy/Caddyfile` (after editing the Caddyfile) or `docker restart
apps-caddy-1` forces an immediate retry instead of waiting. The Vercel-hosted
storefronts also can't get a working production deploy until their backend's
DNS resolves — Next.js prerenders product pages at build time by fetching
from `NEXT_PUBLIC_MEDUSA_BACKEND_URL`, which fails outright if that host
doesn't resolve yet.

## Where the code lives

- **techmeout (production-style deploy)**:
  - Backend (Medusa v2 API + Admin): [`techmeout-it/backend`](https://github.com/techmeout-it/backend).
    GitHub Actions (`.github/workflows/deploy.yml` in that repo) rsyncs it to
    `/opt/apps/medusa` on the VPS and rebuilds on every push to `main`, using
    a dedicated SSH deploy key (not the personal one used for manual access)
    stored as repo secrets (`VPS_SSH_KEY`, `VPS_HOST`, `VPS_USER`). Built with
    a production Dockerfile (`npm run build` → `.medusa/server` → `medusa
    start`).
  - Storefront (Next.js): [`techmeout-it/frontend`](https://github.com/techmeout-it/frontend),
    deployed on Vercel (project `openempower/techmeout-storefront`),
    connected to the GitHub repo for auto-deploy on push. Not on the VPS at
    all.
- **puntofeste and smoothclothingbrand (experimentation, dev-mode)** — see
  "Multi-tenant stores" below for the full rationale:
  - Backends: [`techmeout-it/puntofeste-backend`](https://github.com/techmeout-it/puntofeste-backend),
    [`techmeout-it/smoothclothingbrand-backend`](https://github.com/techmeout-it/smoothclothingbrand-backend).
    Run directly on the VPS via `medusa develop` (no build step, no CI/CD,
    no Dockerfile — plain `node:20` image bind-mounting the repo directory).
  - Storefronts: [`techmeout-it/puntofeste-frontend`](https://github.com/techmeout-it/puntofeste-frontend),
    [`techmeout-it/smoothclothingbrand-frontend`](https://github.com/techmeout-it/smoothclothingbrand-frontend),
    each on their own Vercel project, same pattern as techmeout's storefront.
- **This repo's `compose/`** only owns the infra layer: Postgres, Redis,
  Caddy, n8n, how the `techmeout` backend image gets built, the dev-mode
  services for the other two stores, and the monitoring stack below.

## Layout

- `docker-compose.yml` — 14 services. App layer: `caddy`, `postgres`, `redis`,
  `n8n`, `medusa` (techmeout), `puntofeste-backend`,
  `smoothclothingbrand-backend`. Monitoring layer: `node-exporter`,
  `postgres-exporter`, `redis-exporter`, `prometheus`, `loki`, `promtail`,
  `grafana`. One Postgres instance with a database per store (`n8n`,
  `medusa`, `puntofeste`, `smoothclothingbrand`), one shared Redis (isolated
  per store by logical DB index — see below).
- `postgres/init/01-databases.sh` — creates the `n8n` and `medusa` databases
  on first boot. `02-monitoring-user.sh` — creates a read-only
  `postgres_exporter` role (`pg_monitor`) for Prometheus to scrape with,
  instead of reusing the app's own credentials. Both only run automatically
  against a **fresh** Postgres data dir (`docker-entrypoint-initdb.d`
  semantics) — against an already-initialized volume, run the SQL by hand
  once instead (see git history of this file for the exact commands used).
  `puntofeste`/`smoothclothingbrand` databases were likewise created by hand
  (`CREATE DATABASE`) since they were added after the volume already existed.
- `proxy/Caddyfile` — reverse proxy + automatic HTTPS for every VPS-hosted
  domain in the table above. The storefronts (Vercel) aren't in here.
- `monitoring/prometheus/prometheus.yml` — scrape configs for node-exporter,
  postgres-exporter, redis-exporter, and n8n's own `/metrics` endpoint
  (`N8N_METRICS=true`, set directly on the `n8n` service — no separate
  exporter needed, n8n exposes Prometheus format natively).
- `monitoring/loki/loki-config.yml`, `monitoring/promtail/promtail-config.yml` —
  log aggregation; Promtail discovers containers via the Docker socket
  (`docker_sd_configs`), ships all container logs to Loki. 7-day retention.
- `monitoring/grafana/provisioning/` — datasources (Prometheus + Loki) and a
  dashboard (`vps-overview.json`, rows: Host, Postgres, Redis, n8n, Disk &
  logs) provisioned automatically on boot — no manual Grafana setup needed.
  Host: CPU/mem/disk/load/swap/disk-I/O/network. Postgres: connections, DB
  size, cache hit ratio. Redis: memory, ops/sec, connected clients. n8n:
  active workflows, process memory, event loop lag, execution rate by status
  (empty until workflows actually run — that's correct, not broken). Plus a
  disk-free stat and a per-container error/fatal log-line rate panel (Loki)
  so a noisy container stands out before you'd think to go looking.
- `.env.example` — template for the real `/opt/apps/.env` on the VPS
  (secrets, never committed).
- `configure-env.sh` — run **on the VPS**, reads `/opt/apps/.env` and writes
  the derived `/opt/apps/medusa/.env` (backend runtime config).

## Deploying the backend

Normal path: push to `techmeout-medusa`'s `main` branch — GitHub Actions
handles the rest (rsync + `docker compose build medusa && docker compose up
-d medusa`).

Manual path (first bring-up, or debugging): rsync the repo to
`/opt/apps/medusa` yourself, then run the same two commands over SSH.
`medusa-config.ts` in that repo must keep
`databaseDriverOptions.connection.ssl: false` — without it, migrations fail
after exactly 10s with a misleading "SSL configuration issue" error even
though the same `DATABASE_URL` connects fine with a raw `pg` client
(MikroORM attempts SSL against a Postgres server that doesn't support it and
hangs until Medusa's own timeout kills it).

The backend's `CMD` runs `npx medusa db:migrate && npx medusa db:sync-links
&& npm run start` — not the `predeploy` script some Medusa docs mention,
which doesn't exist in the generated `.medusa/server/package.json`.

## Multi-tenant stores (puntofeste, smoothclothingbrand)

This VPS is explicitly an experimentation box (the user's framing, not a
euphemism) — `puntofeste` and `smoothclothingbrand` are two more independent
Medusa stores added later, deliberately run differently from `techmeout`:

- **Dev mode, not production build**: each backend runs `npx medusa develop`
  directly — no Dockerfile, no `medusa build`, no CI/CD. The compose service
  is a plain `node:20` image with the store's repo directory bind-mounted at
  `/app` (e.g. `/opt/apps/puntofeste/apps/backend`), running `npm install &&
  medusa db:migrate && medusa db:sync-links && medusa develop` on start. A
  `git pull` in that directory + Medusa's own file-watcher is the entire
  deploy loop — no rebuild, no restart even, for most changes. Trades
  production-grade robustness for near-zero iteration friction, which is the
  right trade for "try this out" work. `medusa-config.ts` still needs the
  same `databaseDriverOptions.connection.ssl: false` fix as `techmeout` — that
  bug is about MikroORM vs this Postgres server, unrelated to dev vs. prod
  mode.
- **Shared Postgres + Redis, not dedicated instances**: each store gets its
  own Postgres database (`puntofeste`, `smoothclothingbrand`) on the existing
  shared `postgres` container, and is isolated in Redis via logical DB index
  (`redis://redis:6379/1` for puntofeste, `/2` for smoothclothingbrand — `0`
  stays techmeout's default) rather than three separate Redis containers.
  Much lighter on a 4 GB box than giving every store its own database engine.
- **Dev-phase domains, both under `techmeout.it`**: backend at
  `admin-puntofeste.techmeout.it` / `admin-smoothclothingbrand.techmeout.it`
  (VPS, Caddy), storefront at `puntofeste.techmeout.it` /
  `smoothclothingbrand.techmeout.it` (Vercel) — deliberately *not* the real
  brand domains (`shop.puntofeste.com`, `shop.smoothclothingbrand.com`) yet.
  Per the user: prove the setup end-to-end on throwaway subdomains first,
  cut over to the real domains once it's ready. Same
  backend-stays-on-VPS/storefront-goes-to-Vercel split as `techmeout`
  either way.
- **Live end-to-end** as of the last deploy: both backends reachable over
  HTTPS, both storefronts deployed to Vercel and reachable at their
  `*.techmeout.it` custom domains. Moving to the final brand domains later is
  just: point `shop.<brand>.com` DNS at Vercel, `vercel domains add
  shop.<brand>.com`, update `NEXT_PUBLIC_BASE_URL`/`STORE_CORS`/`AUTH_CORS`
  to match, redeploy.

## Monitoring stack

Everything lives behind Grafana at `https://monitor.openempower.com`
(Grafana's own login, `GF_SECURITY_ADMIN_PASSWORD` from `/opt/apps/.env`) —
Prometheus, Loki, and all the exporters are only reachable on the internal
`apps` Docker network, not published to the host or the internet.

- **Metrics**: node-exporter (host CPU/mem/disk/network), postgres-exporter,
  redis-exporter — all scraped by Prometheus every 15s, 15-day retention.
- **Logs**: Promtail tails every container's logs via the Docker socket and
  ships them to Loki (7-day retention). Query with `{container="apps-medusa-1"}`
  etc. in Grafana's Explore view, or use the "Container logs" panel on the
  overview dashboard.
- Added ~400MB RAM total across the new containers — checked against actual
  headroom before deploying (VPS had ~2.8GB available at the time), not just
  assumed to fit.
- **No per-container CPU/memory breakdown** — cAdvisor was tried and removed.
  Docker 29 on this VPS defaults to the containerd-snapshotter image store,
  which broke cAdvisor's Docker factory (it looks for a classic overlay2
  `layerdb` that no longer exists, per-container, forever). cAdvisor does
  register a containerd factory that talks to `/run/containerd/containerd.sock`
  directly and would work with the right `-containerd-namespace=moby` flag,
  but the (broken) Docker factory always wins the "who owns this container"
  race and the containerd one never gets a chance — v0.49.1 has no flag to
  disable Docker detection. Net effect: it produced zero working data and
  just spammed errors into its own logs (which Loki was faithfully ingesting).
  Removed rather than left running broken. `docker stats` on the VPS covers
  this in the meantime; revisit if a cAdvisor release fixes the factory
  priority, or if per-container metrics become actually necessary (e.g.
  chasing a specific memory leak) rather than nice-to-have.

## Notes

- Postgres's healthcheck is `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` —
  without the explicit `-d`, `pg_isready` defaults the target database to the
  *username* (`appuser`), which doesn't exist, so the healthcheck (which still
  reports "healthy" — `pg_isready`'s success criterion is server
  responsiveness, not a successful login) spams `FATAL: database "appuser"
  does not exist` into the Postgres logs every 10s forever. Harmless but
  noisy — especially once you have a log viewer that surfaces it front and
  center.
- `MEDUSA_WORKER_MODE` is left unset (defaults to `shared`) — a single Medusa
  instance handles both the API and background jobs. Not worth splitting into
  separate server/worker containers on a $5/mo VPS unless load grows.
- The backend Dockerfile is a simple single-stage build (`npm ci`, `npm run
  build`, install prod deps into `.medusa/server`), using a
  `--mount=type=cache,target=/root/.npm` BuildKit cache mount so repeated
  builds don't re-download the npm registry each time. It used to need a
  React-18 override to work around a hoisting conflict with the storefront
  when both lived in one Turborepo monorepo — that's gone now that the
  backend is a standalone repo with no sibling storefront workspace forcing
  React 19 into the same dependency tree.
- Setting `projectConfig.redisUrl` alone does **not** switch Medusa's event
  bus/locking to Redis — startup logs still show `Local Event Bus installed.
  This is not recommended for production.` Getting real Redis-backed event
  bus + locking requires explicitly registering
  `@medusajs/medusa/event-bus-redis` and `@medusajs/medusa/workflow-engine-redis`
  in the `modules` array. Left as in-memory for now since a single
  `shared`-mode instance doesn't need it.
- Disk/log hygiene beyond Loki's 7-day retention (Docker image/build-cache
  pruning, n8n execution pruning, off-VPS backups, disk-usage alerting) is a
  known follow-up, not yet automated — `docker builder prune -f` has been run
  by hand a few times after iterative builds.
