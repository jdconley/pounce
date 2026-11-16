import { expect, type Browser, type BrowserContext, type Page } from "@playwright/test";

let addresses = 0;
const nextAddress = () => `10.${(process.pid % 200) + 1}.${Math.floor(++addresses / 250)}.${(addresses % 250) + 1}`;

/** A new player in a fresh browser profile: the age check and a name, then Home. */
export async function newPlayer(browser: Browser, name: string, opts: { path?: string; year?: string; context?: Parameters<Browser["newContext"]>[0] } = {}) {
  // Each player comes from an address of its own, as family members' phones do: a full run signs
  // up more devices than the server's per-address limit allows from one (10 a minute). Only
  // wrangler dev believes this header; Cloudflare sets it itself in production.
  const context = await browser.newContext({ ...opts.context, extraHTTPHeaders: { "cf-connecting-ip": nextAddress() } });
  const page = await context.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
  if (process.env.E2E_DEBUG) {
    page.on("console", (m) => console.log(name, m.type(), m.text()));
    page.on("websocket", (ws) => {
      ws.on("framesent", (f) => String(f.payload).includes("ping") || console.log(name, "SENT", String(f.payload).slice(0, 140)));
      ws.on("framereceived", (f) => /"t":"(event|error)"/.test(String(f.payload)) && console.log(name, "RECV", String(f.payload).slice(0, 140)));
    });
  }
  await page.goto(opts.path ?? "/play/");
  await firstRun(page, name, opts.year);
  return { context, page };
}

export async function firstRun(page: Page, name: string, year = "1985") {
  await expect(page.getByRole("heading", { name: "What year were you born?" })).toBeVisible();
  for (const d of year) await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  const field = page.getByLabel("Your name");
  await expect(field).toBeVisible();
  await field.fill(name);
  await page.getByRole("button", { name: "Done" }).click();
}

/** The table code from a page at /play/t/<code>. */
export async function tableCode(page: Page): Promise<string> {
  await page.waitForURL(/\/play\/t\/[A-Z0-9]{5}$/);
  return page.url().split("/").at(-1) as string;
}

export const deckCount = async (page: Page) => Number(await page.locator("#deck .pile-count").textContent());

/** Plays one Cat Tower turn on `page` if it's this page's turn: draw, then discard by tap. */
export async function catTowerTurn(page: Page): Promise<boolean> {
  const deck = page.locator("#deck:not([disabled])");
  if (!(await deck.isVisible())) return false;
  const cards = page.locator(".card.mine .card-inner");
  const before = await cards.count();
  await deck.click();
  // The drawn card arrives; then pick the right-most card and tap the discard pile.
  await expect(cards).toHaveCount(before + 1);
  await cards.last().click();
  await page.locator("#discard").click();
  return true;
}

export async function closeAll(...contexts: BrowserContext[]) {
  for (const c of contexts) await c.close();
}
