/**
 * Screenshots of Sniff in the browser at every size AGENTS.md asks for (a dev tool):
 *   BASE=http://127.0.0.1:8804 OUT=dir node scripts/sniff-shots.mjs
 * Needs a server with DAILY=on. Takes the Dish with Sniff's treat, Sniff new, two guesses in with a
 * word half typed, an unknown word, the end, and the share card (once). "Largest text" is the
 * page's root font size at 200%, which every rem in the player follows.
 */
import { writeFile } from "node:fs/promises";

import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "shots";
const BASE = process.env.BASE ?? "http://127.0.0.1:8804";
const SIZES = [
  { name: "iphone-se", ...devices["iPhone SE (3rd gen)"] },
  { name: "iphone-pro-max", ...devices["iPhone 15 Pro Max"] },
  { name: "ipad-portrait", ...devices["iPad (gen 7)"] },
  { name: "ipad-landscape", ...devices["iPad (gen 7) landscape"] },
  { name: "laptop", viewport: { width: 1440, height: 900 } },
  { name: "iphone-se-largest-text", ...devices["iPhone SE (3rd gen)"], big: true },
].filter((s) => !process.env.SIZES || process.env.SIZES.split(",").includes(s.name));

const browser = await chromium.launch();
let ip = 1;
let card = false;
for (const size of SIZES) {
  const { name, big, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", extraHTTPHeaders: { "cf-connecting-ip": `10.78.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, "canShare", { value: () => true, configurable: true });
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: async (d) => {
        const file = d.files?.[0];
        if (file)
          window.__card = await new Promise((done) => {
            const r = new FileReader();
            r.onload = () => done(String(r.result).split(",")[1]);
            r.readAsDataURL(file);
          });
      },
    });
  });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  const shot = async (step, wait = 700) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png`, fullPage: false });
  };
  const keys = page.getByRole("group", { name: "Keyboard" });
  const tap = async (word, send = true) => {
    for (const l of word.toUpperCase()) await keys.getByRole("button", { name: new RegExp(`^${l}(,|$)`) }).click();
    if (send) await keys.getByRole("button", { name: "Sniff" }).click();
  };
  await page.goto(`${BASE}/play/`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill("Bartholomew");
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Practice" }).waitFor();
  await shot("home");
  await page.getByRole("button", { name: "Open the Dish" }).click();
  await shot("dish");
  await page.getByRole("button", { name: /Play Sniff|Sniff/ }).first().click();
  await keys.waitFor();
  await shot("sniff-new", 1200);
  await tap("crane");
  await page.getByRole("group", { name: "Try 1" }).locator(".sniff-tag[data-mark=none], .sniff-tag[data-mark=near], .sniff-tag[data-mark=spot]").nth(4).waitFor();
  await page.waitForTimeout(700);
  await tap("sloth");
  await page.getByRole("group", { name: "Try 2" }).locator(".sniff-tag[data-mark=none], .sniff-tag[data-mark=near], .sniff-tag[data-mark=spot]").nth(4).waitFor();
  await tap("pud", false);
  await shot("sniff-mid", 1200);
  for (let i = 0; i < 3; i++) await keys.getByRole("button", { name: "Delete" }).click();
  await tap("zzzzz");
  await shot("sniff-not-a-word", 300);
  for (let i = 0; i < 5; i++) await keys.getByRole("button", { name: "Delete" }).click();
  for (const word of ["pudgy", "witch", "femur", "balky"]) {
    if (await page.getByRole("heading", { name: /Solved|Missed/ }).isVisible()) break;
    await tap(word);
    await page.waitForTimeout(900);
  }
  await page.getByRole("heading", { name: /Solved|Missed/ }).waitFor({ timeout: 20_000 });
  await shot("sniff-end", 1800);
  if (!card) {
    await page.getByRole("button", { name: "Share" }).click();
    await page.waitForFunction(() => window.__card);
    await writeFile(`${OUT}/sniff-share-card.png`, Buffer.from(await page.evaluate(() => window.__card), "base64"));
    card = true;
  }
  await ctx.close();
}
await browser.close();
