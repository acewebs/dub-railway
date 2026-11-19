# Deploy and Host Dub: Self-Hosted Link Management on Railway

Dub is an open-source link management and attribution platform: branded short links on your own domains, QR codes, click and conversion tracking, and affiliate programs through Dub Partners. It is a developer-friendly, self-hostable alternative to Bitly, built on Next.js. This template runs it on Railway with its own MySQL database.

## About Hosting Dub: Self-Hosted Link Management

Dub reaches its database two ways at once, Prisma over the MySQL wire protocol and the PlanetScale serverless HTTP driver, so self-hosting it needs a MySQL database plus a PlanetScale-compatible HTTP proxy in front of it. This template provisions all three services and wires them together: private networking, the database connection, the generated application domain, and fresh NextAuth, encryption and cron secrets. The Prisma schema is synced during deployment, so there is no manual migration step. You supply credentials for the external services Dub uses for caching, queues, analytics and file storage.

## Common Use Cases

- Branded short links on your own domains for marketing and growth campaigns
- Click and conversion attribution across channels, with a QR code per link
- Affiliate and partner programs run through Dub Partners

## Dependencies for Dub: Self-Hosted Link Management Hosting

Provisioned by the template, with nothing to configure:

- MySQL 9.4 on a persistent volume
- ps-http-sim, the PlanetScale-compatible HTTP proxy Dub's serverless driver talks to
- The app secrets and every database, domain and networking variable

You bring accounts for these, all of which have free tiers:

- Upstash Redis for caching and redirects, and Upstash QStash for background jobs
- Tinybird for click analytics
- S3-compatible object storage: Cloudflare R2, Amazon S3, or a MinIO service on Railway
- One login method: a GitHub or Google OAuth app, or Resend for email magic links

### Implementation Details

**Upstash** (console.upstash.com). Create a Redis database and copy `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` from its REST API section. Open QStash in the sidebar for `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY` and `QSTASH_NEXT_SIGNING_KEY`.

**Tinybird** (tinybird.co). Create a workspace, set `TINYBIRD_API_URL` to its region host and `TINYBIRD_API_KEY` to the workspace admin token, then push the datasources from `packages/tinybird` with the Tinybird CLI. Analytics has nowhere to write until those exist.

**Object storage** (Cloudflare R2, S3, or MinIO). Create a public and a private bucket, then set `STORAGE_ENDPOINT`, `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY`, `STORAGE_PUBLIC_BUCKET`, `STORAGE_PRIVATE_BUCKET` and `STORAGE_BASE_URL` (the public bucket's URL). R2 needs a payment method on file even on the free tier.

**Login.** OAuth is the simplest, since it needs no email service. The callback URL contains your deployed domain, so create the OAuth app after the first deploy: `https://your-domain.example/api/auth/callback/github`, then set `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` (or the Google pair, or `RESEND_API_KEY` for magic links).

Getting started:

1. Click Deploy and let the three services build.
2. Open the generated Railway domain to get your hostname.
3. Create the OAuth app using that hostname in the callback URL.
4. Add the Upstash, Tinybird, storage and login variables to the Dub service.
5. Redeploy the Dub service, then open the domain and sign in.

To use your own domain, add it to the Dub service and set `NEXT_PUBLIC_APP_DOMAIN` to that hostname; `NEXTAUTH_URL` follows automatically. The branded short-link domains you hand out to users are added inside Dub itself, separately from this one.

Worth knowing before you commit to it:

- This is a Railway-ready fork of Dub, not an auto-updating deployment of the latest upstream release.
- New Tinybird signups get Forward workspaces, but Dub's datasources still use the Classic `tb push` flow. Use a Classic workspace or port them to `tb deploy`.
- Country and city analytics come from Vercel-specific geolocation helpers and stay empty off Vercel. Clicks and the rest of the metadata are still recorded.
- Dub's scheduled `/api/cron/*` jobs are not created for you. Add Railway cron services for the ones you need and authenticate them with `CRON_SECRET`.
- Stripe billing and Upstash Vector ship with placeholder values so the build passes. Replace them only to enable those features.
- Dub is licensed under AGPL-3.0: a modified version offered over a network may oblige you to publish your changes. This template is community-maintained and is not affiliated with or endorsed by Dub.

## Why Deploy Dub: Self-Hosted Link Management on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Dub: Self-Hosted Link Management on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
