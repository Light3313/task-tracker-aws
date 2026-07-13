import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

// LIVENESS: is the process up and able to answer? No dependencies checked on purpose.
// Used as a Kubernetes livenessProbe and as a basic load-balancer health check.
// If this fails, the orchestrator restarts the container.
export async function GET() {
  return NextResponse.json({ status: "ok" });
}
