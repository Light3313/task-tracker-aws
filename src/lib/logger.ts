import pino from "pino";
import { config } from "./config";

// Structured JSON logs to stdout — exactly the shape CloudWatch Logs Insights and
// ELK/Loki ingest and query. Do NOT pretty-print inside the app:
// keep raw JSON in containers. Locally, pipe through pino-pretty if you want:
//   npm run dev | npx pino-pretty
export const logger = pino({
  level: config.logLevel,
  // Defense in depth: if a secret ever slips into a logged object, redact it.
  redact: [
    "password",
    "password_hash",
    "req.headers.cookie",
    "req.headers.authorization",
  ],
});
