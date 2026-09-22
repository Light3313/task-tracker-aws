import { AsyncLocalStorage } from "node:async_hooks";
import type { NextRequest } from "next/server";
import { logger } from "./logger";

type RequestState = { dbMs: number; reqId?: string; ip?: string };

// Request-scoped, so db.ts can add its timing without every handler passing a counter down.
const state = new AsyncLocalStorage<RequestState>();

export function addDbTime(ms: number): void {
  const current = state.getStore();
  if (current) current.dbMs += ms;
}

// The ALB appends the address it saw to any X-Forwarded-For the client sent
// (routing.http.xff_header_processing.mode = append, the default), so the LAST entry is the
// balancer's and every earlier one is whatever the client chose to claim. Take the last, or a
// brute-force count groups by an attacker-supplied string.
// With routing.http.xff_client_port.enabled the entry becomes ip:port (IPv6: [ip]:port).
function clientIp(req: NextRequest): string | undefined {
  const entries = (req.headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  const last = entries.at(-1);
  if (!last) return undefined;

  const bracketed = last.match(/^\[(.+)\]/); // IPv6 with the port appended
  if (bracketed) return bracketed[1];
  // Strip a trailing :port on IPv4 only — a bare IPv6 address is all colons.
  return last.replace(/^(\d+\.\d+\.\d+\.\d+):\d+$/, "$1");
}

// For log lines written outside the request line itself (login_failed and the like), so they
// carry the same two keys and join to it instead of floating free.
export function requestFields(): { reqId?: string; ip?: string } {
  const current = state.getStore();
  return current ? { reqId: current.reqId, ip: current.ip } : {};
}

type Handler<C> = (req: NextRequest, ctx: C) => Promise<Response> | Response;

type Options = {
  // Health checks fire every few seconds -> info would bury everything else.
  quiet?: boolean;
};

function levelFor(status: number, failed: boolean, quiet: boolean) {
  if (failed || status >= 500) return "error" as const;
  if (status >= 400) return "warn" as const;
  return quiet ? ("debug" as const) : ("info" as const);
}

// One JSON line per request: what was asked, what came back, how long, how much of it was the DB.
// reqId is the ALB's X-Amzn-Trace-Id — the same value lands in the ALB access log, so a 5xx
// seen on the balancer can be joined to what the app was doing.
export function withRequestLog<C>(
  route: string,
  handler: Handler<C>,
  options: Options = {},
): Handler<C> {
  return async (req, ctx) => {
    const started = performance.now();
    const current: RequestState = {
      dbMs: 0,
      reqId: req.headers.get("x-amzn-trace-id") ?? undefined,
      ip: clientIp(req),
    };

    return state.run(current, async () => {
      let status = 500;
      let failed = false;

      try {
        const res = await handler(req, ctx);
        status = res.status;
        return res;
      } catch (err) {
        failed = true;
        logger.error({ event: "request_failed", route, err }, "unhandled error");
        throw err;
      } finally {
        logger[levelFor(status, failed, options.quiet ?? false)](
          {
            event: "request",
            reqId: current.reqId,
            ip: current.ip,
            method: req.method,
            route,
            status,
            durMs: Math.round(performance.now() - started),
            dbMs: Math.round(current.dbMs),
          },
          "request",
        );
      }
    });
  };
}
