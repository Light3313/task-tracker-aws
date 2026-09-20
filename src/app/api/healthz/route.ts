import { NextResponse } from "next/server";
import { withRequestLog } from "@/lib/request-log";

export const dynamic = "force-dynamic";

// LIVENESS: is the process up and able to answer? No dependencies checked on purpose.
// Used as a Kubernetes livenessProbe and as a basic load-balancer health check.
// If this fails, the orchestrator restarts the container.
async function liveness() {
  return NextResponse.json({ status: "ok" });
}

export const GET = withRequestLog("/api/healthz", liveness, { quiet: true });
