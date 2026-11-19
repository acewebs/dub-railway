# Deploying Dub on Railway

A Railway-ready fork of [dubinc/dub](https://github.com/dubinc/dub), verified to
build and run on Railway (Node 23.11.0 / pnpm 9.15.9). Deployed and serving as a
3-service project; the dashboard works on the auto-generated Railway domain.

## Architecture - 3 Railway services

| Service | Source | Role |
|---|---|---|
| **web** | this repo, repo root (`Dockerfile`) | the Dub Next.js app (`apps/web`) |
| **MySQL** | Railway MySQL (one-click) | primary database (db name `railway`) |
| **planetscale-proxy** | this repo, **root dir `railway/ps-http-sim`** (Dockerfile) | HTTP shim so Dub's `@planetscale/database` driver can talk to plain MySQL |

Dub talks to the database two ways: Prisma over the MySQL wire protocol
(`DATABASE_URL`) and the PlanetScale serverless HTTP driver
(`PLANETSCALE_DATABASE_URL` → the proxy). Both are mandatory.

### planetscale-proxy

The upstream `ghcr.io/mattrobenolt/ps-http-sim` image is a **shell-less scratch
image**, so `railway/ps-http-sim/Dockerfile` copies its static binary onto alpine
and sets the ENTRYPOINT (Railway execs start commands as literal argv, so it's
wrapped in `sh -c '…'` to expand the env vars):

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
- **Set its Root Directory to `railway/ps-http-sim`** - the CLI can't set root dir,
  but a template does carry it. Without it the proxy builds the web app's
  Dockerfile instead.

## Build / deploy (handled by the root `Dockerfile`)

A Railway template cannot carry a build command - the only build setting a template
holds is the builder - and Config as Code stops being read on 2026-12-01. So the
build lives in the `Dockerfile` and the startup work lives in the image's
entrypoint, leaving the template with nothing to carry but `builder: DOCKERFILE`.

- Build: start a throwaway MariaDB inside the build layer, `pnpm --filter web
  prisma:push` into it, then `pnpm build` with an 8 GB heap.
  - The 8 GB heap avoids an OOM in `next build`.
  - `prisma db push` runs **in the build** so `generateStaticParams` DB queries hit
    existing (empty) tables instead of failing.
  - The database is local to the build because the Railway builder can't reach the
    private network, and the alternative (MySQL's public TCP proxy, via a
    `DATABASE_URL_BUILD` variable) puts a public hostname in a service-to-service
    variable, which fails Railway's private networking guideline and breaks the
    build whenever that proxy is absent. The queries hit empty tables either way.
    Debian ships MariaDB rather than MySQL; `prisma db push` takes Dub's schema on
    10.11 including the `@@fulltext` indexes, verified 2026-11-19.
  - A second stage copies `/app` forward so the build's database server does not
    ship in the runtime image.
  - Railway only passes a variable into a Dockerfile build if the Dockerfile
    declares an `ARG` for it. Anything the build reads, including
    `NEXT_PUBLIC_APP_DOMAIN` (inlined into the client bundle) and the Stripe /
    Upstash Vector dummies, needs a line there.
  - `.next/cache` is 4 GB of webpack cache that nothing reads at runtime; it is
    removed in the layer that creates it, or the image ships it.
- Start: `railway/web-entrypoint.sh` pushes the schema over the private
  `DATABASE_URL`, then execs `pnpm --filter web start`. Node pinned by the base
  image (23.11.0), matching `.nvmrc`.

## Fork patches applied

- **`next` bumped to `15.5.21`** in `apps/web`, `@dub/ui`, `@dub/utils` (deps + peers)
  - Railway's scanner blocks the flagged CVE and reads the whole lockfile.
- **`packages/utils/src/constants/main.ts`** - `NEXT_PUBLIC_APP_DOMAIN` now drives
  `APP_HOSTNAMES`/`APP_DOMAIN`, so the deployment's own domain is treated as the
  dashboard domain (otherwise a bare domain shows "Link Not Found"). dub.co behavior
  unchanged when the var is unset.
- **`apps/web/vercel.json` removed** (Vercel-only; cron schedules noted below).
- **`apps/web/app/api/health/route.ts` added** - a readiness probe for the Railway
  healthcheck. It queries both database paths (Prisma over the wire protocol and
  the PlanetScale HTTP driver) and returns 503 if either is down, because a
  misconfigured proxy otherwise leaves the process up with most of the app broken.
  Set the Dub service's healthcheck path to `/api/health` only once this route is
  on the deployed branch, or every deploy hangs on a 404 probe and then fails.

## Environment variables (web service)

Auto-wired references and generated secrets - **no user input needed**:

```bash
DATABASE_URL=${{MySQL.MYSQL_URL}}                 # private, runtime
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
3. **A template does not inherit the MySQL TCP proxy** it was generated from.
   `MYSQL_PUBLIC_URL` is built from `RAILWAY_TCP_PROXY_DOMAIN`/`_PORT`, which only
   exist once the service has a proxy, so without one it resolves to
   `mysql://root:pw@:/railway`. The old build consumed that as
   `DATABASE_URL_BUILD` and died on Prisma `P1013: empty host in database URL`,
   which is what took the published template to 0% health (confirmed on a cold
   deploy 2026-11-19). The build no longer depends on it, but the shape of the
   trap is worth keeping: Railway's own `mysql` template declares
   `networking.tcpProxies: {"3306": {}}` and a generated one does not.
4. **Build-time DB access:** the builder can't reach `*.railway.internal`, so the
   build brings up its own database rather than borrowing the deployed one (see
   the build section).
5. **Proxy start command** is exec'd as literal argv (no shell expansion), so it is
   baked into `railway/ps-http-sim/Dockerfile` as an `sh -c` ENTRYPOINT rather than
   set as a Railway start command.
6. **Secrets in image layers:** every build-time variable lands in image history as
   an ARG (BuildKit warns). Keep the project private; rotate secrets.
7. **Redeploy ≠ latest commit** - it re-runs a deployment's exact commit; push or use
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
