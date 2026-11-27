/**
 * Screenshots of Toy Tumble in the browser at every size AGENTS.md asks for (a dev tool), from live
 * games against the server's House Cats:
 *   BASE=http://127.0.0.1:8795 OUT=screenshots/tumble node scripts/tumble-shots.mjs
 * Needs a server with GAMES listing tumble and TV on, and a web build with WEB_TUMBLE=on. Each size
 * shoots Home, the lobby, How to play, the 3-2-1, play, watching once out, and round over; then the
 * TV page with six boxes and a phone at that TV table. "Largest text" is the page's root font size
 * at 200%. One player is "Great Aunt Josephine", to test long names.
 */
import { mkdirSync } from "node:fs";

import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "screenshots/tumble";
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

const browser = await chromium.launch({ args: ["--mute-audio"] });
let ip = 1;

async function player(device, name, path = "/play/", big = false) {
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", extraHTTPHeaders: { "cf-connecting-ip": `10.81.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  await page.goto(`${BASE}${path}`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill(name);
  await page.getByRole("button", { name: "Done" }).click();
  return { ctx, page };
}

const live = (page) => page.locator(".tt-table[data-live]").count().then((n) => n > 0);
const dismissTip = async (page) => {
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible()) await tip.click();
};

/** A few keys, then a drop. */
async function turn(page, k) {
  for (let i = 0; i < (k % 3) + 1; i++) await page.keyboard.press(k % 2 ? "ArrowLeft" : "ArrowRight");
  await page.keyboard.press("Space");
}

for (const size of SIZES) {
  const { name, big, ...device } = size;
  const { ctx, page } = await player(device, "Great Aunt Josephine", "/play/", big);
  const shot = async (step, wait = 700) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png` });
  };
  await page.getByRole("button", { name: "Play Toy Tumble" }).scrollIntoViewIfNeeded();
  await shot("home");
  await page.getByRole("button", { name: "Play Toy Tumble" }).click();
  await page.waitForURL(/\/play\/t\//);
  await page.locator(".lobby-seat.bot").first().waitFor();
  for (let n = 1; n < 5; n++) await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
  await dismissTip(page);
  await shot("lobby");
  await page.getByRole("button", { name: "How to play" }).click();
  await shot("how-to-play");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Start" }).click();
  await shot("countdown", 900);
  // Play a little, then shoot the box mid-round.
  for (let i = 0; i < 40 && !(await live(page)); i++) await page.waitForTimeout(150);
  for (let k = 0; k < 6; k++) {
    await turn(page, k);
    await page.waitForTimeout(250);
  }
  // The House Cats take a few seconds a toy: give their minis something to show.
  await page.waitForTimeout(9000);
  await shot("play", 0);
  // Drop till out: every box big.
  for (let k = 0; k < 80 && (await live(page)); k++) await page.keyboard.press("Space");
  await page.locator(".tt-table.watching, .tt-over").first().waitFor({ timeout: 30_000 }).catch(() => undefined);
  if (await page.locator(".tt-table.watching").isVisible()) await shot("watching", 1200);
  await page.locator(".tt-over").waitFor({ timeout: 120_000 }).catch(() => undefined);
  await shot("round-over", 1200);
  await ctx.close();
}

// The TV page with six boxes, and a phone at that TV table.
if (!process.env.SIZES || process.env.SIZES.split(",").includes("tv")) {
  const tvCtx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, serviceWorkers: "block", extraHTTPHeaders: { "cf-connecting-ip": `10.81.${process.pid % 200}.${ip++}` } });
  await tvCtx.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
  const tv = await tvCtx.newPage();
  await tv.goto(`${BASE}/play/tv`);
  await tv.getByRole("button", { name: "Start", exact: true }).click();
  await tv.getByRole("button", { name: /^Toy Tumble\s*\d+ to \d+ players$/ }).click();
  const code = ((await tv.locator(".tv-lobby .tv-code").textContent()) ?? "").trim();
  const { ctx, page } = await player(devices["iPhone SE (3rd gen)"], "Great Aunt Josephine", `/play/j/${code}`);
  await page.waitForURL(/\/play\/t\//);
  for (let n = 0; n < 5; n++) await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
  await tv.waitForTimeout(800);
  await tv.screenshot({ path: `${OUT}/lobby-tv.png` });
  await page.getByRole("button", { name: "Start", exact: true }).click();
  for (let i = 0; i < 40 && !(await live(page)); i++) await page.waitForTimeout(150);
  for (let k = 0; k < 8; k++) {
    await turn(page, k);
    await page.waitForTimeout(300);
  }
  await page.waitForTimeout(9000);
  await tv.screenshot({ path: `${OUT}/play-tv.png` });
  await page.screenshot({ path: `${OUT}/play-at-tv-table-iphone-se.png` });
  await tv.locator(".tt-over").waitFor({ timeout: 120_000 }).catch(() => undefined);
  await tv.waitForTimeout(1200);
  await tv.screenshot({ path: `${OUT}/round-over-tv.png` });
  await ctx.close();
  await tvCtx.close();
}
await browser.close();
console.log(`shots in ${OUT}`);
