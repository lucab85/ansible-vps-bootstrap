# App stack: n8n + Medusa backends + Postiz + open-seo + monitoring

Deployed on top of the `ansible-vps-bootstrap` base. Not run by the Ansible
playbook — deployed over SSH, directly on the VPS under `/opt/apps`. This
directory is the version-controlled mirror of the infra config that's
actually deployed; it does **not** contain application source code (see
"Where the code lives" below).

**Adding another store?** See [`NEW_TENANT.md`](NEW_TENANT.md) for the full
step-by-step recipe — note it still documents the original dev-mode
(`medusa develop`) pattern; `heavenartshop-backend` (the newest tenant) uses
the production build+start pattern instead, see "Multi-tenant stores" below
for what actually changed. Every generated password/secret for every service
in this stack is recorded in `credentials.txt` at the repo root (gitignored —
not in this file, not in git history, local reference only).

## Domains

| Service                              | Domain                                    | Hosted on |
|---------------------------------------|---------------------------------------------|-----------|
| n8n                                    | `n8n.openempower.com`                      | VPS |
| Grafana                                | `monitor.openempower.com`                  | VPS |
| Postiz (social scheduling)             | `postiz.openempower.com`                   | VPS |
| open-seo                               | `seo.openempower.com`                      | VPS |
| Medusa backend/admin (techmeout)       | `admin.techmeout.it`                       | VPS (stopped, kept as template) |
| Medusa storefront (techmeout)          | `shop.techmeout.it`                        | Vercel |
| Medusa backend (puntofeste)            | `admin-puntofeste.techmeout.it`            | VPS |
| Medusa storefront (puntofeste)         | `puntofeste.techmeout.it`                  | Vercel |
| Medusa backend (smoothclothingbrand)   | `admin-smoothclothingbrand.techmeout.it`   | VPS |
| Medusa storefront (smoothclothingbrand)| `smoothclothingbrand.techmeout.it`         | Vercel |
| Medusa backend (heavenartshop)         | `admin-medusa.heavenartshop.com`           | VPS |
| Medusa storefront (heavenartshop)      | `new-heavenartshopcom.vercel.app`          | Vercel |

`techmeout`'s own backend/storefront are deliberately **not** publicly routed
as a live store — `medusa` is stopped (not removed) and kept purely as the
template new tenants get scaffolded from (see `NEW_TENANT.md`), and
`shop.techmeout.it` was never this host's concern (Vercel-only). `puntofeste`
and `smoothclothingbrand` are still on **dev-phase URLs** (subdomains of
`techmeout.it`) rather than their real brand domains — deliberate, per the
user: prove the setup works here first, move to the final domains once
ready. `heavenartshop` is the first tenant on its own real domain from day
one (`heavenartshop.com`, Cloudflare-hosted DNS, **not** proxied — see the
Cloudflare note under "Notes").

