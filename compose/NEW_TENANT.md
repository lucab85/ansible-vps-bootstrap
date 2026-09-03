# Onboarding a new tenant (new Medusa store)

Step-by-step recipe for adding another store to this VPS, following the same
pattern as `puntofeste` and `smoothclothingbrand`: dev-mode backend on the
VPS, storefront on Vercel. Replace `<brand>` / `<BRAND>` with the store's
slug (lowercase, no spaces — used as the Postgres DB name, Redis isolation
comment, env var prefix, and directory name).

Budget ~15-20 minutes hands-on, most of it waiting on `npm install` and the
scaffold tool. Do this over SSH to the VPS (`ssh deploy@192.236.151.70`)
unless noted otherwise.

## 1. Pick a free Redis logical DB index

Each store gets its own Redis logical database to avoid key collisions.
Check what's already used before picking the next one:

```
grep REDIS_URL /opt/apps/docker-compose.yml
```

(`techmeout` uses the default DB `0`, `puntofeste` uses `/1`,
`smoothclothingbrand` uses `/2` — the next new store should use `/3`, and so
on.)

## 2. Create the Postgres database

```
docker exec apps-postgres-1 psql -U appuser -d postgres -c 'CREATE DATABASE <brand>;'
```

## 3. Generate secrets and add them to `/opt/apps/.env`

```
JWT=$(openssl rand -hex 32)
COOKIE=$(openssl rand -hex 32)
cat >> /opt/apps/.env <<EOF

<BRAND>_JWT_SECRET=$JWT
<BRAND>_COOKIE_SECRET=$COOKIE
<BRAND>_BACKEND_URL=https://admin-<brand>.techmeout.it
<BRAND>_STOREFRONT_URL=https://<brand>.techmeout.it
<BRAND>_PUBLISHABLE_KEY=replace-after-seed
EOF
chmod 600 /opt/apps/.env
```

