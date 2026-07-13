import client from "prom-client";

// A single shared Prometheus registry. prom-client's default metrics cover
// process/Node internals (event-loop lag, heap, GC, open FDs). We add one custom
// HTTP counter. Exposed at GET /api/metrics for a Prometheus scrape.
//
// The globalThis stash prevents duplicate metric registration during Next.js dev
// hot-reload (modules get re-evaluated; metrics must not be re-created).
const g = globalThis as unknown as {
  __registry?: client.Registry;
  __httpRequests?: client.Counter<string>;
};

export const registry: client.Registry =
  g.__registry ??
  (() => {
    const r = new client.Registry();
    client.collectDefaultMetrics({ register: r });
    g.__registry = r;
    return r;
  })();

export const httpRequests: client.Counter<string> =
  g.__httpRequests ??
  (() => {
    const c = new client.Counter({
      name: "http_requests_total",
      help: "Total HTTP requests handled by the app",
      labelNames: ["method", "route", "status"],
      registers: [registry],
    });
    g.__httpRequests = c;
    return c;
  })();
