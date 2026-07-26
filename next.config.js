/** @type {import('next').NextConfig} */
const nextConfig = {
  // Produces a minimal, self-contained server in .next/standalone — the basis for a
  // small production Docker image, copied into the runner stage of the Dockerfile.
  output: "standalone",

  // Small hardening: don't advertise the framework in the X-Powered-By header.
  poweredByHeader: false,

  // The app renders no next/image components, so the built-in image optimizer is
  // unused. Disabling it means the optimizer route never runs, so sharp is never
  // required at runtime.
  images: {
    unoptimized: true,
  },

  // The optimizer being disabled, sharp and its libvips native bindings are dead
  // weight. The file tracer still statically pulls them in, so exclude them
  // explicitly — smaller image, smaller attack surface.
  outputFileTracingExcludes: {
    "*": [
      "node_modules/.pnpm/sharp@*/**",
      "node_modules/.pnpm/@img+*/**",
      "node_modules/.pnpm/typescript@*/**",
      "node_modules/.pnpm/caniuse-lite@*/**",
    ],
  },

  // Keep the AWS SDK external instead of webpack-bundled. Not because inline bundling
  // was proven to break (a local test of the env-credential path worked bundled) — but
  // as defense-in-depth: it removes the whole dynamic-require risk class, covers the
  // IMDS credential path that can't be exercised outside EC2, and matches how Next
  // already treats `pg`. The SDK is then traced into standalone/node_modules like any dep.
  serverExternalPackages: ["@aws-sdk/rds-signer", "@aws-sdk/client-ssm"],
};

module.exports = nextConfig;