(Dev-phase URL scheme, matching `puntofeste`/`smoothclothingbrand` — backend
on a `techmeout.it` subdomain, storefront also on a `techmeout.it` subdomain
until it's ready to move to the brand's real domain. See "Moving to the real
domain" at the end.)

Record these two secrets (and everything else generated below) in
`credentials.txt` at the repo root — gitignored, not part of this repo's
history, your own local reference.

## 4. Scaffold the backend + storefront

From the VPS, using a throwaway Node container (no Node installed on the
host):

```
cd /opt/apps
docker run --rm --network apps_apps -v /opt/apps:/opt/apps -w /opt/apps node:20 \
  npx --yes create-medusa-app@latest <brand> \
  --skip-db --with-nextjs-starter --no-browser \
  --directory-path /opt/apps --use-npm
sudo chown -R deploy:deploy /opt/apps/<brand>
```

`--skip-db` scaffolds the files only, without touching the database or
prompting for an admin user (both are done explicitly below, for full
non-interactive control). Produces `<brand>/apps/backend` and
`<brand>/apps/storefront`.

**Important**: don't `mkdir /opt/apps/<brand>` beforehand —
`create-medusa-app` refuses to scaffold into an existing directory and will
hang waiting for interactive input.

## 5. Fix `medusa-config.ts`

Copy the known-working config (this exact file already lives in
`techmeout-it/backend`, `techmeout-it/puntofeste-backend`, and
`techmeout-it/smoothclothingbrand-backend` — copy from any of those):

```ts
import { loadEnv, defineConfig } from '@medusajs/framework/utils'

loadEnv(process.env.NODE_ENV || 'development', process.cwd())

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL,
    databaseDriverOptions: {
      connection: {
        ssl: false,
      },
    },
    redisUrl: process.env.REDIS_URL,
    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET,
      cookieSecret: process.env.COOKIE_SECRET,
    }
  },
  admin: {
    backendUrl: process.env.MEDUSA_BACKEND_URL,
  },
})
```

Save it to `/opt/apps/<brand>/apps/backend/medusa-config.ts`. Without the
`databaseDriverOptions.connection.ssl: false` line, migrations fail after
exactly 10s with a misleading "SSL configuration issue" error — MikroORM
attempts SSL against a Postgres server that doesn't support it and hangs
until Medusa's own timeout kills it.

## 6. Add the backend service to `docker-compose.yml`

In `ansible-vps-bootstrap/compose/docker-compose.yml` (locally), add a block
matching the `puntofeste-backend` service exactly, swapping in `<brand>` and
the next free Redis index:

```yaml
  <brand>-backend:
    image: node:20
    restart: unless-stopped
    working_dir: /app
    volumes:
      - /opt/apps/<brand>/apps/backend:/app
    command: sh -c "npm install && npx medusa db:migrate && npx medusa db:sync-links && npx medusa develop"
    environment:
      NODE_ENV: development
      DATABASE_URL: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/<brand>"
      REDIS_URL: "redis://redis:6379/<N>"
      STORE_CORS: ${<BRAND>_STOREFRONT_URL}
      ADMIN_CORS: ${<BRAND>_BACKEND_URL}
      AUTH_CORS: "${<BRAND>_STOREFRONT_URL},${<BRAND>_BACKEND_URL}"
      JWT_SECRET: ${<BRAND>_JWT_SECRET}
      COOKIE_SECRET: ${<BRAND>_COOKIE_SECRET}
      MEDUSA_BACKEND_URL: ${<BRAND>_BACKEND_URL}
    networks: [apps]
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
```

Also add `<brand>-backend` to `caddy`'s `depends_on` list. **No frontend
service goes in compose** — the storefront runs on Vercel, not the VPS (see
step 10).

Use `npm install`, not `npm ci` — these per-app directories (scaffolded as
`apps/backend` inside a monorepo-shaped tree) don't have their own
`package-lock.json` until you generate one in step 8, and `npm ci` fails
outright without one.

## 7. Add the Caddyfile block

In `compose/proxy/Caddyfile`:

```
admin-<brand>.techmeout.it {
	reverse_proxy <brand>-backend:9000
}
```

## 8. Deploy the config and bring up the backend

```
scp compose/docker-compose.yml deploy@192.236.151.70:/opt/apps/docker-compose.yml
scp compose/proxy/Caddyfile deploy@192.236.151.70:/opt/apps/proxy/Caddyfile
ssh deploy@192.236.151.70 "cd /opt/apps && docker compose config -q"   # validate first
ssh deploy@192.236.151.70 "cd /opt/apps && docker compose up -d <brand>-backend"
ssh deploy@192.236.151.70 "docker exec apps-caddy-1 caddy reload --config /etc/caddy/Caddyfile"
```

Wait for it to actually finish starting before doing anything else —
`npm install` + migrations + the dev server booting takes a couple of
minutes:

```
until ssh deploy@192.236.151.70 "docker logs apps-<brand>-backend-1 2>&1" | grep -q "Server is ready"; do sleep 3; done
```

The backend's migration step also auto-seeds demo data (a default "Europe"
region covering IT/DE/FR/ES/GB/DK/SE, demo products, a default publishable
API key) — no separate seed step needed.

**DNS**: `admin-<brand>.techmeout.it` needs an A record to `192.236.151.70`
before this is reachable over HTTPS — Caddy will keep retrying automatically
once it resolves. Confirm with `curl -s -o /dev/null -w '%{http_code}\n'
https://admin-<brand>.techmeout.it/health` (expect `200`).

## 9. Create the admin user and grab the publishable key

```
ssh deploy@192.236.151.70 "docker exec apps-<brand>-backend-1 npx medusa user -e <email> -p '<password>'"
ssh deploy@192.236.151.70 "docker exec apps-postgres-1 psql -U appuser -d <brand> -t -c \"SELECT token FROM api_key WHERE type='publishable';\""
```

Update `<BRAND>_PUBLISHABLE_KEY` in `/opt/apps/.env` with the real value from
the second command, and record both in `credentials.txt`.

## 10. Extract the code, push to GitHub, set up Vercel

On your local machine (not the VPS):

