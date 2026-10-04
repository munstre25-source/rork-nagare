import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

const configDir = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  outputFileTracingRoot: configDir,
  async redirects() {
    return [{ source: "/", destination: "/hq", permanent: false }];
  },
};

export default nextConfig;
