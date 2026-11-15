#!/usr/bin/env node
/**
 * Performance traces of the web player (web player design, "Testing"): Chrome on a laptop
 * profile and on a mobile profile with the CPU slowed 4x, through the moments that move the most:
 * the deal, a drag, a play (yours and the House Cat's) and the round's end with the next deal.
 * Records a Chrome DevTools trace of each run and the frame times the page itself sees, then
 * prints a table. Needs a server with the web player built: BASE (default
 * http://127.0.0.1:8790), started with a high DEV_SPEED so the House Cat plays quickly.
 *
 *   OUT=traces node apps/play-web/scripts/perf.mjs
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

import { chromium, devices } from "@playwright/test";

const BASE = process.env.BASE ?? "http://127.0.0.1:8790";
const OUT = process.env.OUT ?? "perf-out";
mkdirSync(OUT, { recursive: true });

const PROFILES = [
  { name: "laptop", context: { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 }, throttle: 1 },
  { name: "mobile-4x", context: { ...devices["Pixel 7"] }, throttle: 4 },
];

/** Frame times the page sees: one requestAnimationFrame per frame, recorded between start and stop. */
const RECORDER = `
  window.__perf = { on: false, marks: [], frames: [] };
  (function loop(t) {
    if (window.__perf.on) window.__perf.frames.push(t);
    requestAnimationFrame(loop);
  })(performance.now());
`;

function stats(times) {
  const deltas = [];
  for (let i = 1; i < times.length; i++) deltas.push(times[i] - times[i - 1]);
  if (deltas.length === 0) return null;
  const sorted = [...deltas].sort((a, b) => a - b);
  const p = (q) => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
  const total = times[times.length - 1] - times[0];
  return {
    frames: deltas.length,
    fps: Math.round((deltas.length / total) * 1000 * 10) / 10,
    p50: Math.round(p(0.5) * 10) / 10,
    p95: Math.round(p(0.95) * 10) / 10,
    max: Math.round(sorted[sorted.length - 1] * 10) / 10,
    // A frame that took more than one and a half refreshes at 60 Hz is a dropped frame.
    dropped: deltas.filter((d) => d > 25).length,
  };
}

