import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { withRequestLog } from "@/lib/request-log";

export const dynamic = "force-dynamic";

// READINESS: can we actually serve traffic right now? Checks the DB dependency.
// Returns 503 when the DB is unreachable so the load balancer / K8s readinessProbe
// stops routing requests here until it recovers — without restarting the container.
// The liveness vs readiness distinction is a classic interview/ops point.
async function readiness() {
  try {
    await query("SELECT 1");
    return NextResponse.json({ status: "ready" });
  } catch {
    return NextResponse.json(
      { status: "not-ready", reason: "database unreachable" },
      { status: 503 },
    );
  }
}

export const GET = withRequestLog("/api/readyz", readiness, { quiet: true });
