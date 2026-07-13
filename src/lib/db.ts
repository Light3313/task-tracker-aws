import { Pool } from "pg";
import { config } from "./config";

// Lazy singleton pool. Created on first query (request time), not at import time,
// so `next build` doesn't try to open a DB connection.
let pool: Pool | undefined;

export function getPool(): Pool {
  if (!pool) {
    pool = new Pool({
      connectionString: config.databaseUrl,
      max: 10,
      // PRODUCTION TODO: enforce TLS to RDS, e.g.
      //   ssl: { rejectUnauthorized: true, ca: fs.readFileSync('rds-ca.pem') }
      // Left off for local dev where Postgres has no TLS.
    });
  }
  return pool;
}

// All queries are parameterized ($1, $2, ...) — never string-concatenated.
// This is what keeps SQL injection off the table (and a SAST scan quiet).
export async function query<T = Record<string, unknown>>(
  text: string,
  params?: unknown[],
): Promise<T[]> {
  const res = await getPool().query(text, params);
  return res.rows as T[];
}
