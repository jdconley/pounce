#!/usr/bin/env node
/**
 * After `vite build`: the service worker (src/sw.ts) with this build's shell to precache, and
 * /play/version.json, which the page and the worker check for a newer deploy.
 */
import { execSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "../../play-api/public/play");
const manifest = JSON.parse(readFileSync(join(out, ".vite/manifest.json"), "utf8"));

function buildId() {
  if (process.env.WEB_BUILD) return process.env.WEB_BUILD;
  try {
    return execSync("git rev-parse --short=12 HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "dev";
  }
}

// The shell: the entry's script and styles, the chunks it imports, and its fonts. Art and sounds
// are cached as they are first used.
const shell = new Set();
const visit = (key) => {
  const chunk = manifest[key];
  if (!chunk || shell.has(`/play/${chunk.file}`)) return;
  shell.add(`/play/${chunk.file}`);
  for (const css of chunk.css ?? []) shell.add(`/play/${css}`);
  for (const asset of chunk.assets ?? []) if (/\.(woff2|css)$/.test(asset)) shell.add(`/play/${asset}`);
  for (const imp of chunk.imports ?? []) visit(imp);
};
for (const [key, chunk] of Object.entries(manifest)) if (chunk.isEntry) visit(key);
for (const icon of ["icon-192.png", "icon-512.png"]) shell.add(`/play/icons/${icon}`);
shell.add("/play/manifest.webmanifest");

const id = buildId();
await build({
  entryPoints: [join(here, "../src/sw.ts")],
  bundle: true,
  minify: true,
  format: "iife",
  target: "es2022",
  outfile: join(out, "sw.js"),
  define: { __PRECACHE__: JSON.stringify([...shell]), __BUILD__: JSON.stringify(id) },
});
writeFileSync(join(out, "version.json"), JSON.stringify({ build: id }) + "\n");
rmSync(join(out, ".vite"), { recursive: true, force: true });
console.log(`sw.js: ${shell.size} shell files, build ${id}`);
