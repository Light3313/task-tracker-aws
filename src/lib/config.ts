// 12-factor config: everything comes from the environment, read lazily and validated
// on first use. Fail fast with a clear message if a REQUIRED variable is missing —
// far easier to diagnose in a container/K8s pod than a vague crash deep in a request.
//
// Lazy getters (not eager constants) so that `next build` — which imports modules
// without runtime env present — does not blow up. Validation happens at request time.

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  get databaseUrl(): string {
    return required("DATABASE_URL");
  },
  get sessionSecret(): string {
    return required("SESSION_SECRET");
  },
  get port(): number {
    return parseInt(process.env.PORT ?? "3000", 10);
  },
  get logLevel(): string {
    return process.env.LOG_LEVEL ?? "info";
  },
};
