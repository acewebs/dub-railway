# Deploying Dub on Railway

This branch is a Railway-ready fork of [dubinc/dub](https://github.com/dubinc/dub),
verified to build and run on Railway (Node 23.11.0 / pnpm 9.15.9).

## Architecture — 3 Railway services

| Service | Source | Role |
|---|---|---|
| **web** | this repo, `railway-template` branch (root dir) | the Dub Next.js app (`apps/web`) |
| **MySQL** | Railway MySQL (one-click) | primary database (db name `railway`) |
| **planetscale-proxy** | this repo, root dir `railway/ps-http-sim` (Dockerfile) | HTTP shim so Dub's `@planetscale/database` driver can talk to plain MySQL |

Dub talks to the database two ways — Prisma over the MySQL wire protocol
(`DATABASE_URL`) and the PlanetScale serverless HTTP driver
(`PLANETSCALE_DATABASE_URL` → the proxy). Both are mandatory.

### planetscale-proxy

The upstream `ghcr.io/mattrobenolt/ps-http-sim` image is **shell-less (scratch)**,
so it can't read env vars in a Railway start command. `railway/ps-http-sim/Dockerfile`
wraps its static binary on alpine and reads the MySQL connection from env vars.
Set these service variables (references to the MySQL service):

```
MYSQLHOST=${{MySQL.MYSQLHOST}}
MYSQLPORT=${{MySQL.MYSQLPORT}}
MYSQLDATABASE=${{MySQL.MYSQLDATABASE}}
MYSQLUSER=${{MySQL.MYSQLUSER}}
MYSQLPASSWORD=${{MySQL.MYSQLPASSWORD}}
```

## Build / run (handled by `railway.json`)

- Build: `NODE_OPTIONS=--max-old-space-size=8192 pnpm build` — the heap bump is
  required; the default Node heap OOMs during `next build`.
- Pre-deploy: `pnpm --filter web prisma:push` — syncs the schema.
- Start: `pnpm --filter web start`.
- Node pinned via `.nvmrc` (23.11.0).

## Railway-specific gotchas (all learned the hard way — keep these)

1. **Build security scanner blocks HIGH-severity CVEs.** Railway hard-blocks the
   build if any **direct** dependency in `pnpm-lock.yaml` has a HIGH/critical CVE,
   with no opt-out. `next` was flagged (CVE-2025-67779). You must bump it in
   **every** workspace package that pins it (here: `apps/web`, `@dub/ui`,
   `@dub/utils` — deps *and* peers) so no old version remains in the lockfile.
   Pinned to `next@15.5.21`. `pnpm audit` is **not** a reliable predictor of this
   scanner (different DB, false positives) — the scanner only flags direct deps.
2. **Build-time env for import-time SDK clients.** Several route modules construct
   SDK clients at import (Stripe), which Next executes during "Collecting page
   data". Every referenced key must be **non-empty at build time**, even if unused:
   `STRIPE_SECRET_KEY`, `STRIPE_APP_SECRET_KEY`, `STRIPE_APP_SECRET_KEY_TEST`,
   `STRIPE_APP_SECRET_KEY_SANDBOX` (dummy values are fine for a build).
3. **Secrets baked into image layers.** Nixpacks declares all service variables as
   `ARG`/`ENV` in its generated Dockerfile, so secrets land in image layers
   (BuildKit warns `SecretsUsedInArgOrEnv`). The image is private to the project;
   keep it private and rotate secrets. Not fully fixable without leaving Nixpacks.
4. **Redeploy ≠ latest commit.** Railway's Redeploy re-runs a deployment's exact
   commit. To deploy the newest branch commit use "Deploy Latest Commit" (Cmd/Ctrl+K)
   or push. Making `railway-template` the repo's **default branch** avoids drift.

## Required environment variables (web service)

```bash
# Database
DATABASE_URL=${{MySQL.MYSQL_URL}}
PLANETSCALE_DATABASE_URL=http://root:unused@planetscale-proxy.railway.internal:3900/railway

# App / auth
NEXTAUTH_URL=https://<your-app-domain>
NEXTAUTH_SECRET=<openssl rand -base64 32>
NEXT_PUBLIC_APP_DOMAIN=<your-app-domain>
ENCRYPTION_KEY=<32-byte base64>   # must decode to exactly 32 bytes
CRON_SECRET=<random>
UNSUBSCRIBE_TOKEN_SECRET=<random>

# Upstash (bring your own)
UPSTASH_REDIS_REST_URL= ; UPSTASH_REDIS_REST_TOKEN=
QSTASH_URL= ; QSTASH_TOKEN= ; QSTASH_CURRENT_SIGNING_KEY= ; QSTASH_NEXT_SIGNING_KEY=

# Tinybird (bring your own; see caveat below)
TINYBIRD_API_KEY= ; TINYBIRD_API_URL=https://api.tinybird.co

# Storage: Cloudflare R2 / S3 (bring your own)
STORAGE_ACCESS_KEY_ID= ; STORAGE_SECRET_ACCESS_KEY= ; STORAGE_ENDPOINT=
STORAGE_BASE_URL= ; STORAGE_PUBLIC_BUCKET= ; STORAGE_PRIVATE_BUCKET=

# Auth providers (GitHub OAuth callback must be https://<domain>/api/auth/callback/github)
GITHUB_CLIENT_ID= ; GITHUB_CLIENT_SECRET=

# Stripe — dummy non-empty values needed at BUILD time (see gotcha #2)
STRIPE_SECRET_KEY= ; STRIPE_APP_SECRET_KEY= ; STRIPE_APP_SECRET_KEY_TEST= ; STRIPE_APP_SECRET_KEY_SANDBOX=
```

## Known limitations / caveats

- **Tinybird "Forward" workspaces:** new Tinybird signups are Forward workspaces,
  but Dub's `packages/tinybird` uses the Classic `tb push` flow. Analytics
  datasources won't deploy out-of-the-box on a Forward workspace — use a Classic
  workspace or port the datasources to Forward's `tb deploy`.
- **Production login:** dev logs the magic link to the console; on Railway you need
  Resend configured for magic-link email, or use GitHub/Google OAuth.
- **Geo/IP analytics:** `record-click` uses `@vercel/functions` geolocation/ipAddress,
  which return empty off-Vercel. Clicks record without country/city.
- **Scheduled jobs:** the original `apps/web/vercel.json` crons were removed; Dub's
  `/api/cron/*` jobs need replicating via Railway cron (auth with `CRON_SECRET`).
