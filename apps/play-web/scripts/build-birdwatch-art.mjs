#!/usr/bin/env node
/**
 * Birdwatch's poster for Home's shelf, until the iOS app has its own: scripts/birdwatch-poster.html
 * (our Bird, our cats, our card faces) drawn by Chromium at 768 x 512 and encoded as WebP. The
 * output is committed (src/art/game-birdwatch.webp). Needs cwebp.
 *
 *   node apps/play-web/scripts/build-birdwatch-art.mjs
 */
import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { chromium } from "@playwright/test";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "../src/art/game-birdwatch.webp");
const png = join(here, ".game-birdwatch.png");

const browser = await chromium.launch({ args: ["--mute-audio", "--allow-file-access-from-files"] });
const page = await browser.newPage({ viewport: { width: 768, height: 512 } });
await page.goto(pathToFileURL(join(here, "birdwatch-poster.html")).href);
await page.evaluate(() => Promise.all([...document.images].map((img) => img.decode().catch(() => undefined))));
await page.screenshot({ path: png });
await browser.close();
execFileSync("cwebp", ["-quiet", "-q", "80", "-m", "6", png, "-o", out]);
rmSync(png);
console.log("poster built");
