/**
 * Screenshots of Nine Lives' screens at every size AGENTS.md asks for (a dev tool):
 *   BASE=http://127.0.0.1:8823 OUT=dir STEPS=play,midway,wrong,out,end node scripts/nine-lives-shots.mjs
 * Needs a server with DAILY=on. Each size plays two runs (two new players): one that is solved
 * (play, midway, end) and one that runs out of lives (wrong, out). "Largest text" is the page's
 * root font size at 200%, which every rem in the player follows.
 */
import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "shots";
const BASE = process.env.BASE ?? "http://127.0.0.1:8823";
const STEPS = (process.env.STEPS ?? "play,midway,wrong,out,end").split(",");
const NAME = process.env.NAME ?? "Bartholomew";
const SIZES = [
  { name: "phone-320", viewport: { width: 320, height: 568 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true },
  { name: "iphone-se", ...devices["iPhone SE (3rd gen)"] },
  { name: "iphone-pro-max", ...devices["iPhone 15 Pro Max"] },
  { name: "ipad-portrait", ...devices["iPad (gen 7)"] },
  { name: "ipad-landscape", ...devices["iPad (gen 7) landscape"] },
  { name: "laptop", viewport: { width: 1440, height: 900 } },
  { name: "phone-320-largest-text", viewport: { width: 320, height: 568 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, big: true },
  { name: "iphone-se-largest-text", ...devices["iPhone SE (3rd gen)"], big: true },
  { name: "iphone-pro-max-largest-text", ...devices["iPhone 15 Pro Max"], big: true },
  { name: "ipad-landscape-largest-text", ...devices["iPad (gen 7) landscape"], big: true },
].filter((s) => !process.env.SIZES || process.env.SIZES.split(",").includes(s.name));

/** The one solution of `cells` (0 for open). */
function solve(cells) {
  const g = [...cells];
  const free = (i) => {
    const [r, c] = [Math.floor(i / 9), i % 9];
    let used = 0;
    for (let k = 0; k < 9; k++) {
      used |= (1 << g[r * 9 + k]) | (1 << g[k * 9 + c]);
      used |= 1 << g[(Math.floor(r / 3) * 3 + Math.floor(k / 3)) * 9 + Math.floor(c / 3) * 3 + (k % 3)];
    }
    return [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((d) => !(used & (1 << d)));
  };
  const go = () => {
    let best = -1;
    let options = [];
    for (let i = 0; i < 81; i++) {
      if (g[i]) continue;
      const f = free(i);
      if (best < 0 || f.length < options.length) [best, options] = [i, f];
      if (f.length === 0) return false;
    }
    if (best < 0) return true;
    for (const d of options) {
      g[best] = d;
      if (go()) return true;
    }
    g[best] = 0;
    return false;
  };
  if (!go()) throw new Error("no solution");
  return g;
}

const browser = await chromium.launch({ args: ["--mute-audio"] });
let ip = 1;

async function player(size) {
  const { name, big, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", extraHTTPHeaders: { "cf-connecting-ip": `10.78.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  await page.goto(`${BASE}/play/`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill(NAME);
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Practice" }).waitFor();
  await page.goto(`${BASE}/play/daily/nine-lives`);
  await page.getByRole("group", { name: "Nine Lives" }).waitFor();
  const board = await page.locator(".nl-board button[data-cell]").evaluateAll((els) =>
    els.map((el) => {
      const parts = (el.getAttribute("aria-label") ?? "").split(", ");
      return { i: Number(el.getAttribute("data-cell")), d: Number(parts[2]) || 0, given: parts.includes("given") };
    }),
  );
  board.sort((a, b) => a.i - b.i);
  const solution = solve(board.map((c) => (c.given ? c.d : 0)));
  const open = board.filter((c) => !c.given).map((c) => c.i);
  const shot = async (step, wait = 700) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png`, fullPage: false });
  };
  const put = async (i, d) => {
    await page.locator(`.nl-board [data-cell="${i}"]`).click();
    await page.keyboard.press(String(d));
    await page.waitForTimeout(80);
  };
  const tip = async () => {
    const x = page.getByRole("button", { name: "Dismiss tip" });
    if (await x.isVisible().catch(() => false)) await x.click();
  };
  return { ctx, page, solution, open, shot, put, tip };
}

for (const size of SIZES) {
  if (STEPS.some((s) => ["play", "midway", "end"].includes(s))) {
    const p = await player(size);
    if (STEPS.includes("play")) await p.shot("play");
    if (STEPS.includes("midway") || STEPS.includes("end")) {
      await p.page.getByRole("button", { name: /^Hint/ }).click();
      await p.page.waitForTimeout(500);
      for (const i of p.open.slice(0, Math.floor(p.open.length / 2))) await p.put(i, p.solution[i]);
      if (STEPS.includes("midway")) await p.shot("midway", 1400);
      await p.tip();
      for (const i of p.open) {
        const label = await p.page.locator(`.nl-board [data-cell="${i}"]`).getAttribute("aria-label");
        if (!label?.includes(`, ${p.solution[i]}`)) await p.put(i, p.solution[i]);
      }
      await p.page.getByRole("heading", { name: "Solved" }).waitFor({ timeout: 20_000 });
      if (STEPS.includes("end")) await p.shot("end", 1600);
    }
    await p.ctx.close();
  }
  if (STEPS.some((s) => ["wrong", "out"].includes(s))) {
    const p = await player(size);
    for (const i of p.open.slice(0, 8)) await p.put(i, p.solution[i]);
    const wrongAt = p.open.slice(10, 13);
    const wrongOf = (i) => (p.solution[i] % 9) + 1;
    await p.put(wrongAt[0], wrongOf(wrongAt[0]));
    if (STEPS.includes("wrong")) await p.shot("wrong", 1200);
    await p.tip();
    await p.put(wrongAt[1], wrongOf(wrongAt[1]));
    await p.page.waitForTimeout(600);
    await p.put(wrongAt[2], wrongOf(wrongAt[2]));
    if (STEPS.includes("out")) {
      await p.shot("out-reveal", 900);
      // The end comes over the board after the solution fills in (its CSS delay).
      await p.page.getByRole("heading", { name: /Out of lives|Missed|Solved/ }).waitFor({ timeout: 20_000 }).catch(() => {});
      await p.shot("out", 3600);
    }
    await p.ctx.close();
  }
}
await browser.close();
