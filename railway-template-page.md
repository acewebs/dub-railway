# Deploy and Host Dub on Railway

Dub is the open-source link management platform for modern marketing teams to create, share, and track short links. It provides branded custom domains, real-time click and conversion analytics, QR codes, and affiliate/partner program tracking — a self-hostable, developer-friendly alternative to Bitly, built on Next.js.

## About Hosting Dub

Dub is a Next.js monorepo (pnpm/Turborepo). Self-hosting it means more than running one container: the app reads and writes through both Prisma (MySQL wire protocol) and the `@planetscale/database` serverless HTTP driver, so it needs a MySQL database *and* a small PlanetScale-compatible HTTP proxy in front of it. It also depends on Upstash Redis and QStash for caching and background jobs, Tinybird for click analytics, and S3-compatible object storage for image assets. On Railway this becomes a three-service project — the Dub web app, a MySQL database, and a `ps-http-sim` proxy — with the external SaaS dependencies supplied as environment variables. The build compiles the full monorepo, syncs the Prisma schema, and starts the Next.js server.

## Common Use Cases

- Branded short links and custom-domain link management for marketing and growth teams
- Real-time click and conversion analytics to attribute traffic across campaigns
- Affiliate and partner program link tracking with Dub Partners

## Dependencies for Dub Hosting

- A MySQL 8 database (Prisma schema, `relationMode="prisma"`, no foreign keys)
- A PlanetScale HTTP proxy (`ps-http-sim`) in front of MySQL, for Dub's serverless-driver queries
- Upstash Redis + QStash (link caching and background jobs/queues)
- Tinybird (time-series click analytics)
- S3-compatible object storage (Cloudflare R2 or AWS S3) for image assets

### Deployment Dependencies

- [Dub self-hosting guide](https://dub.co/docs/self-hosting)
- [Dub source (dubinc/dub)](https://github.com/dubinc/dub)
- [ps-http-sim (PlanetScale HTTP simulator)](https://github.com/mattrobenolt/ps-http-sim)
- [Upstash (Redis + QStash)](https://upstash.com)
- [Tinybird](https://www.tinybird.co)
- [Cloudflare R2](https://developers.cloudflare.com/r2/)

### Implementation Details

The database is wired two ways — Prisma over the MySQL wire protocol, and the serverless driver over HTTP to the proxy:

```bash
DATABASE_URL=${{MySQL.MYSQL_URL}}
PLANETSCALE_DATABASE_URL=http://root:unused@planetscale-proxy.railway.internal:3900/railway
```

The `planetscale-proxy` service runs `ghcr.io/mattrobenolt/ps-http-sim`, pointed at the MySQL service, exposing the PlanetScale HTTP protocol on port 3900. The web service builds the monorepo with an increased Node heap (`NODE_OPTIONS=--max-old-space-size=8192`) and runs `prisma db push` before starting. Note: pin `next` to a current patch release — Railway's build scanner blocks HIGH-severity dependency CVEs, and older `next` versions in the lockfile are flagged. External accounts (Tinybird, Upstash, R2) are supplied via environment variables.

## Why Deploy Dub on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Dub on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
