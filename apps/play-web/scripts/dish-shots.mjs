/**
 * Screenshots of the Daily Dish's screens at every size AGENTS.md asks for (a dev tool):
 *   BASE=http://127.0.0.1:8807 OUT=dir STEPS=home,dish,play,end node scripts/dish-shots.mjs
 * Needs a server with DAILY=on and DAILY_TEST=on. "Largest text" is the browser's text size at its
 * maximum: the page's root font size at 200%, which every rem in the player follows.
 */
import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "shots";
const BASE = process.env.BASE ?? "http://127.0.0.1:8807";
const STEPS = (process.env.STEPS ?? "home").split(",");
const NAME = process.env.NAME ?? "Bartholomew";
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
for (const size of SIZES) {
  const { name, big, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", extraHTTPHeaders: { "cf-connecting-ip": `10.77.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  const shot = async (step) => {
    await page.waitForTimeout(step === "end" ? 1600 : 700);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png`, fullPage: false });
  };
  await page.goto(`${BASE}/play/`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill(NAME);
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByRole("button", { name: "Practice" }).waitFor();
  if (STEPS.includes("home")) await shot("home");
  if (STEPS.some((s) => s !== "home")) {
    await page.getByRole("button", { name: /Daily Dish|Open the Dish/ }).first().click();
    if (STEPS.includes("dish")) await shot("dish");
    if (STEPS.includes("play") || STEPS.includes("end")) {
      await page.getByRole("button", { name: /Play Test/ }).click();
      await page.getByTestId("test-count").waitFor();
      if (STEPS.includes("play")) await shot("play");
      for (let i = 0; i < 12 && (await page.getByRole("button", { name: "Step" }).isEnabled().catch(() => false)); i++) {
        await page.getByRole("button", { name: "Step" }).click();
      }
      await page.getByRole("heading", { name: /Solved|Gave up/ }).waitFor({ timeout: 20_000 });
      if (STEPS.includes("end")) await shot("end");
      if (STEPS.includes("dish")) {
        await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
        await shot("dish-after");
      }
    }
  }
  await ctx.close();
}
await browser.close();
