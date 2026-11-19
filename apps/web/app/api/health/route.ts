import { prisma } from "@/lib/prisma";
import { prismaEdge } from "@/lib/prisma/edge";
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

// Readiness probe for self-hosted deployments. Dub reads through two separate
// database paths, Prisma over the MySQL wire protocol and the PlanetScale HTTP
// driver, and a misconfigured proxy leaves the process up while most of the app
// fails, so probe both rather than reporting liveness.
export async function GET() {
  let database = false;
  let planetscaleProxy = false;

  // allSettled covers the queries rejecting; the try covers either client
  // throwing before it returns a promise, which would otherwise answer the
  // probe with Next's generic error page instead of a readiness verdict.
  try {
    [database, planetscaleProxy] = (
      await Promise.allSettled([
        prisma.$queryRaw`SELECT 1`,
        prismaEdge.$queryRaw`SELECT 1`,
      ])
    ).map((result) => result.status === "fulfilled");
  } catch {
    // both stay false
  }

  const ready = database && planetscaleProxy;

  return NextResponse.json(
    { status: ready ? "ok" : "degraded", database, planetscaleProxy },
    { status: ready ? 200 : 503 },
  );
}
