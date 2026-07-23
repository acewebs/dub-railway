# Dub on Railway

A Railway-ready fork of [Dub](https://github.com/dubinc/dub), the open-source link management platform (short links, conversion analytics, QR codes, and affiliate/partner programs). It deploys the full Dub app as a three-service Railway project: the Dub web app, MySQL, and a PlanetScale-compatible HTTP proxy, wired together and verified to build and run on Railway.

> This fork exists to make Dub deployable on Railway. For what Dub is and its full product documentation, see the [upstream repository](https://github.com/dubinc/dub) and [dub.co](https://dub.co). The original Dub README is preserved at [docs/dub-upstream-readme.md](docs/dub-upstream-readme.md).

## Deploy

Read the [deployment guide](docs/railway-template-page.md) first. It lists the free-tier accounts and keys you need (Upstash, Tinybird, storage, and one login method) and walks through the setup. For architecture, environment variables, and Railway-specific notes, see [docs/RAILWAY.md](docs/RAILWAY.md).

## What this fork changes

Minimal, config-focused changes on top of upstream Dub (pinned at commit `05c50b0`):

- **Railway service config**: a root `railway.json` for the web app and `railway/ps-http-sim/` (Dockerfile + `railway.json`) for the proxy.
- **`next` bumped to `15.5.21`** across the workspace packages, because Railway's build scanner blocks the older flagged CVE.
- **`packages/utils/src/constants/main.ts`**: `NEXT_PUBLIC_APP_DOMAIN` now makes the deployment's own domain the app/dashboard domain, so self-hosted deployments work on any domain (unset preserves upstream dub.co behavior).
- **`apps/web/vercel.json` removed** (Vercel-only).

Everything else is stock Dub.

## Docs

- [docs/railway-template-page.md](docs/railway-template-page.md): deployment guide (accounts, keys, step-by-step setup).
- [docs/RAILWAY.md](docs/RAILWAY.md): architecture, environment variables, and Railway-specific gotchas.
- [docs/dub-upstream-readme.md](docs/dub-upstream-readme.md): the original Dub README.

## License

Same as upstream Dub: [AGPL-3.0](LICENSE.md).