/** From a DevTools trace: main-thread tasks over 50 ms, and how much the compositor drew. */
function traceStats(trace) {
  const events = trace.traceEvents ?? [];
  // The renderer's main thread only.
  const main = events.find((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
  const tasks = events.filter((e) => (e.name === "RunTask" || e.name === "ThreadControllerImpl::RunTask") && e.ph === "X" && e.dur && (!main || (e.pid === main.pid && e.tid === main.tid)));
  const long = tasks.filter((e) => e.dur > 50_000);
  const sorted = tasks.map((e) => e.dur).sort((a, b) => a - b);
  const p95 = sorted.length ? sorted[Math.floor(sorted.length * 0.95)] / 1000 : 0;
  const layouts = events.filter((e) => e.name === "Layout" && e.ph === "X").length;
  const paints = events.filter((e) => e.name === "Paint" && e.ph === "X").length;
  const frames = events.filter((e) => e.name === "DrawFrame" || e.name === "Graphics.Pipeline").length;
  return {
    tasks: tasks.length,
    longTasks: long.length,
    p95TaskMs: Math.round(p95 * 10) / 10,
    longestTaskMs: Math.round(Math.max(0, ...tasks.map((e) => e.dur)) / 100) / 10,
    layouts,
    paints,
    frames,
  };
}

async function window_(page, label, fn) {
  await page.evaluate(() => {
    window.__perf.frames = [];
    window.__perf.on = true;
  });
  await fn();
  const frames = await page.evaluate(() => {
    window.__perf.on = false;
    return window.__perf.frames;
  });
  return { label, ...stats(frames) };
}

async function run(profile) {
  const browser = await chromium.launch({ args: ["--disable-gpu-vsync=false"] });
  const context = await browser.newContext({ ...profile.context, serviceWorkers: "block" });
  await context.addInitScript(RECORDER);
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await page.goto(`${BASE}/play/`);
  for (const d of "1988") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Practice" }).waitFor();
  // Art cached, as on a second visit, so the numbers are the game's, not the network's.
  if (profile.throttle > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: profile.throttle });
  await browser.startTracing(page, { categories: ["toplevel", "devtools.timeline", "disabled-by-default-devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink.user_timing"], screenshots: false });

  const results = [];
  results.push(
    await window_(page, "deal", async () => {
      await page.getByRole("button", { name: "Practice" }).click();
      await page.locator("#deck").waitFor();
      await page.waitForTimeout(2200);
    }),
  );

  // Our turn: draw, then a long drag across the table, dropped on the discard pile.
  await page.locator("#deck:not([disabled])").waitFor({ timeout: 60_000 });
  await page.locator("#deck").click();
  await page.waitForTimeout(700);
  results.push(
    await window_(page, "drag", async () => {
      const card = page.locator(".card.mine .card-inner").first();
      const from = await card.boundingBox();
      const to = await page.locator("#discard").boundingBox();
      await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
      await page.mouse.down();
      const steps = 90;
      for (let i = 1; i <= steps; i++) {
        const t = i / steps;
        // Out and back across the table before landing on the pile.
        const x = from.x + from.width / 2 + (to.x - from.x) * t + Math.sin(t * Math.PI * 2) * 120;
        const y = from.y + from.height / 2 + (to.y - from.y) * t;
        await page.mouse.move(x, y);
        await page.waitForTimeout(16);
      }
      await page.mouse.up();
      await page.waitForTimeout(600);
    }),
  );

  // A play: the House Cat's turn animating, then ours again (draw and a tapped discard).
  results.push(
    await window_(page, "play", async () => {
      await page.locator("#deck:not([disabled])").waitFor({ timeout: 60_000 });
      await page.locator("#deck").click();
      await page.waitForTimeout(500);
      await page.locator(".card.mine .card-inner").last().click();
      await page.locator("#discard").click();
      await page.waitForTimeout(2500);
    }),
  );

  // Play on until the round ends; record the results and the next deal.
  let roundEnd = null;
  for (let turn = 0; turn < 60 && !roundEnd; turn++) {
    const over = page.locator(".round-over");
    const deck = page.locator("#deck:not([disabled])");
    await Promise.race([over.waitFor({ timeout: 60_000 }), deck.waitFor({ timeout: 60_000 })]).catch(() => undefined);
    if (await over.isVisible()) {
      roundEnd = await window_(page, "round end", async () => {
        await page.waitForTimeout(4000);
      });
      break;
    }
    if (await deck.isVisible()) {
      await deck.click();
      await page.waitForTimeout(450);
      // Discard the highest-scoring card we can, so the House Cat goes out sooner.
      await page.locator(".card.mine .card-inner").last().click();
      await page.locator("#discard").click();
      await page.waitForTimeout(400);
    }
  }
  if (roundEnd) results.push(roundEnd);

  const buffer = await browser.stopTracing();
  const trace = JSON.parse(buffer.toString());
  writeFileSync(join(OUT, `trace-${profile.name}.json.gz`), gzipSync(buffer));
  await browser.close();
  return { profile: profile.name, throttle: profile.throttle, results, trace: traceStats(trace) };
}

/** A first visit on a mid-range phone over slow 4G (Lighthouse's mobile: 150 ms, 1.6 Mbps, CPU 4x), nothing cached. */
async function firstLoad() {
  const browser = await chromium.launch();
  const context = await browser.newContext({ ...devices["Pixel 7"], serviceWorkers: "block" });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 150, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 });
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: 4 });
  const start = Date.now();
  await page.goto(`${BASE}/play/`, { waitUntil: "commit" });
  await page.getByRole("heading", { name: "What year were you born?" }).waitFor();
  const interactive = Date.now() - start;
  await page.waitForLoadState("networkidle");
  const m = await page.evaluate(() => {
    const fcp = performance.getEntriesByName("first-contentful-paint")[0]?.startTime ?? null;
    const res = performance.getEntriesByType("resource");
    const nav = performance.getEntriesByType("navigation")[0];
    const bytes = res.reduce((n, r) => n + (r.transferSize || 0), 0) + (nav?.transferSize ?? 0);
    const script = res.filter((r) => r.initiatorType === "script" || r.name.endsWith(".js")).reduce((n, r) => n + (r.transferSize || 0), 0);
    return { fcp, bytes, script, requests: res.length + 1 };
  });
  await browser.close();
  return { fcpMs: Math.round(m.fcp ?? 0), ageScreenMs: interactive, transferredKB: Math.round(m.bytes / 1024), scriptKB: Math.round(m.script / 1024), requests: m.requests };
}

const all = [];
const load = await firstLoad();
console.log("\nfirst load, slow 4G, CPU x4:", load);
for (const profile of PROFILES) {
  const r = await run(profile);
  all.push(r);
  console.log(`\n${r.profile} (CPU x${r.throttle})`);
  console.table(r.results);
  console.log("trace:", r.trace);
}
writeFileSync(join(OUT, "summary.json"), JSON.stringify({ firstLoad: load, runs: all }, null, 2));
