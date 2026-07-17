import { Pool, type PoolConfig } from "pg";
import { Signer } from "@aws-sdk/rds-signer";
import { config } from "./config";

// Lazy singleton pool. Created on first query (request time), not at import time,
// so `next build` doesn't try to open a DB connection.
let pool: Pool | undefined;

// Two credential strategies, selected by environment:
//   - DATABASE_URL present -> local/dev: plain connection string, password auth, no TLS.
//   - DATABASE_URL absent   -> AWS: IAM database authentication. No stored password —
//     a short-lived (~15 min) token is minted per new physical connection from the
//     instance role's IMDS credentials, and TLS is mandatory.
function buildPoolConfig(): PoolConfig {
  const url = config.databaseUrl;
  if (url) {
    return { connectionString: url, max: 10 };
  }

  const signer = new Signer({
    hostname: config.pgHost,
    port: config.pgPort,
    username: config.pgUser,
    region: config.awsRegion,
  });

  return {
    host: config.pgHost,
    port: config.pgPort,
    user: config.pgUser,
    database: config.pgDatabase,
    max: 10,
    // pg calls this for every NEW physical connection -> always a fresh token.
    // The token only needs to be valid at connect time; an established socket
    // outlives the token's 15-min window, so pooled connections are not disrupted.
    password: () => signer.getAuthToken(),
    // IAM auth requires TLS. rejectUnauthorized:false encrypts without pinning the RDS
    // CA — acceptable inside the VPC; pin the RDS global CA bundle for verify-full in prod.
    ssl: { rejectUnauthorized: false },
  };
}

export function getPool(): Pool {
  if (!pool) {
    pool = new Pool(buildPoolConfig());
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
