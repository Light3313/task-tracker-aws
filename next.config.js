/** @type {import('next').NextConfig} */
const nextConfig = {
  // Produces a minimal, self-contained server in .next/standalone — the basis for a
  // small production Docker image, copied into the runner stage of the Dockerfile.
  output: "standalone",

  // Small hardening: don't advertise the framework in the X-Powered-By header.
  poweredByHeader: false,
};

module.exports = nextConfig;
