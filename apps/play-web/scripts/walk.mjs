/** Walks the web player in a browser and takes screenshots (a dev tool: OUT=dir node scripts/walk.mjs). */
import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "shots";
const BASE = process.env.BASE ?? "http://127.0.0.1:8790";
const DEVICE = process.env.DEVICE ?? "iPhone 13";
const browser = await chromium.launch();
const ctx = await browser.newContext({ ...(DEVICE === "desktop" ? { viewport: { width: 1440, height: 900 } } : devices[DEVICE]), serviceWorkers: "block" });
const page = await ctx.newPage();
page.on("console", (m) => { if (m.type() === "error") console.log("console:", m.text()); });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
const shot = (name) => page.screenshot({ path: `${OUT}/${name}.png` });
await page.goto(`${BASE}/play/`);
for (const d of "1990") await page.getByRole("button", { name: d, exact: true }).click();
await page.getByRole("button", { name: "Done" }).click();
await page.getByRole("button", { name: "Done" }).click();
await page.waitForTimeout(800);
await shot("03-home");
await page.getByRole("button", { name: process.env.GAME === "tiles" ? "Play Tuna Tiles" : "Practice" }).click();
await page.waitForTimeout(2500);
await shot("04-start");
if (process.env.GAME === "tiles") {
  await page.getByRole("button", { name: "Start" }).click();
  await page.waitForTimeout(2500);
  await shot("05-tiles");
  await page.getByRole("button", { name: "Hint" }).click();
  await page.waitForTimeout(800);
  await shot("06-hint");
} else {
  for (let turn = 0; turn < 3; turn++) {
    await page.locator("#deck:not([disabled])").waitFor({ timeout: 20000 });
    await page.locator("#deck").click();
    await page.waitForTimeout(700);
    await shot(`05-drew-${turn}`);
    const cards = page.locator(".card.mine .card-inner");
    // Drag the last card onto the discard pile.
    const card = cards.last();
    const from = await card.boundingBox();
    const to = await page.locator("#discard").boundingBox();
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(500);
    await shot(`06-discarded-${turn}`);
  }
}
await browser.close();
