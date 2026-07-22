# Deploying Dub on Railway

This branch is a frozen, Railway-ready snapshot of [dubinc/dub](https://github.com/dubinc/dub)
pinned at commit `05c50b0`. It has been verified to compile and type-check on
Node 23.11.0 / pnpm 9.15.9.

## Architecture — 3 Railway services

| Service | Source | Role |
|---|---|---|
| **web** | this repo, `railway-template` branch (root dir) | the Dub Next.js app (`apps/web`) |
| **mysql** | Railway MySQL (one-click) | primary database |
| **planetscale-proxy** | image `ghcr.io/mattrobenolt/ps-http-sim:latest` | HTTP shim that lets Dub's `@planetscale/database` driver talk to plain MySQL |

Dub talks to the database two ways: Prisma over the MySQL wire protocol
(`DATABASE_URL`) and the PlanetScale serverless HTTP driver
(`PLANETSCALE_DATABASE_URL` → the proxy). Both env vars are mandatory.

### planetscale-proxy start args

```
-listen-port=3900
-mysql-addr=${{MySQL.MYSQLHOST}}
-mysql-port=${{MySQL.MYSQLPORT}}
-mysql-dbname=${{MySQL.MYSQLDATABASE}}
-mysql-user=${{MySQL.MYSQLUSER}}
-mysql-pass=${{MySQL.MYSQLPASSWORD}}
```

## Build / run (handled by `railway.json`)

- Build: `NODE_OPTIONS=--max-old-space-size=8192 pnpm build` — the heap bump is
  required; the default Node heap OOMs during `next build`.
- Pre-deploy: `pnpm --filter web prisma:push` — syncs the schema (safe with
  `relationMode="prisma"`, no foreign keys).
- Start: `pnpm --filter web start`.
- Node pinned via `.nvmrc` (23.11.0). If Nixpacks doesn't pick it up, set
  `NIXPACKS_NODE_VERSION=23` on the web service.

## Required environment variables (web service)

```bash
# Database
DATABASE_URL=mysql://${{MySQL.MYSQLUSER}}:${{MySQL.MYSQLPASSWORD}}@${{MySQL.MYSQLHOST}}:${{MySQL.MYSQLPORT}}/${{MySQL.MYSQLDATABASE}}
PLANETSCALE_DATABASE_URL=http://root:unused@${{planetscale-proxy.RAILWAY_PRIVATE_DOMAIN}}:3900/planetscale

# App / auth
NEXTAUTH_URL=https://<your-app-domain>
NEXTAUTH_SECRET=<openssl rand -base64 32>
NEXT_PUBLIC_APP_DOMAIN=<your-app-domain>
ENCRYPTION_KEY=<32-byte base64>
CRON_SECRET=<random>
UNSUBSCRIBE_TOKEN_SECRET=<random>

# Upstash (bring your own)
UPSTASH_REDIS_REST_URL=
UPSTASH_REDIS_REST_TOKEN=
QSTASH_URL=
QSTASH_TOKEN=
QSTASH_CURRENT_SIGNING_KEY=
QSTASH_NEXT_SIGNING_KEY=

# Tinybird (bring your own; deploy datasources with the tb CLI first)
TINYBIRD_API_KEY=
TINYBIRD_API_URL=https://api.tinybird.co

# Storage: Cloudflare R2 / S3 (bring your own)
STORAGE_ACCESS_KEY_ID=
STORAGE_SECRET_ACCESS_KEY=
STORAGE_ENDPOINT=
STORAGE_BASE_URL=
STORAGE_PUBLIC_BUCKET=
STORAGE_PRIVATE_BUCKET=

# OAuth (at least one)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=

# Email (optional — magic-link sign-in)
RESEND_API_KEY=
```

> **Important:** every var must have a *non-empty* value present at **build time**.
> Several route modules construct SDK clients at import (e.g. Stripe), which Next
> executes during "Collecting page data" — empty values fail the build.

## Scheduled jobs (was `vercel.json` crons)

Vercel's cron definitions were removed (Railway doesn't read them). Dub depends on
~22 scheduled jobs hitting `/api/cron/*` (authenticated with `CRON_SECRET`).
Replicate the important ones with Railway cron services (or an external scheduler)
POSTing to these paths. Key schedules from the original `vercel.json`:

| Path | Schedule |
|---|---|
| `/api/cron/domains/verify` | `0 * * * *` |
| `/api/cron/streams/update-workspace-clicks` | `* * * * *` |
| `/api/cron/streams/update-workspace-links-usage` | `* * * * *` |
| `/api/cron/streams/send-link-clicked-webhooks` | `* * * * *` |
| `/api/cron/queue/retry` | `* * * * *` |
| `/api/cron/webhooks/sync-click-workspaces` | `*/5 * * * *` |
| `/api/cron/sitemaps/queue` | `0 2 * * *` |

(The full original list of 22 jobs is in this repo's git history at `apps/web/vercel.json`, commit `05c50b0`.)

## External SaaS still required

Not self-hostable in this template — the operator must provide accounts:
**Tinybird** (click analytics), **Upstash** (Redis + QStash), **R2/S3** (storage).
Optional: Resend (email), GitHub/Google OAuth.
