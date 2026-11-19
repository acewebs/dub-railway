# Dub on Railway.
#
# A Railway template cannot carry a build command (the only build setting a
# template holds is the builder), so everything the build needs lives here
# rather than in railway.json. Config as Code stops being read on 2026-12-01.
#
# The build runs its own throwaway MariaDB rather than reaching the deployed
# database. next build queries the database while collecting page data, and the
# Railway builder cannot reach the private network, so the alternative is
# pointing the build at MySQL's public TCP proxy: a public hostname in a
# service-to-service variable, which fails Railway's private networking
# guideline, and a build that breaks whenever that proxy is missing. The
# queries hit empty tables either way, so an empty local database is equivalent.
# The real database gets its schema from the entrypoint on first boot.

FROM node:23.11.0-slim AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates mariadb-server \
  && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile

# Railway populates an ARG from the service variable of the same name, and
# every ARG value is readable from the image's history afterwards. So the only
# variable declared here is the one the build genuinely needs and that is not a
# secret: NEXT_PUBLIC_APP_DOMAIN is inlined into the client bundle, and a build
# without it serves "Link Not Found" on the dashboard.
ARG NEXT_PUBLIC_APP_DOMAIN

# These are set, never declared as ARGs, so a deployer's real Stripe or Upstash
# credentials cannot be captured into image history by enabling those features.
# The build only needs them non-empty: their SDK clients are constructed at
# import time and throw on an empty value while next build collects page data.
# This stage's ENV does not reach the runtime stage, which reads the real values
# from the environment at startup.
ENV STRIPE_SECRET_KEY=sk_test_dummy_for_build_only \
    STRIPE_APP_SECRET_KEY=sk_test_dummy_for_build_only \
    STRIPE_APP_SECRET_KEY_TEST=sk_test_dummy_for_build_only \
    STRIPE_APP_SECRET_KEY_SANDBOX=sk_test_dummy_for_build_only \
    UPSTASH_VECTOR_REST_URL=https://dummy-vector.upstash.io \
    UPSTASH_VECTOR_REST_TOKEN=dummy_build_only_token

# One layer, because the database only exists for the length of it. The 8 GB
# heap avoids an OOM in next build, and .next/cache is 4 GB of webpack cache
# that nothing reads at runtime, so it goes before the layer is committed.
RUN set -eu; \
    mkdir -p /run/mysqld; \
    mariadb-install-db --user=root --datadir=/var/lib/mysql >/dev/null; \
    mariadbd --user=root --datadir=/var/lib/mysql \
      --socket=/run/mysqld/mysqld.sock --port=3306 --bind-address=127.0.0.1 & \
    up=0; \
    for i in $(seq 1 60); do \
      if mariadb --socket=/run/mysqld/mysqld.sock -uroot -e "SELECT 1" >/dev/null 2>&1; then up=1; break; fi; \
      sleep 1; \
    done; \
    if [ "$up" -ne 1 ]; then \
      echo "build database did not accept connections within 60s" >&2; exit 1; \
    fi; \
    mariadb --socket=/run/mysqld/mysqld.sock -uroot -e "\
      CREATE DATABASE railway; \
      CREATE USER 'dub'@'%' IDENTIFIED BY 'dub'; \
      GRANT ALL ON *.* TO 'dub'@'%';"; \
    export DATABASE_URL="mysql://dub:dub@127.0.0.1:3306/railway"; \
    pnpm --filter web prisma:push; \
    NODE_OPTIONS=--max-old-space-size=8192 pnpm build; \
    mariadb-admin --socket=/run/mysqld/mysqld.sock -uroot shutdown; \
    rm -rf apps/web/.next/cache apps/web/.next/trace apps/web/.next/types

# Separate stage so the build's database server stays out of the shipped image.
FROM node:23.11.0-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Resolve pnpm at build time into a location every user can read. Left to
# corepack's default, the first pnpm call downloads the tarball from
# registry.npmjs.org, making every container start depend on the npm registry.
ENV COREPACK_HOME=/usr/local/share/corepack
RUN corepack enable && corepack prepare pnpm@9.15.9 --activate

WORKDIR /app
COPY --from=build --chown=node:node /app /app
COPY railway/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh

USER node
ENTRYPOINT ["/usr/local/bin/web-entrypoint.sh"]
