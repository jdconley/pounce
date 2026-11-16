import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { defineConfig } from "vite";

/**
 * The web player (docs/superpowers/specs/2026-11-15-web-player-design.md). Built into the
 * Worker's static assets under /play/, and deployed with it from the same commit.
 */
function buildId(): string {
  if (process.env.WEB_BUILD) return process.env.WEB_BUILD;
  try {
    return execSync("git rev-parse --short=12 HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "dev";
  }
}

/** The version the server and the funnel see: the build's UTC time, "2026.1115.1432". */
function buildVersion(now = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${now.getUTCFullYear()}.${p(now.getUTCMonth() + 1)}${p(now.getUTCDate())}.${p(now.getUTCHours())}${p(now.getUTCMinutes())}`;
}

const DEV_SERVER = process.env.DEV_SERVER_URL ?? "http://localhost:8787";

export default defineConfig({
  base: "/play/",
  define: {
    __BUILD__: JSON.stringify(buildId()),
    __VERSION__: JSON.stringify(buildVersion()),
  },
  build: {
    outDir: fileURLToPath(new URL("../play-api/public/play", import.meta.url)),
    emptyOutDir: true,
    target: "es2022",
    assetsDir: "assets",
    // Nothing inlined: every file is its own cached request, and the CSP allows no data: audio.
    assetsInlineLimit: 0,
    cssCodeSplit: false,
    manifest: true,
    reportCompressedSize: true,
  },
  server: {
    port: 5180,
    strictPort: false,
    proxy: {
      "/v1": { target: DEV_SERVER, ws: true, changeOrigin: true },
      "/j/": { target: DEV_SERVER, changeOrigin: true },
      "/static/": { target: DEV_SERVER, changeOrigin: true },
    },
  },
  oxc: { jsx: { runtime: "automatic", importSource: "preact" } },
});
