// Minimal migration runner: applies db/schema.sql once.
// Real projects use a migration tool (e.g. node-pg-migrate, Prisma, Flyway). This is
// intentionally tiny — the point of this repo is the infra around the app, not the app.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import pg from "pg";

const here = dirname(fileURLToPath(import.meta.url));

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("DATABASE_URL is not set — copy .env.example to .env or export it.");
  process.exit(1);
}

const sql = readFileSync(join(here, "..", "db", "schema.sql"), "utf8");
const client = new pg.Client({ connectionString: databaseUrl });

try {
  await client.connect();
  await client.query(sql);
  console.log("Schema applied successfully.");
} catch (err) {
  console.error("Migration failed:", err.message);
  process.exit(1);
} finally {
  await client.end();
}
