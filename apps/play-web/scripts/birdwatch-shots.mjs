/**
 * Screenshots of Birdwatch in the browser at every size AGENTS.md asks for (a dev tool):
 *   BASE=http://127.0.0.1:8795 OUT=screenshots/birdwatch node scripts/birdwatch-shots.mjs
 * Needs a server with GAMES listing birdwatch. Home and the lobby come from that server; each
 * phase of a hand is the server's own sample snapshot (apps/play-api/fixtures/protocol), played to
 * the page through its socket, with one player renamed "Great Aunt Josephine" to test long names.
 * "Largest text" is the page's root font size at 200%, which every rem in the player follows.
 */
import { mkdirSync, readFileSync } from "node:fs";

import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "screenshots/birdwatch";
const BASE = process.env.BASE ?? "http://127.0.0.1:8795";
mkdirSync(OUT, { recursive: true });
const SIZES = [
  { name: "iphone-se", ...devices["iPhone SE (3rd gen)"] },
  { name: "iphone-pro-max", ...devices["iPhone 15 Pro Max"] },
  { name: "ipad-portrait", ...devices["iPad (gen 7)"] },
  { name: "ipad-landscape", ...devices["iPad (gen 7) landscape"] },
  { name: "laptop", viewport: { width: 1440, height: 900 } },
  { name: "iphone-se-largest-text", ...devices["iPhone SE (3rd gen)"], big: true },
].filter((s) => !process.env.SIZES || process.env.SIZES.split(",").includes(s.name));

const samples = JSON.parse(readFileSync(new URL("../../play-api/fixtures/protocol/birdwatch-server-messages.json", import.meta.url), "utf8"));
const sample = (name) => JSON.parse(JSON.stringify(samples.find((s) => s.name === name).message).replaceAll('"Alice"', '"Great Aunt Josephine"'));
const PHASES = [
  ["bid", "snapshot-bidding-your-move"],
  ["six-players", "snapshot-six-house-cat"],
  ["nest", "snapshot-nest-bid-winner"],
  ["trump", "snapshot-trump-bid-winner"],
  ["follow-suit", "snapshot-play-follow"],
  ["partner-call", "snapshot-five-partner-call"],
  ["secret-partner", "snapshot-five-you-are-partner"],
  ["between", "snapshot-between"],
  ["over", "snapshot-over-target"],
];

const browser = await chromium.launch({ args: ["--mute-audio"] });
let ip = 1;
for (const size of SIZES) {
  const { name, big, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", reducedMotion: "reduce", extraHTTPHeaders: { "cf-connecting-ip": `10.79.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  const shot = async (step, wait = 900) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png` });
  };
  await page.goto(`${BASE}/play/`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill("Bartholomew");
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Play Birdwatch" }).scrollIntoViewIfNeeded();
  await shot("home");
  await page.getByRole("button", { name: "Play Birdwatch" }).click();
  await page.waitForURL(/\/play\/t\//);
  await page.getByRole("button", { name: "House Cat" }).nth(2).waitFor();
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible()) await tip.click();
  await page.getByRole("radio", { name: "Tucker" }).click();
  await shot("lobby");
  await page.getByRole("button", { name: "How to play" }).click();
  await shot("how-to-play");
  await page.keyboard.press("Escape");

  // Each phase, from the server's sample, on a table page whose socket plays it.
  let said = null;
  await page.routeWebSocket(/\/v1\/rooms\/[A-Z0-9]+\/ws/, (ws) => {
    ws.onMessage((m) => {
      if (JSON.parse(String(m)).t === "ping") ws.send(JSON.stringify({ t: "pong" }));
    });
    if (said) ws.send(JSON.stringify(said));
  });
  for (const [step, fixture] of PHASES) {
    said = sample(fixture);
    await page.goto(`${BASE}/play/t/BCDFG`);
    await page.locator(".bw-table, .game-over").first().waitFor();
    await shot(step, 1400);
    if (step === "between") {
      await page.locator("#bw-strip").click();
      await shot("score-sheet");
    }
  }
  await ctx.close();
}
// The TV: its home with Birdwatch's poster, a Birdwatch lobby, and the table mid-hand while a
// phone plays its seat on Cards.
if (!process.env.SIZES || process.env.SIZES.includes("tv")) {
  const tvCtx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, reducedMotion: "reduce", extraHTTPHeaders: { "cf-connecting-ip": `10.79.${process.pid % 200}.${ip++}` } });
  await tvCtx.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
  const tv = await tvCtx.newPage();
  await tv.goto(`${BASE}/play/tv`);
  await tv.getByRole("button", { name: "Start", exact: true }).click();
  await tv.getByRole("button", { name: /^Birdwatch\s*4 to 6 players$/ }).waitFor();
  await tv.waitForTimeout(1200);
  await tv.screenshot({ path: `${OUT}/tv-home.png` });
  await tv.getByRole("button", { name: /^Birdwatch\s*4 to 6 players$/ }).click();
  const codeEl = tv.locator(".tv-lobby .tv-code");
  await codeEl.waitFor();
  const code = ((await codeEl.textContent()) ?? "").trim();
  const phoneCtx = await browser.newContext({ ...devices["Pixel 7"], reducedMotion: "reduce", extraHTTPHeaders: { "cf-connecting-ip": `10.79.${process.pid % 200}.${ip}` } });
  const phone = await phoneCtx.newPage();
  await phone.goto(`${BASE}/play/j/${code}`);
  for (const d of "1985") await phone.getByRole("button", { name: d, exact: true }).click();
  await phone.getByRole("button", { name: "Done" }).click();
  await phone.getByLabel("Your name").fill("Great Aunt Josephine");
  await phone.getByRole("button", { name: "Done" }).click();
  await phone.waitForURL(/\/play\/t\//);
  for (let n = 0; n < 3; n++) {
    await phone.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await phone.waitForTimeout(400);
  }
  await phone.getByRole("radio", { name: "Friesen" }).click();
  await tv.waitForTimeout(1500);
  await tv.screenshot({ path: `${OUT}/tv-lobby.png` });
  await phone.getByRole("button", { name: "Start", exact: true }).click();
  await tv.locator(".bw-tv").waitFor();
  // The phone passes and plays its first card it may, until a trick is on the sill.
  const until = Date.now() + 60_000;
  while (Date.now() < until && (await tv.locator(".bw-tv .card.on-sill").count()) < 3) {
    if (await phone.locator("#bw-pass:not([disabled])").isVisible()) await phone.locator("#bw-pass").click();
    else if (await phone.locator("#bw-nest-done").isVisible()) break;
    else if (await phone.locator(".bw-cue.mine").isVisible()) {
      const c = phone.locator(".bw-hand-card:not(.dim)").first();
      const box = await c.boundingBox();
      if (box) {
        await phone.mouse.click(box.x + box.width * 0.22, box.y + box.height * 0.22);
        await phone.mouse.click(box.x + box.width * 0.22, box.y + box.height * 0.22);
      }
    }
    await phone.waitForTimeout(200);
  }
  await tv.screenshot({ path: `${OUT}/tv-table.png` });
  await phone.screenshot({ path: `${OUT}/phone-cards-with-tv.png` });
  await phoneCtx.close();
  await tvCtx.close();
}
await browser.close();
console.log("shots in", OUT);
