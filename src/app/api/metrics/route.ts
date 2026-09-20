import { registry } from "@/lib/metrics";
import { withRequestLog } from "@/lib/request-log";

export const dynamic = "force-dynamic";

// Prometheus scrape target. Exposes default Node/process metrics plus
// http_requests_total. In a production cluster this would be network-segmented
// (scrape-only); here it's exposed so a local Prometheus / kube-prometheus-stack
// can scrape it.
async function scrape() {
  const body = await registry.metrics();
  return new Response(body, {
    headers: { "Content-Type": registry.contentType },
  });
}

export const GET = withRequestLog("/api/metrics", scrape, { quiet: true });
