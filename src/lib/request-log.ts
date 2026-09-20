import { AsyncLocalStorage } from "node:async_hooks";
import type { NextRequest } from "next/server";
import { logger } from "./logger";

type RequestState = { dbMs: number };

// Request-scoped, so db.ts can add its timing without every handler passing a counter down.
const state = new AsyncLocalStorage<RequestState>();

export function addDbTime(ms: number): void {
  const current = state.getStore();
  if (current) current.dbMs += ms;
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
    const current: RequestState = { dbMs: 0 };

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
            reqId: req.headers.get("x-amzn-trace-id") ?? undefined,
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