```
mkdir ~/prj/github/<brand>-backend ~/prj/github/<brand>-frontend
rsync -az --exclude node_modules --exclude .medusa --exclude dist --exclude .DS_Store \
  deploy@192.236.151.70:/opt/apps/<brand>/apps/backend/ ~/prj/github/<brand>-backend/
rsync -az --exclude node_modules --exclude .next --exclude .DS_Store \
  deploy@192.236.151.70:/opt/apps/<brand>/apps/storefront/ ~/prj/github/<brand>-frontend/

rm -f ~/prj/github/<brand>-backend/.env ~/prj/github/<brand>-frontend/.env.local
rm -f ~/prj/github/<brand>-frontend/tsconfig.tsbuildinfo ~/prj/github/<brand>-frontend/Dockerfile

# standard Next.js .gitignore for the frontend (node_modules, .next, .env*.local, .vercel, etc.)
# — copy from an existing *-frontend repo, e.g. puntofeste-frontend/.gitignore

cd ~/prj/github/<brand>-backend && npm install --package-lock-only
cd ~/prj/github/<brand>-frontend && npm install --package-lock-only

cd ~/prj/github/<brand>-backend && git init -q && git add -A && git commit -q -m "Initial commit"
gh repo create techmeout-it/<brand>-backend --private --source=. --remote=origin --push

cd ~/prj/github/<brand>-frontend && git init -q && git add -A && git commit -q -m "Initial commit"
gh repo create techmeout-it/<brand>-frontend --private --source=. --remote=origin --push
```

Then Vercel, from `~/prj/github/<brand>-frontend`:

```
vercel link --yes --project <brand>-frontend
echo "https://admin-<brand>.techmeout.it" | vercel env add NEXT_PUBLIC_MEDUSA_BACKEND_URL production
echo "it" | vercel env add NEXT_PUBLIC_DEFAULT_REGION production
echo "https://<brand>.techmeout.it" | vercel env add NEXT_PUBLIC_BASE_URL production
echo "<publishable-key-from-step-9>" | vercel env add NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY production
vercel --prod --yes
```

**Only deploy once the backend is confirmed reachable over HTTPS** (step 8's
`curl` check) — Next.js prerenders product/collection pages at build time by
fetching from the backend URL, and the build fails outright if it can't
resolve or connect. If a deploy fails with `ENOTFOUND` or `Bad Gateway`,
that's DNS or the backend not finished starting yet, not a real bug — wait
and retry (`vercel --prod --yes` again), don't start debugging the storefront
code.

## 11. Attach the domain

```
vercel domains add <brand>.techmeout.it
```

If this errors "already assigned to another project", check
`vercel domains inspect <brand>.techmeout.it` — it may already be correctly
linked (this happened for both `puntofeste` and `smoothclothingbrand`; the
error was stale, the assignment was already right). Verify with
`curl -sL https://<brand>.techmeout.it | grep '<title>'`.

## 12. Verify end to end

- `https://admin-<brand>.techmeout.it/app` — Admin login works (Playwright or
  by hand)
- `https://<brand>.techmeout.it` — storefront loads, shows demo products
- `docker compose ps` on the VPS shows `<brand>-backend` healthy
- Check `credentials.txt` has everything: JWT/cookie secrets, admin login,
  publishable key

## Moving to the real domain later

When `<brand>` is ready to leave the `techmeout.it` dev subdomain for its
real brand domain (e.g. `shop.<brand>.com`):

1. Point `shop.<brand>.com` DNS at Vercel (A record to `76.76.21.21`, or
   whatever `vercel domains add shop.<brand>.com` asks for).
2. `vercel domains add shop.<brand>.com` on the `<brand>-frontend` project.
3. Update `<BRAND>_STOREFRONT_URL` in `/opt/apps/.env` to
   `https://shop.<brand>.com`, restart `<brand>-backend` (picks up new
   `STORE_CORS`/`AUTH_CORS`).
4. Update `NEXT_PUBLIC_BASE_URL` in Vercel to match, redeploy.
5. The backend's own domain (`admin-<brand>.techmeout.it`) can stay as-is —
   there's no requirement to move it, it's not customer-facing.
