/** @type {import('next').NextConfig} */
const nextConfig = {
  // Produces a minimal, self-contained server in .next/standalone — the basis for a
  // small production Docker image, copied into the runner stage of the Dockerfile.
  output: "standalone",

  // Small hardening: don't advertise the framework in the X-Powered-By header.
  poweredByHeader: false,

  // Keep the AWS SDK external instead of webpack-bundled. Not because inline bundling
  // was proven to break (a local test of the env-credential path worked bundled) — but
  // as defense-in-depth: it removes the whole dynamic-require risk class, covers the
  // IMDS credential path that can't be exercised outside EC2, and matches how Next
  // already treats `pg`. The SDK is then traced into standalone/node_modules like any dep.
  serverExternalPackages: ["@aws-sdk/rds-signer"],
};

module.exports = nextConfig;
