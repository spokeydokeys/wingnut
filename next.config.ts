import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cache Components is deliberately off. Nearly every screen here renders
  // per-user, must-be-fresh data (a running flight timer, a balance owed), so
  // caching buys nothing and a stale figure would be actively misleading.
  cacheComponents: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
