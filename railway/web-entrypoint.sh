#!/bin/sh
# Sync the Prisma schema, then serve.
#
# This is baked into the image rather than set as a Railway pre-deploy command
# so that it survives whatever a template does or does not carry, and so it
# still runs once Config as Code stops being read.
#
# It retries because on a cold template deploy MySQL and this service start at
# the same time, and prisma exits non-zero the moment it cannot connect. Without
# the loop the only thing standing between a slow-starting database and a failed
# deploy is the restart policy, whose three attempts a connection refusal burns
# through in seconds.
#
# prisma db push is idempotent, and the template ships one replica. Raising the
# replica count would start several of these against one database at once, which
# this does not guard against.
set -e

attempts=30
i=1
while true; do
  if pnpm --filter web prisma:push -- --skip-generate; then
    break
  fi
  if [ "$i" -ge "$attempts" ]; then
    echo "[entrypoint] database unreachable after $attempts attempts, giving up" >&2
    exit 1
  fi
  echo "[entrypoint] database not ready, retrying ($i/$attempts)"
  i=$((i + 1))
  sleep 2
done

echo "[entrypoint] starting dub on port ${PORT:-3000}"
exec pnpm --filter web start
