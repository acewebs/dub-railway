# Deploy and Host Dub on Railway

Dub is the open-source link management platform for modern marketing teams to create, share, and track short links. It offers branded custom domains, real-time click and conversion analytics, QR codes, and affiliate/partner program tracking. It is a self-hostable, developer-friendly alternative to Bitly, built on Next.js.

## About Hosting Dub

Dub is a Next.js monorepo (pnpm/Turborepo) that reads and writes through both Prisma (MySQL wire protocol) and the PlanetScale serverless HTTP driver, so it needs a MySQL database plus a small PlanetScale-compatible HTTP proxy in front of it. It also relies on Upstash Redis and QStash for caching and background jobs, Tinybird for click analytics, and S3-compatible object storage for image assets. This template provisions three Railway services (the Dub web app, MySQL, and the ps-http-sim proxy) already wired together, and generates the app secrets for you. You supply credentials for a few external services as environment variables, and the build compiles the monorepo, syncs the database schema, and starts the app.

## Common Use Cases

- Branded short links and custom-domain link management for marketing and growth teams
- Real-time click and conversion analytics to attribute traffic across campaigns
- Affiliate and partner program tracking with Dub Partners

## Dependencies for Dub Hosting

Provisioned automatically by this template (nothing to configure):

- A MySQL 8 database
- A PlanetScale-compatible HTTP proxy (ps-http-sim) for Dub's serverless-driver queries
- App secrets (NextAuth secret, encryption key, cron secret) and all database wiring

You bring accounts for (all have free tiers):

- Upstash: Redis (caching) and QStash (background jobs and queues)
- Tinybird: time-series click analytics
- Object storage: Cloudflare R2 or AWS S3 (or self-host MinIO on Railway)
- One login method: a GitHub or Google OAuth app, or Resend for email login

### Deployment Dependencies

Create these accounts and copy the listed values into the web service's variables. Upstash, Tinybird, and storage can be set up any time; the OAuth callback needs your deployed domain, so create the login app after the first deploy.

**Upstash (Redis + QStash)** - sign up at [console.upstash.com](https://console.upstash.com)
- Create a Redis database, open its "REST API" section, and copy `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`.
- Open "QStash" in the sidebar and copy `QSTASH_URL`, `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, and `QSTASH_NEXT_SIGNING_KEY`.

**Tinybird (analytics)** - sign up at [tinybird.co](https://www.tinybird.co)
- Create a workspace and note its region host for `TINYBIRD_API_URL` (for example `https://api.tinybird.co`).
- Under "Tokens", copy the workspace admin token into `TINYBIRD_API_KEY`.
- After deploying, push Dub's datasources from `packages/tinybird` with the Tinybird CLI so analytics has somewhere to write.

**Object storage (Cloudflare R2)** - [Cloudflare dashboard](https://dash.cloudflare.com) then R2
- A payment method is required to enable R2 even on the free tier. Create two buckets, one public and one private.
- On the public bucket, enable public access and copy its URL into `STORAGE_BASE_URL`.
- Under "Manage R2 API Tokens", create a token with Object Read and Write, then copy the Access Key ID, Secret Access Key, and S3 endpoint into `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY`, and `STORAGE_ENDPOINT`. Set `STORAGE_PUBLIC_BUCKET` and `STORAGE_PRIVATE_BUCKET` to the two bucket names.
- Prefer no external account? Deploy a MinIO service on Railway and point the same `STORAGE_*` variables at it.

**One login method (pick one)**
- GitHub OAuth: at [github.com/settings/developers](https://github.com/settings/developers), create an OAuth App with the Authorization callback URL `https://<your-domain>/api/auth/callback/github`, then copy `GITHUB_CLIENT_ID` and generate `GITHUB_CLIENT_SECRET`. Easiest option, no email service needed.
- Google OAuth: the same idea, setting `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
- Resend for magic-link email: get an API key at [resend.com/api-keys](https://resend.com/api-keys) and set `RESEND_API_KEY`.

Reference: [Dub self-hosting guide](https://dub.co/docs/self-hosting) and [Dub source](https://github.com/dubinc/dub).

### Implementation Details

The template wires all database, domain, and secret variables for you (`DATABASE_URL`, `DATABASE_URL_BUILD`, `PLANETSCALE_DATABASE_URL`, `NEXT_PUBLIC_APP_DOMAIN`, `NEXTAUTH_URL`, and the generated secrets). The MySQL and proxy services need no configuration.

Getting started:
1. Click Deploy and let the three services build. MySQL and the proxy come up on their own.
2. Create your Upstash, Tinybird, and storage accounts, and a login app (using the deployed domain for the OAuth callback). Add all the variables above to the web service and redeploy.
3. Open your Railway domain and sign in. The dashboard is served on the deployment's own domain out of the box, because the template sets `NEXT_PUBLIC_APP_DOMAIN` to it.
4. To use a custom domain, add it in Railway and set `NEXT_PUBLIC_APP_DOMAIN` to that hostname. `NEXTAUTH_URL` follows automatically.
5. Push the Tinybird datasources from `packages/tinybird` to enable click analytics.

Notes:
- You must configure at least one login method. OAuth (GitHub or Google) needs only a free app; magic-link and email-plus-password both send email, so they need Resend or SMTP.
- Two Stripe and two Upstash Vector variables ship with harmless placeholder values so the build succeeds. Replace them only if you want Dub's billing or AI features.

## Why Deploy Dub on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Dub on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