`postiz.openempower.com` and `seo.openempower.com` were originally going to
live under `lucaberton.com`, but that domain's subdomains resolve through
Cloudflare's proxy (orange-cloud), which combined with Cloudflare's Flexible
SSL mode produced an infinite `ERR_TOO_MANY_REDIRECTS` loop (Caddy's own
HTTP→HTTPS redirect chasing Cloudflare's HTTP→origin hop, forever). Moved to
`openempower.com`, confirmed non-proxied (resolves straight to the VPS IP,
same as `n8n`/`monitor`).

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

- **techmeout (production-style deploy, currently stopped)**:
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
- **puntofeste, smoothclothingbrand, heavenartshop (production build, not
  dev mode)** — see "Multi-tenant stores" below for the full rationale and
  history (these started as `medusa develop` dev-mode services; switched to
  a production build+start command mid-session to cut memory use — dev
  mode's forked watcher process was the single biggest source of swapped
  memory on this host):
  - Backends: [`techmeout-it/puntofeste-backend`](https://github.com/techmeout-it/puntofeste-backend),
    [`techmeout-it/smoothclothingbrand-backend`](https://github.com/techmeout-it/smoothclothingbrand-backend),
    [`lucab85/new-heavenartshop-backend`](https://github.com/lucab85/new-heavenartshop-backend)
    (private; cloned to `/opt/apps/heavenartshop-backend` via the host's own
    SSH key, not the narrowly GITHUB_TOKEN used by the n8n workflow — that
    token only covers `ansiblebyexample.com`). All three run `npm install &&
    medusa build && rm -rf node_modules && cd .medusa/server && npm install
    && medusa db:migrate && medusa db:sync-links && medusa start` on every
    container start — no CI/CD, no Dockerfile, plain `node:20` bind-mounting
    the repo directory. A `git pull` + container recreate is the deploy loop.
  - Storefronts: [`techmeout-it/puntofeste-frontend`](https://github.com/techmeout-it/puntofeste-frontend),
    [`techmeout-it/smoothclothingbrand-frontend`](https://github.com/techmeout-it/smoothclothingbrand-frontend),
    each on their own Vercel project. heavenartshop's storefront is not yet
    in this repo's tracking (Vercel project `new-heavenartshopcom`).
  - `heavenartshop-backend` differs from the other two in a few ways worth
    knowing before touching it: flat repo layout (package.json/
    medusa-config.ts at repo root, not nested under `apps/backend` — it
    wasn't scaffolded via `create-medusa-app`'s monorepo layout, so its bind
    mount is `/opt/apps/heavenartshop-backend:/app` directly), registers
    `@medusajs/medusa/payment-stripe` (keys optional, blank doesn't block
    startup), and ships a `npm run seed` script
    (`src/scripts/seed-heaven-art.ts`) that must be run **exactly once**
    (reruns duplicate products/regions) and **from the project root**, not
    `.medusa/server` — `medusa build` doesn't copy `src/scripts/` into its
    output, so the script only exists pre-build. Running it needs the root
    `node_modules` that the production command deletes after building;
    reinstall with `docker exec -w /app apps-heavenartshop-backend-1 npm
    install` first, run the seed, and the next container recreate cleans it
    up again automatically (the command's own `rm -rf node_modules` step).
- **postiz** (`ghcr.io/gitroomhq/postiz-app`) and **open-seo**
  (`ghcr.io/every-app/open-seo`) — see their own sections below.
- **This repo's `compose/`** only owns the infra layer: Postgres, Redis,
  Caddy, n8n, Temporal, how the `techmeout` backend image gets built, the
  three Medusa tenant services, Postiz, open-seo, and the monitoring stack
  below.

## Layout

- `docker-compose.yml` — 20 services. App layer: `caddy`, `postgres`,
  `redis`, `n8n`, `claude-bridge`, `temporal`, `postiz`, `open-seo`,
  `medusa` (techmeout, stopped), `puntofeste-backend`,
  `smoothclothingbrand-backend`, `heavenartshop-backend`. Monitoring layer:
  `node-exporter`, `cadvisor`, `postgres-exporter`, `redis-exporter`,
  `prometheus`, `loki`, `promtail`, `grafana`. One Postgres instance with a
  database per store (`n8n`, `medusa`, `puntofeste`, `smoothclothingbrand`,
  `heavenartshop`, `postiz`, `temporal`, `temporal_visibility`), one shared
  Redis (isolated per store by logical DB index — `0` techmeout, `1`
  puntofeste, `2` smoothclothingbrand, `3` postiz, `4` heavenartshop).
- **Startup is staggered on purpose**: `puntofeste-backend` →
  `smoothclothingbrand-backend` → `heavenartshop-backend` → `open-seo`, each
  gated on the previous one's `healthcheck` (`wget -qO-
  http://localhost:9000/health`, 15 min of grace). All four rebuild from
  scratch (`npm install && medusa build` / open-seo's own vite/esbuild
  build) on every container start — three or four of them starting
  simultaneously on a full stack bring-up once pushed load average to 19 on
  this host's 3 vCPUs and made even Caddy unresponsive. `caddy`'s own
  `depends_on` lists all app services with the default `service_started`
  condition (not `service_healthy`) — it doesn't need them *up*, just
  started, so a slow tenant build never blocks n8n/Grafana from being
  reachable.
- **V8 heap ceilings are capped explicitly** (`NODE_OPTIONS=
  --max-old-space-size=...`) on `n8n` (768MB), `postiz` (512MB — applies to
  each of its 3 pm2-managed processes independently), and the three Medusa
  backends (1024MB, set **only** on the final `medusa start` invocation, not
  on the `npm install && medusa build` steps before it — capping the build
  step's heap has caused a real outage here once already; build memory
  needs aren't the same as steady-state runtime needs). V8's default
  `--max-old-space-size` heuristic gives each Node process ~2GB on this host
  with no awareness of the ~7 other Node processes also running here — not
  a problem at observed usage (each well under 300MB in steady state) but
  an unbounded worst case worth bounding anyway. `open-seo` is deliberately
  left uncapped — it rebuilds via vite/esbuild on every start and its peak
  build memory hasn't been profiled, so an arbitrary cap risks the same
  class of self-inflicted outage as the Medusa build step above.
- `claude-bridge/` — see `claude-bridge/README.md`: exposes the host's
  already-authenticated Claude Code CLI as an OpenAI-compatible API,
  internal-only (`http://claude-bridge:8000` on the `apps` network, no
  Caddy route), so n8n workflows can call it instead of a paid Anthropic
  API key. Mounts the whole `~/.claude` directory, not individual files
  inside it — see the Notes entry on single-file bind mounts below, this is
  the original case that pattern was diagnosed against.
- `postgres/init/01-databases.sh` — creates the `n8n` and `medusa` databases
  on first boot. `02-monitoring-user.sh` — creates a read-only
  `postgres_exporter` role (`pg_monitor`) for Prometheus to scrape with,
  instead of reusing the app's own credentials. Both only run automatically
  against a **fresh** Postgres data dir (`docker-entrypoint-initdb.d`
  semantics) — against an already-initialized volume, run the SQL by hand
  once instead (see git history of this file for the exact commands used).
  `puntofeste`/`smoothclothingbrand`/`heavenartshop`/`postiz` databases were
  likewise created by hand (`CREATE DATABASE`) since they were added after
  the volume already existed. `temporal`/`temporal_visibility` are created
  automatically by `temporalio/auto-setup` on its first boot (the shared
  Postgres user has `CREATEDB`).
- `proxy/Caddyfile` — reverse proxy + automatic HTTPS for every VPS-hosted
  domain in the table above. The storefronts (Vercel) aren't in here. Global
  options block (`admin 0.0.0.0:2019` + `metrics`) exposes Caddy's own
  Prometheus metrics on the admin port — bound to `0.0.0.0` (not the default
  `127.0.0.1`) so Prometheus, a *different* container, can reach it over the
  `apps` network; same trust boundary as every other exporter (internal
  Docker network only, never published to the host or internet). **Mounted
  as a directory** (`./proxy:/etc/caddy:ro`), not a single file — see the
  Notes entry on single-file bind mounts, this is where that bug was found
  a second time and fixed for good. `seo.openempower.com`'s `basic_auth`
  block is the only thing standing between the public internet and
  open-seo (`AUTH_MODE=local_noauth`, no auth of its own, by its own docs).
  `admin-medusa.heavenartshop.com` has a `handle /static/*` sub-block
  setting a 1-year immutable `Cache-Control` on product images via
  `reverse_proxy`'s `header_down` (not the bare `header` directive — that
  left the backend's own default `Cache-Control: max-age=0` alongside it
  instead of replacing it, two headers on one response, undefined behavior
  for browsers to reconcile).
- `monitoring/prometheus/prometheus.yml` — scrape configs for node-exporter,
  cadvisor, postgres-exporter, redis-exporter, n8n's own `/metrics` endpoint
  (`N8N_METRICS=true`, set directly on the `n8n` service — no separate
  exporter needed, n8n exposes Prometheus format natively), and Caddy
  (`caddy:2019/metrics`).
- `monitoring/postgres-exporter/queries.yaml` — custom queries extending the
  exporter beyond its built-in collectors: `pg_stat_statements_*` (per-query
  calls/total & mean exec time/rows — needs the `pg_stat_statements`
  extension, see Notes) and `pg_backend_age_*` (oldest transaction/query age
  grouped by `datname`+`state` — the metric name is deliberately *not*
  `pg_stat_activity`, since this exporter version already ships a built-in
  collector under that name with different label sets; reusing the name
  causes a HELP-string collision that takes down the *entire* `/metrics`
  endpoint with a 500, not just the new metric — learned the hard way).
- `monitoring/loki/loki-config.yml`, `monitoring/promtail/promtail-config.yml` —
  log aggregation; Promtail discovers containers via the Docker socket
  (`docker_sd_configs`), ships all container logs to Loki. 7-day retention.
- `monitoring/grafana/provisioning/` — datasources (Prometheus + Loki) and a
  dashboard (`vps-overview.json`, 61 panels) provisioned automatically on
  boot — no manual Grafana setup needed. Grafana's file provider polls every
  30s and picks up edits to the JSON directly (it's a directory bind mount,
  so plain file edits are visible immediately). Rows: Host, Postgres, Redis,
  n8n, Disk & logs, **Caddy (edge) — RED**, **Postgres — extra**, **Redis —
  extra**, **Host — extra (USE)**, **Disaster readiness**, **Postgres —
  query insights**, **Containers (cAdvisor)** (per-container CPU %/memory/
  network I/O by name — see the cAdvisor note under Monitoring stack, this
  was previously believed broken and removed, then fixed), and **zram**
  (compression ratio, uncompressed-vs-compressed-vs-actual-RAM-used over
  time, RAM saved in absolute bytes — see the zram note below).
- `backup-postgres.sh` — nightly `pg_dump -Fc` of every database on the
  shared Postgres instance (dynamically enumerated, not hardcoded), 30-day
  rotation, run via cron on the VPS (not Ansible-managed — install with
  `(crontab -l 2>/dev/null; echo "0 3 * * * /opt/apps/backup-postgres.sh") |
  crontab -`, runs nightly at 03:00 in the host's timezone). Writes to
  `/opt/apps/backups/<db>_<timestamp>.dump`, logs to
  `/opt/apps/backups/backup.log`, and emits a Prometheus textfile metric
  (`/opt/apps/monitoring/textfile_collector/postgres_backup.prom` —
  `pg_backup_last_success_timestamp_seconds`, `pg_backup_last_run_status` per
  database) that node-exporter's textfile collector picks up, feeding the
  "Disaster readiness" dashboard row. Restore: `docker exec -i
  apps-postgres-1 pg_restore -U appuser -d <dbname> -c <
  backups/<file>.dump`. Off-VPS copies of these dumps are still not
  automated — see the "known follow-up" note under Monitoring stack.
- `zram-metrics.sh` — reads `/sys/block/zram0/mm_stat` every minute (cron:
  `* * * * * /opt/apps/zram-metrics.sh`, same not-Ansible-managed pattern as
  the backup script) and writes it as a Prometheus textfile metric
  (`node_zram_orig_data_bytes`, `node_zram_compr_data_bytes`,
  `node_zram_mem_used_total_bytes`, `node_zram_mem_limit_bytes`,
  `node_zram_disksize_bytes`, `node_zram_same_pages`) since node-exporter
  has no built-in zram collector. Feeds the "zram" dashboard row.
- `disk-cleanup.sh` — nightly Docker/log hygiene (cron: `30 3 * * *
  /opt/apps/disk-cleanup.sh`, same not-Ansible-managed pattern as the two
  scripts above; install with `(crontab -l 2>/dev/null; echo "30 3 * * *
  /opt/apps/disk-cleanup.sh") | crontab -`; offset 30 min after the Postgres
  backup so the two don't contend for I/O). Prunes Docker build cache and
  dangling images (`docker image prune -f`, deliberately never `-a` — an
  `-a` prune removes *any* image not attached to a running container, which
  would be fine today but is one accidental `docker compose down` away from
  deleting an image that takes 10+ minutes to rebuild, like `open-seo` — see
  its own section below), removes containers stopped >24h, vacuums the
  systemd journal down to 200MB, clears the APT package cache, and clears
  stale `/tmp/*-seo-fix`/`*-scratch` scratch clones older than 2 days. Logs
  to `/opt/apps/disk-cleanup.log`. Added after the host hit 93% disk usage
  (57GB volume down to 4GB free) from accumulated build cache and dangling
  images — see the "known follow-up" note under Notes, now closed for the
  image/build-cache piece.
- `.env.example` — template for the real `/opt/apps/.env` on the VPS
  (secrets, never committed).
- `configure-env.sh` — run **on the VPS**, reads `/opt/apps/.env` and writes
  the derived `/opt/apps/medusa/.env` (backend runtime config).

## Deploying the backend

Normal path: push to `techmeout-it/backend`'s `main` branch — GitHub Actions
handles the rest (rsync + `docker compose build medusa && docker compose up
-d medusa`). Currently **not** publicly routed — see "Domains" above.

Manual path (first bring-up, or debugging): rsync the repo to
`/opt/apps/medusa` yourself, then run the same two commands over SSH.
`medusa-config.ts` in that repo must keep
`databaseDriverOptions.connection.ssl: false` — without it, migrations fail
after exactly 10s with a misleading "SSL configuration issue" error even
though the same `DATABASE_URL` connects fine with a raw `pg` client
(MikroORM attempts SSL against a Postgres server that doesn't support it and
hangs until Medusa's own timeout kills it). Every store's `medusa-config.ts`
needs this same fix; it's about MikroORM vs this Postgres server, not
specific to any one store.

## Multi-tenant stores (puntofeste, smoothclothingbrand, heavenartshop)

This VPS is explicitly an experimentation box (the user's framing, not a
euphemism). All three tenant stores now run the **same production
build+start pattern**:

```
npm install && npx medusa build && rm -rf node_modules && cd .medusa/server \
  && npm install && npx medusa db:migrate && npx medusa db:sync-links \
  && NODE_ENV=production NODE_OPTIONS='--max-old-space-size=1024' npx medusa start
```

- **Why not dev mode (`medusa develop`)**: that's how these three started —
  no Dockerfile, no build step, `npm install && medusa db:migrate &&
  medusa db:sync-links && medusa develop`, with the store's repo directory
  bind-mounted straight in. Traded production-grade robustness for
  near-zero iteration friction, which was the right trade early on. Dropped
  once memory got tight: dev mode forks a second Node process for the
  actual server on top of the supervisor/watcher one (roughly doubling
  RSS), and its file-watcher/HMR state was the single biggest source of
  swapped-out memory on this host. `NODE_ENV=production` must **not** be
  set during `npm install`/`medusa build` — npm skips devDependencies
  (`ts-node`, `@swc/core`) under `NODE_ENV=production`, which breaks loading
  `medusa-config.ts`; it's set only on the final `medusa start`. Migrations
  and the running server both operate out of `.medusa/server` (its own
  `package.json`/`node_modules`, independent of the project root) per
  Medusa's own production docs — the root `node_modules` (hundreds of MB)
  becomes fully unused once the build completes, hence `rm -rf` after
  `medusa build`.
- **Dev-mode-only issues that no longer apply** (kept here for history, in
  case a future store goes back to dev mode): Vite's dev server (used by
  `medusa develop`'s admin bundler) blocks requests whose `Host` header
  isn't localhost/an IP/an explicitly allowed host — fixed via
  `__MEDUSA_ADMIN_ADDITIONAL_ALLOWED_HOSTS` (comma-separated hostnames, no
  scheme) on the `*-backend` compose service. Separately,
  `@medusajs/admin-vite-plugin@2.20.1` had its own Vite-7 incompatibility
  (broken i18n virtual-module resolution) fixed per-store in each backend
  repo's `medusa-config.ts` via the `admin.vite` config hook. Neither is
  relevant to the production build (it serves a static admin build, no Vite
  dev server involved) but both fixes are still in the store repos and
  harmless to leave.
- **Shared Postgres + Redis, not dedicated instances**: each store gets its
  own Postgres database on the existing shared `postgres` container, and is
  isolated in Redis via logical DB index (see "Layout" above for the
  current index assignments) rather than separate Redis containers. Much
  lighter on a 4GB box than giving every store its own database engine.
- **Startup is staggered and heap-capped** — see "Layout" above for both;
  this section used to have the details, moved there since it now applies
  to open-seo too, not just the Medusa tenants.
- **heavenartshop specifics** (flat repo layout, Stripe module, seed
  script, persistent `static/` volume) — see "Where the code lives" above.
- **Dev-phase domains**: `puntofeste`/`smoothclothingbrand` are still on
  `techmeout.it` subdomains (both backend and storefront) rather than their
  real brand domains — per the user, prove the setup end-to-end on
  throwaway subdomains first, cut over later. `heavenartshop` skipped this
  phase and went straight to its real domain. Moving a store to its final
  domain later is just: point `shop.<brand>.com` DNS at Vercel, `vercel
  domains add shop.<brand>.com`, update
  `NEXT_PUBLIC_BASE_URL`/`STORE_CORS`/`AUTH_CORS` to match, redeploy — same
  for the VPS-side `*_BACKEND_URL`/`*_STOREFRONT_URL` env vars and the
  Caddyfile block.

## Postiz (social media scheduling)

`ghcr.io/gitroomhq/postiz-app`, at `postiz.openempower.com`. Upstream's own
docker-compose pairs this with a dedicated Elasticsearch + Temporal-Postgres
+ Temporal-UI + admin-tools stack (~1.5-2GB+ RAM) — all skipped here:

- **Temporal** (`temporalio/auto-setup:1.29.7`) runs standalone, reusing
  this host's shared Postgres (its own `appuser` has `CREATEDB` — auto-setup
  creates `temporal`/`temporal_visibility` on first boot) instead of a
  dedicated Postgres container. `DYNAMIC_CONFIG_FILE_PATH=
  config/dynamicconfig/development-sql.yaml` enables SQL-only (non-
  Elasticsearch) visibility — the same file upstream's own compose uses;
  Elasticsearch is a pure opt-in there (`ENABLE_ES=true` + `ES_SEEDS`), not
  a requirement. That file isn't baked into the `auto-setup` image; it's
  fetched verbatim from `temporalio/docker-compose`'s repo and mounted in
  from `temporal/dynamicconfig/`.
- **SQL visibility's search-attribute limit bit us once**: standard
  (non-Elasticsearch) visibility hard-codes exactly 3 generic Text-type
  custom search-attribute columns. Temporal ships 2 of them already
  registered as unused defaults (`CustomTextField`, `CustomStringField`),
  and Postiz's backend tries to register 2 more of its own
  (`organizationId`, `postId`) in a single batch call on every boot — with
  only 1 free slot, the whole batch fails
  (`cannot have more than 3 search attribute of type Text`), and the
  backend process stays alive (an unhandled rejection during NestJS's
  module-init phase, before `app.listen()`) but never actually binds to
  port 3000 — nginx inside the container returns 502 for everything,
  silently, no crash to notice. Fixed by removing the 2 unused Temporal
  defaults (`docker exec apps-temporal-1 temporal operator
  search-attribute remove --address temporal:7233 --name
  CustomTextField/CustomStringField`), freeing enough room for Postiz's
  own 2.
- Reuses the shared Redis (`redis://redis:6379/3`) instead of a dedicated
  instance.
- **NODE_OPTIONS heap cap** — see "Layout" above.
- Runs 3 processes under `pm2` inside one container (frontend, backend,
  orchestrator) — recreating `redis`/`temporal` doesn't automatically
  reconnect an *already-running* postiz container (`ioredis` logged
  `ENOTFOUND`/`ECONNREFUSED` until postiz itself was restarted too) — not
  obvious from the compose dependency graph, since postiz's own service
  definition doesn't change when its dependencies get recreated.

## open-seo

`ghcr.io/every-app/open-seo`, at `seo.openempower.com`, behind Caddy
`basic_auth` (its own docs: `AUTH_MODE=local_noauth`, no auth of its own —
"only expose behind your own auth-protected reverse proxy"). Single
container, SQLite-backed via the `open_seo_data` volume mounted at
`/app/.wrangler` (Cloudflare Workers' local D1 emulation — this is built to
deploy to Cloudflare Workers natively, self-hosting via Docker is a
secondary mode).

- **It's a Cloudflare Workers app running under `vite preview` locally** —
  this explains two non-obvious things: (1) it rebuilds via vite/esbuild on
  every container start (not a prebuilt image) — the entrypoint fingerprints
  the build-relevant env vars and skips rebuilding only if unchanged *and*
  the previous build output is still on the same writable layer (a `stop`+
  `start` keeps it; `--force-recreate` always rebuilds). (2) `docker-compose`
  environment variables don't reach the app by default — it reads them
  through Cloudflare Workers bindings (`env.X` inside `workerd`), not
  `process.env` directly, so without `CLOUDFLARE_INCLUDE_PROCESS_ENV=true`
  set, `AUTH_MODE`/`DATAFORSEO_API_KEY`/etc. all silently read as unset no
  matter how many times the container is recreated — confirmed via
  `/api/health` reporting `"AUTH_MODE is unset"` while `docker exec ... env`
  showed it set.
- **DATAFORSEO_API_KEY** is base64(`login:password`) for a real, paid
  DataForSEO account — not the DataForSEO dashboard API key itself.
- **Google Search Console / Analytics OAuth** (`GOOGLE_CLIENT_ID`,
  `GOOGLE_CLIENT_SECRET`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`) — GSC and
  GA4 are two separate OAuth flows on the *same* Google Cloud OAuth client,
  each needing its own Authorized Redirect URI
  (`/api/gsc/oauth/callback`, `/api/ga4/oauth/callback`) — both must be
  present together, not swapped one for the other. `BETTER_AUTH_URL` is
  required even though `AUTH_MODE` stays `local_noauth` (unrelated to
  Better Auth's own hosted-login mode) — without it, the app derives its
  own public origin from the incoming request, which arrives from Caddy as
  plain HTTP (TLS terminates at Caddy), so the OAuth `redirect_uri` it sends
  to Google is `http://...`, which never matches the `https://...` URI
  registered in Google Cloud Console.
- Google Cloud project needs the actual **Search Console API**
  (`searchconsole.googleapis.com`) and/or **Analytics Admin/Data API**
  enabled, separately from creating the OAuth client — a 401/403 from the
  underlying Google API surfaces in the UI as a generic "Connection
  expired. Reconnect to continue.", not the real status code (the app
  deliberately doesn't log the detail for this class of error).
- Upgraded 0.1.7 → 0.1.8 → 0.1.9 (pinned, not `:latest`). 0.1.8: minor
  release, no relevant open issues for this deployment (the one open issue
  at the time, about scheduled rank-tracking checks, doesn't apply: Docker
  self-hosting doesn't run scheduled rank-tracking at all, only
  manually-triggered checks, per the image's own preflight output). 0.1.9
  (2026-09-17): saved reports/reusable report templates readable from MCP
  clients, Search Console MCP filtering by position/impressions, and rank-
  tracking fixes (unsupported-location rejection, failure surfaced when no
  keywords could be checked, US state-abbreviation location matching) — no
  compose/env changes needed.

## Monitoring stack

Everything lives behind Grafana at `https://monitor.openempower.com`
(Grafana's own login, `GF_SECURITY_ADMIN_PASSWORD` from `/opt/apps/.env`) —
Prometheus, Loki, and all the exporters are only reachable on the internal
`apps` Docker network, not published to the host or the internet.

- **Metrics**: node-exporter (host CPU/mem/disk/network), cadvisor
  (per-container CPU/memory/network), postgres-exporter (including custom
  `pg_stat_statements`/`pg_backend_age` queries), redis-exporter, Caddy's
  own `/metrics`, plus two textfile-collector scripts (`backup-postgres.sh`,
  `zram-metrics.sh`) — all scraped by Prometheus every 15s, 15-day
  retention.
- **cAdvisor now works** (this repo's history has an earlier note saying it
  was tried and removed as unfixable on this Docker/containerd setup — that
  turned out to be about its **default** config, not a hard incompatibility).
  Its default per-container disk-usage collector does an expensive full
  filesystem walk every 10s — measured 1.2GB RAM / ~92% CPU sustained on
  this host, thrashing specifically against the Medusa backends'
  `node_modules` trees (hundreds of thousands of small files).
  `--disable_metrics=disk,diskIO,percpu,sched,process,hugetlb,
  referenced_memory,cpu_topology,resctrl,tcp,udp` turns off just that
  expensive collector (CPU/memory/network — what the dashboard actually
  uses — stay on); `--housekeeping_interval=60s` since nothing here needs
  second-by-second resolution. Doesn't need `--privileged` on this
  Ubuntu/cgroup-v2 host (only RHEL/CentOS require that, per cAdvisor's own
  docs).
- **Dashboard follows RED (Rate/Errors/Duration, for Caddy) and USE
  (Utilization/Saturation/Errors, for host/Postgres/Redis)** on top of the
  original per-service panels — see the dashboard row list under `Layout`
  above for the full breakdown.
- **Logs**: Promtail tails every container's logs via the Docker socket and
  ships them to Loki (7-day retention). Query with
  `{container="apps-medusa-1"}` etc. in Grafana's Explore view, or use the
  "Container logs" panel on the overview dashboard.
- **KSM (kernel same-page merging) investigated for cross-container memory
  sharing, concluded not worth it**: stock Node.js processes don't call
  `madvise(MADV_MERGEABLE)`, so plain `echo 1 > /sys/kernel/mm/ksm/run`
  finds nothing to merge (`pages_scanned` stays 0) — KSM was designed for
  KVM guests, which mark their memory mergeable on the guest's behalf; most
  userspace apps never opt in. A `LD_PRELOAD` shim
  ([`unbrice/ksm_preload`](https://github.com/unbrice/ksm_preload)) *can*
  force it by hooking `malloc`/`mmap`/etc. to call `madvise` automatically —
  confirmed with a synthetic test (two containers each holding an identical
  200MB buffer merged down to ~400MB combined savings) — but tested against
  two *real* Medusa processes (same framework version, same source) it only
  found 27 shareable pages (~1.3MB combined, against ~97MB per process) —
  V8's heap is too fragmented and full of per-process pointers/addresses to
  produce many byte-identical pages even running identical code. Not worth
  the risk of an obscure, unmaintained-for-production LD_PRELOAD library
  for a sub-1% memory win.
- Added ~400MB RAM total across the original monitoring containers — checked
  against actual headroom before deploying (VPS had ~2.8GB available at the
  time), not just assumed to fit. Headroom has gotten tighter since (a third
  Medusa tenant, Postiz, open-seo, Temporal all added later) — see the zram
  and NODE_OPTIONS notes under "Layout" for what's been done about it.

## zram (aggressive memory compression)

Configured via the base Ansible role (`systemd-zram-generator`), not this
compose stack — see the repo root's `site.yml`/`group_vars` for the
Ansible-managed pieces. Notable here only because `zram-metrics.sh` (see
"Layout") feeds its own Grafana dashboard row:

- zstd compression, `zram-size = min(ram * 2, 8192)` (7.6GB on this 3.8GB
  host), `swap-priority = 100` (above disk swap's negative auto-priority, so
  the kernel always tries zram first), `vm.swappiness = 100` (raised from
  the default 10 — aggressive, per the user's explicit request).
- Real observed compression: ~3.9-4.0:1. At any given time zram is typically
  holding several GB of "swapped" data in ~1-1.3GB of actual RAM — that gap
  *is* the extra usable memory headroom this buys on a box this small.
  `docker exec apps-redis-1 ...`-style spot checks aren't useful for this;
  use the Grafana "zram" row or `cat /sys/block/zram0/mm_stat` directly
  (`orig_data_size compr_data_size mem_used_total mem_limit mem_used_max
  same_pages pages_compacted huge_pages huge_pages_since`, all bytes/counts).

## Notes

- **Single-file bind mounts pin to the inode present at container *start*,
  not the file's current content** — this has bitten twice. A tool that
  replaces a file via unlink+rename (rewriting in place, not appending) is
  invisible to a container that bind-mounted just that one file: the
  container keeps reading the old inode forever, and there's no error, no
  log line, nothing — commands that read the "live" config inside the
  container (`caddy reload`, `caddy validate`, `cat`) all agree with each
  other and all silently disagree with reality on the host. First hit with
  `claude-bridge`'s `~/.claude/.credentials.json` (the host's OAuth refresh
  replaced it atomically, the bridge kept using the dead token and reported
  "access token has been revoked" even though the host's own session was
  fine) — fixed by mounting the whole `~/.claude` directory instead of the
  individual file. Hit again with `proxy/Caddyfile`: edited it multiple
  times, `caddy reload`/`caddy validate` reported success every time against
  a Caddyfile that, from inside the container, still had the *original*
  6 routes — confirmed by `docker exec apps-caddy-1 cat /etc/caddy/Caddyfile`
  showing stale content while the host file was already correct. Only a full
  `docker compose up -d --force-recreate caddy` (not `restart`, not
  `reload`) actually picked up the new file, because recreation resolves
  the bind mount fresh. Fixed permanently the same way: `./proxy:/etc/caddy:ro`
  (directory), not `./proxy/Caddyfile:/etc/caddy/Caddyfile:ro` (single
  file) — a plain `caddy reload` now genuinely works after editing the
  file. **If a single-file bind mount for a config file gets added again
  anywhere in this stack, mount its parent directory instead from the
  start.**
- **`docker compose restart <service>` does not re-read `.env`/environment
  for the container** — it restarts the existing process with whatever
  environment was already baked in at the last `up`/recreate. Only `up -d`
  (which recreates the container if anything in its resolved config
  changed) picks up new environment values. Caused a full Caddy crash-loop
  once (`OPEN_SEO_BASIC_AUTH_HASH` added to `.env` and the compose file,
  then `restart`ed instead of `up -d`'d — the running container never saw
  the new value, Caddy's `basic_auth` directive got an empty password and
  refused to parse, taking down every other domain with it too since it's
  one Caddy instance for everything).
- **`.env` values containing a literal `$` followed by a letter get silently
  corrupted by Compose's own variable interpolation** — e.g. a bcrypt hash
  like `$2a$14$ZI.nUHxYt...`: Compose treats `$ZI` as a reference to an
  undefined variable `ZI` and substitutes empty string, but leaves `$2a`/
  `$14` alone since a digit can't start a variable name. Fix: single-quote
  the value in `.env` (`KEY='$2a$14$ZI...'`) — Compose's own docs confirm
  single-quoted values are used literally, no interpolation.
- **`docker compose up -d <service>` cascades via `depends_on`** — it also
  brings up every dependency of the named service, regardless of which
  service you actually named. Has caused unwanted restarts of already-
  stopped services (`medusa`, deliberately stopped, came back up once) and
  unwanted cascading rebuilds (fixing an unrelated Caddy issue with `up -d
  caddy` restarted/started five other services at once, because they're
  all in Caddy's `depends_on` list) — this is *why* startup is staggered
  the way it is now (see "Layout"), and why `medusa` was removed from
  Caddy's `depends_on` list entirely once it was deliberately stopped.
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
- Setting `projectConfig.redisUrl` alone does **not** switch Medusa's event
  bus/locking to Redis — startup logs still show `Local Event Bus installed.
  This is not recommended for production.` Getting real Redis-backed event
  bus + locking requires explicitly registering
  `@medusajs/medusa/event-bus-redis` and `@medusajs/medusa/workflow-engine-redis`
  in the `modules` array. Left as in-memory for now since a single
  `shared`-mode instance doesn't need it.
- Postgres/Redis/Temporal version bumps are deliberately staged by risk:
  **Redis 7→8** and **Temporal 1.28.1→1.29.7** were done (additive changes
  only per each project's own release notes; Redis's client libraries in use
  here — `ioredis` — are unaffected by the RESP-level changes). **Postgres
  stays on 16** — n8n's own logs recommend 17+, and Medusa's driver stack
  has no stated blocker either, but Temporal's *own* reference
  docker-compose still pins Postgres 16, there's no confirmation upstream
  has validated newer Postgres, and a real major-version bump means
  `pg_upgrade`/dump-restore across all 8 databases on this one shared
  instance (including two live storefronts with real data) — not a tag
  swap. Revisit when there's an actual reason to, not just because a newer
  tag exists.
- Recreating a container whose `depends_on` changed (e.g. adding a
  healthcheck) recreates it even if you only named a *different* service in
  `up -d` — Compose detects the config diff on affected dependents too, not
  just the one service you named on the command line.
- `pg_stat_statements` needs `shared_preload_libraries` set at Postgres
  startup (can't be enabled by `ALTER SYSTEM` + reload, needs a full
  container restart — briefly drops connections from every backend, which
  reconnect on their next query) *and* `CREATE EXTENSION pg_stat_statements;`
  run by hand once against the `postgres` database on an already-initialized
  volume (same `docker-entrypoint-initdb.d`-only-runs-on-a-fresh-volume
  caveat as `02-monitoring-user.sh` above — new volumes get neither
  automatically without also adding this to an init script). Installing it
  in one database (`postgres`, since that's `postgres-exporter`'s
  `DATA_SOURCE_NAME` target) is enough — the view reports every query
  cluster-wide via its `dbid`/`datname` columns, not just that database's own
  queries.
- Disk/log hygiene beyond Loki's 7-day retention: Docker build-cache and
  dangling-image pruning, journal vacuuming, and APT cache cleanup now run
  nightly via `disk-cleanup.sh` (see "Layout" above), added after the host
  hit 93% disk usage. Deliberately conservative — plain `docker image prune
  -f` (dangling only), not the `-a -f && docker builder prune -a -f`
  combination that had been run by hand a few times before (recovered
  ~3.3GB the last time): `-a` removes any image not attached to a running
  container, which is one accidental `docker compose down` away from
  deleting something like `open-seo`'s image that takes 10+ minutes to
  rebuild from source. n8n execution pruning and disk-usage alerting are
  still open follow-ups. Postgres backups are automated (see
  `backup-postgres.sh` above), but only *on* the VPS — an off-VPS copy (S3,
  another host, etc.) is still not automated; a single-disk failure
  currently takes out both the live data and its backups.
- Cloudflare-proxied domains (orange cloud) resolve to Cloudflare edge IPs,
  not the VPS's real IP — fine for most things, but combined with
  Cloudflare's Flexible SSL mode it produces an infinite same-URL redirect
  loop against Caddy's own automatic HTTP→HTTPS redirect (see the
  Postiz/open-seo domain history above). Every domain actually routed
  through this Caddyfile needs to be either DNS-only (grey cloud) or on
  Cloudflare Full/Full(strict) SSL mode.
