# Deploying Dub on Railway

A Railway-ready fork of [dubinc/dub](https://github.com/dubinc/dub), verified to
build and run on Railway (Node 23.11.0 / pnpm 9.15.9). Deployed and serving as a
3-service project; the dashboard works on the auto-generated Railway domain.

## Architecture - 3 Railway services

| Service | Source | Role |
|---|---|---|
| **web** | this repo, repo root (Nixpacks) | the Dub Next.js app (`apps/web`) |
| **MySQL** | Railway MySQL (one-click) | primary database (db name `railway`) |
| **planetscale-proxy** | this repo, **root dir `railway/ps-http-sim`** (Dockerfile) | HTTP shim so Dub's `@planetscale/database` driver can talk to plain MySQL |

Dub talks to the database two ways: Prisma over the MySQL wire protocol
(`DATABASE_URL`) and the PlanetScale serverless HTTP driver
(`PLANETSCALE_DATABASE_URL` → the proxy). Both are mandatory.

### planetscale-proxy

The upstream `ghcr.io/mattrobenolt/ps-http-sim` image is a **shell-less scratch
image**, so `railway/ps-http-sim/Dockerfile` copies its static binary onto alpine.
Its `railway/ps-http-sim/railway.json` sets the start command (Railway execs start
commands as literal argv, so it's wrapped in `sh -c '…'` to expand the env vars):

```
sh -c 'exec /usr/local/bin/ps-http-sim -listen-addr=0.0.0.0 -listen-port=3900 \
  -mysql-addr=$MYSQLHOST -mysql-port=$MYSQLPORT -mysql-dbname=$MYSQLDATABASE'
```

Key facts:
- ps-http-sim has **no `-mysql-user`/`-mysql-pass` flags** - it uses the credentials
  from the incoming request, i.e. the web app's `PLANETSCALE_DATABASE_URL` user:pass.
  The proxy only needs `MYSQLHOST` / `MYSQLPORT` / `MYSQLDATABASE` (refs to MySQL).
- It binds `0.0.0.0` (it **can't** bind `::` - panics). Reachable on Railway
  environments created after 2025-10-16 (dual-stack); a legacy IPv6-only environment
  would need a socat `::`→IPv4 bridge.
- **Set its Root Directory to `railway/ps-http-sim` in the dashboard** - the CLI
  can't set root dir, and without it the proxy inherits the web app's `railway.json`.

## Build / deploy (handled by the root `railway.json`)

- Build: `DATABASE_URL="$DATABASE_URL_BUILD" pnpm --filter web prisma:push && NODE_OPTIONS=--max-old-space-size=8192 DATABASE_URL="$DATABASE_URL_BUILD" pnpm build`
  - The 8 GB heap avoids an OOM in `next build`.
  - `prisma db push` runs **in the build** so `generateStaticParams` DB queries hit
    existing (empty) tables instead of failing.
  - The build overrides `DATABASE_URL` inline with the **public** URL
    (`DATABASE_URL_BUILD`) because the builder can't reach the private network;
    runtime keeps the private `DATABASE_URL`.
- Start: `pnpm --filter web start`. Node pinned via `.nvmrc` (23.11.0).

## Fork patches applied

- **`next` bumped to `15.5.21`** in `apps/web`, `@dub/ui`, `@dub/utils` (deps + peers)
  - Railway's scanner blocks the flagged CVE and reads the whole lockfile.
- **`packages/utils/src/constants/main.ts`** - `NEXT_PUBLIC_APP_DOMAIN` now drives
  `APP_HOSTNAMES`/`APP_DOMAIN`, so the deployment's own domain is treated as the
  dashboard domain (otherwise a bare domain shows "Link Not Found"). dub.co behavior
  unchanged when the var is unset.
- **`apps/web/vercel.json` removed** (Vercel-only; cron schedules noted below).

## Environment variables (web service)

Auto-wired references and generated secrets - **no user input needed**:

```bash
DATABASE_URL=${{MySQL.MYSQL_URL}}                 # private, runtime
DATABASE_URL_BUILD=${{MySQL.MYSQL_PUBLIC_URL}}    # public, build only
PLANETSCALE_DATABASE_URL=http://root:${{MySQL.MYSQLPASSWORD}}@${{planetscale-proxy.RAILWAY_PRIVATE_DOMAIN}}:3900/${{MySQL.MYSQLDATABASE}}
NEXT_PUBLIC_APP_DOMAIN=${{RAILWAY_PUBLIC_DOMAIN}}
NEXTAUTH_URL=https://${{NEXT_PUBLIC_APP_DOMAIN}}
NEXTAUTH_SECRET=<generate>       # openssl rand -base64 32
ENCRYPTION_KEY=<generate>        # must decode to exactly 32 bytes (base64)
CRON_SECRET=<generate>
```

Bring your own (external accounts):

```bash
UPSTASH_REDIS_REST_URL= ; UPSTASH_REDIS_REST_TOKEN=
QSTASH_URL= ; QSTASH_TOKEN= ; QSTASH_CURRENT_SIGNING_KEY= ; QSTASH_NEXT_SIGNING_KEY=
TINYBIRD_API_KEY= ; TINYBIRD_API_URL=https://api.tinybird.co
STORAGE_ACCESS_KEY_ID= ; STORAGE_SECRET_ACCESS_KEY= ; STORAGE_ENDPOINT=
STORAGE_BASE_URL= ; STORAGE_PUBLIC_BUCKET= ; STORAGE_PRIVATE_BUCKET=
# One login method - OAuth needs no email service; magic-link needs Resend:
GITHUB_CLIENT_ID= ; GITHUB_CLIENT_SECRET=      # or Google, or RESEND_API_KEY
```

Build-only dummies (non-empty so import-time SDK clients don't throw during
"Collecting page data"; replace only to enable those features):

```bash
STRIPE_SECRET_KEY= ; STRIPE_APP_SECRET_KEY= ; STRIPE_APP_SECRET_KEY_TEST= ; STRIPE_APP_SECRET_KEY_SANDBOX=
UPSTASH_VECTOR_REST_URL= ; UPSTASH_VECTOR_REST_TOKEN=
```

(`UNSUBSCRIBE_TOKEN_SECRET` is optional - falls back to `NEXTAUTH_SECRET`.)

## Railway-specific gotchas (all learned the hard way)

1. **Build scanner blocks HIGH-severity CVEs** in direct deps (no opt-out); it reads
   the whole lockfile, so bump the offending dep in every workspace package. `pnpm
   audit` is not a reliable predictor (different DB, false positives).
2. **Import-time SDK clients** (Stripe, Upstash Vector) throw during "Collecting page
   data" if their env is empty - set dummy non-empty values at build.
3. **Build-time DB access:** the builder can't reach `*.railway.internal`; use the
   public MySQL URL for the build only (see build command).
4. **Proxy start command** is exec'd as literal argv (no shell expansion) - wrap in
   `sh -c`. The proxy inherits the web `railway.json` unless its root dir is set.
5. **Secrets in image layers:** Nixpacks bakes all vars as ARG/ENV (BuildKit warns).
   Keep the project private; rotate secrets.
6. **Redeploy ≠ latest commit** - it re-runs a deployment's exact commit; push or use
   "Deploy Latest Commit". `railway-template` is the repo's default branch.

## Known limitations / caveats

- **Tinybird "Forward" workspaces:** new Tinybird signups are Forward workspaces, but
  Dub's `packages/tinybird` uses the Classic `tb push` flow - analytics datasources
  won't deploy out-of-the-box; use a Classic workspace or port to `tb deploy`.
- **Auth needs one external piece:** OAuth (GitHub/Google) needs only a free OAuth
  app; magic-link and email+password both send email → need Resend/SMTP.
- **Geo/IP analytics:** `record-click` uses `@vercel/functions` geolocation/ipAddress,
  which return empty off-Vercel - clicks record without country/city.
- **Scheduled jobs:** the original `vercel.json` crons were removed; Dub's
  `/api/cron/*` jobs need replicating via Railway cron (auth with `CRON_SECRET`).
- **Storage** can optionally be self-hosted on Railway with MinIO (Dub uses an
  S3-compatible client) instead of R2; Redis/QStash/Tinybird cannot practically move.
```
