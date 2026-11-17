import { devices, expect, type Browser, type BrowserContext, type Page } from "@playwright/test";
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { findPhase } from "@pounce/play-api/rules/solver";

import { newPlayer, ownAddress } from "./helpers";

/**
 * Pounce on the TV, end to end: a TV page (`/play/tv`, its own device) and phones at one table.
 * On a table the TV shows, a seated phone shows the controller ("Cards"): off turn its piles rest
 * (role=img, no `#deck`), so turns here are told by the TV's own deck count, which is always there.
 */

export const TV_VIEWPORT = { width: 1920, height: 1080 };
/** The two phones every TV test seats, by turns. */
export const PHONES = [devices["Pixel 7"], devices["iPhone 13"]] as const;

export type Tv = {
  context: BrowserContext;
  page: Page;
  /** The links this TV was given (`POST /v1/screens`), newest last. */
  links: { code: string; url: string }[];
};

/** A TV page in a fresh browser profile of its own, at 1920×1080 unless told otherwise, on its home screen. */
export async function openTv(browser: Browser, opts: { viewport?: { width: number; height: number } } = {}): Promise<Tv> {
  const context = await browser.newContext({ viewport: opts.viewport ?? TV_VIEWPORT, isMobile: false, hasTouch: false });
  await ownAddress(context);
  const tv: Tv = { context, page: null as unknown as Page, links: [] };
  tv.page = await tvPage(context, (page) => recordLinks(tv, page));
  return tv;
}

/** A page of `context` at `/play/tv`, past Start: home, or the table this TV kept. */
export async function tvPage(context: BrowserContext, before?: (page: Page) => void): Promise<Page> {
  const page = await context.newPage();
  before?.(page);
  // Full screen would change the viewport under the test; the TV plays the same without it.
  await page.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
  await page.addInitScript(WATCH_HANDS);
  page.on("pageerror", (e) => console.log("TV pageerror", e.message));
  await page.goto("/play/tv");
  await page.getByRole("button", { name: "Start" }).click();
  return page;
}

/** Records every link the TV page is given, so a test can open the one its QR shows. */
function recordLinks(tv: Tv, page: Page = tv.page): void {
  page.on("response", async (res) => {
    if (!res.url().endsWith("/v1/screens") || res.request().method() !== "POST" || res.status() !== 201) return;
    const body = (await res.json().catch(() => null)) as { code?: string; url?: string } | null;
    if (body?.code && body.url) tv.links.push({ code: body.code, url: body.url });
  });
}

/** The link the TV shows now: the backup code read off the screen, and the URL its QR holds. */
export async function shownLink(tv: Tv, scope = ".tv-home-screen"): Promise<{ code: string; url: string }> {
  const shown = tv.page.locator(`${scope} .tv-code`);
  await expect(shown).toHaveText(/^[A-Z0-9]{6}$/);
  await expect(tv.page.locator(`${scope} .tv-qr svg`)).toBeVisible();
  const code = ((await shown.textContent()) ?? "").trim();
  await expect.poll(() => tv.links.some((l) => l.code === code), { message: "the TV's link for the code it shows" }).toBe(true);
  return tv.links.findLast((l) => l.code === code)!;
}

/** The TV makes a table from its poster; returns the table's code, read off its lobby. */
export async function tvMakes(tv: Tv, game: "Cat Tower" | "Tuna Tiles"): Promise<string> {
  await tv.page.getByRole("button", { name: game, exact: true }).click();
  return tvTable(tv.page);
}

/** The code of the table the TV's lobby shows. */
export async function tvTable(page: Page): Promise<string> {
  const code = page.locator(".tv-lobby .tv-code");
  await expect(code).toHaveText(/^[A-Z0-9]{5}$/);
  return ((await code.textContent()) ?? "").trim();
}

/** Phones that join `code` from its invite link, as people scanning the TV's lobby QR do. */
export async function phonesJoin(browser: Browser, code: string, names: string[], viewport?: { width: number; height: number }) {
  const phones = [];
  for (const [i, name] of names.entries()) {
    const device = PHONES[i % PHONES.length]!;
    const phone = await newPlayer(browser, name, { path: `/play/j/${code}`, context: { ...device, ...(viewport ? { viewport } : {}) } });
    await expect(phone.page).toHaveURL(new RegExp(`/play/t/${code}$`));
    phones.push(phone);
  }
  return phones;
}

/** Start, from whichever phone shows it. */
export async function startFromPhone(...pages: Page[]): Promise<void> {
  await expect.poll(async () => {
    for (const p of pages) if (await p.getByRole("button", { name: "Start", exact: true }).isVisible()) return true;
    return false;
  }).toBe(true);
  for (const p of pages) {
    const start = p.getByRole("button", { name: "Start", exact: true });
    if (await start.isVisible()) return start.click();
  }
}

/** The deck count the TV shows: it changes with every Cat Tower draw, whoever draws. */
export const tvDeck = async (tv: Page) => Number(await tv.locator(".tv-table #deck .pile-count").textContent());

/** The toy box count a page shows (TV, controller or full table). */
export const toyBox = async (page: Page) => Number(/(\d+)/.exec((await page.getByRole("img", { name: /^Toy box: \d+ pieces/ }).first().getAttribute("aria-label")) ?? "")?.[1]);

/** Whether this phone may play now: the live deck (`#deck`, a button) only shows on its turn. */
export const ctMyTurn = (page: Page) => page.locator("#deck:not([disabled])").isVisible();

/** What a screen reader hears for a card (the web player's `cardLabel`). */
function labelOf(id: CardId): string {
  const c = card(id);
  if (c.kind === "yarn") return "Yarn, wild";
  if (c.kind === "cucumber") return "Cucumber, skip";
  return `${c.value}, ${c.coat}`;
}

/** Card ids for a hand read as labels: any card of the same face plays the same. */
function idsFor(labels: string[]): CardId[] {
  const used = new Set<CardId>();
  return labels.map((label) => {
    const id = Array.from({ length: 108 }, (_, i) => i).find((i) => !used.has(i) && labelOf(i) === label)!;
    used.add(id);
    return id;
  });
}

/** Presses the hand card labelled `label` that isn't in a tray yet. */
async function pickFromHand(page: Page, label: string): Promise<void> {
  const trays = await page.locator(".ctl .tray").evaluateAll((els) => els.map((e) => e.getBoundingClientRect().toJSON() as DOMRect));
  const cards = page.locator(".card.mine .card-inner");
  const n = await cards.count();
  for (let i = 0; i < n; i++) {
    const c = cards.nth(i);
    if ((await c.getAttribute("aria-label")) !== label) continue;
    const b = await c.boundingBox();
    if (!b) continue;
    const [x, y] = [b.x + b.width / 2, b.y + b.height / 2];
    if (trays.some((t) => x >= t.left && x <= t.right && y >= t.top && y <= t.bottom)) continue;
    await c.press("Enter");
    return;
  }
  throw new Error(`no ${label} in the hand`);
}

/** Taps tray `i` where no card in it covers it (a tap on one of its cards takes that card out). */
async function tapTray(page: Page, i: number): Promise<void> {
  const at = await page.locator(".ctl .tray").nth(i).evaluate((tray) => {
    const r = tray.getBoundingClientRect();
    for (let y = r.bottom - 4; y > r.top; y -= 6)
      for (let x = r.right - 4; x > r.left; x -= 6) {
        const hit = document.elementFromPoint(x, y);
        if (hit && tray.contains(hit)) return { x, y };
      }
    return null;
  });
  if (!at) throw new Error(`tray ${i} is covered`);
  await page.mouse.click(at.x, at.y);
}

/**
 * Lays down the first level from the controller if the hand makes it: each group's cards into its
 * tray, then the paw. False when the hand doesn't make it (or this isn't the first level).
 */
async function layDownIfMade(page: Page): Promise<boolean> {
  const trays = page.locator(".ctl .tray");
  if ((await trays.count()) !== 2) return false;
  const labels = await page.locator(".card.mine .card-inner").evaluateAll((els) => els.map((e) => e.getAttribute("aria-label") ?? ""));
  const groups = findPhase(idsFor(labels), 0);
  if (!groups) return false;
  for (const [i, g] of groups.entries()) {
    for (const [k, id] of g.cards.entries()) {
      // Cards move into a tray: tell the hand from the trays once they have landed.
      await page.waitForTimeout(400);
      await pickFromHand(page, labelOf(id));
      await tapTray(page, i);
      await expect(trays.nth(i)).toHaveAttribute("aria-label", new RegExp(`, ${k + 1} of \\d`));
    }
  }
  const lay = page.locator("#lay");
  await expect(lay).toBeVisible();
  await lay.click();
  await expect(lay).toBeHidden();
  return true;
}

/**
 * One Cat Tower turn on the controller, if it's this phone's: draw from the deck, lay down the
 * level when the hand makes it (and `layDown` is on), then discard the last card by tap. Returns
 * what it did, or null off turn.
 */
export async function controllerTurn(page: Page, opts: { layDown?: boolean } = {}): Promise<null | "turn" | "laid"> {
  if (!(await ctMyTurn(page))) return null;
  const cards = page.locator(".card.mine .card-inner");
  const before = await cards.count();
  await page.locator("#deck").click();
  await expect(cards).toHaveCount(before + 1);
  const laid = opts.layDown ? await layDownIfMade(page) : false;
  // Pick the right-most card, then the Discard button (a hit list, once laid down, may cover the pile).
  await expect.poll(() => cards.count()).toBeGreaterThan(0);
  await cards.last().press("Enter");
  await page.locator("#discard-btn:not([disabled])").click();
  const skip = page.getByRole("dialog", { name: "Skip whose turn?" });
  if (await skip.isVisible().catch(() => false)) await skip.locator("button").first().click();
  await expect(page.locator("#deck:not([disabled])")).toBeHidden();
  return laid ? "laid" : "turn";
}

/**
 * Plays Cat Tower turns from these phones until `turns` were played; each must show on the TV
 * (its deck goes down). `each` runs after every turn.
 */
export async function playCatTowerTurns(tv: Page, phones: Page[], turns: number, opts: { layDown?: boolean; each?: () => Promise<void> } = {}) {
  let played = 0;
  let laid = 0;
  for (let i = 0; i < 120 && played < turns; i++) {
    for (const p of phones) {
      if (played >= turns) break;
      const before = await tvDeck(tv);
      const did = await controllerTurn(p, { layDown: opts.layDown });
      if (!did) continue;
      played++;
      if (did === "laid") laid++;
      await expect.poll(() => tvDeck(tv)).toBeLessThan(before);
      await opts.each?.();
    }
    await tv.waitForTimeout(200);
  }
  expect(played).toBe(turns);
  return { played, laid };
}

/**
 * One Tuna Tiles turn, if it's this phone's: a hint's play when it makes one, else a draw. With
 * `tv`, a play is first seen there as the phone's live draft.
 */
export async function tilesTurn(page: Page, opts: { tv?: Page } = {}): Promise<null | "played" | "drew"> {
  const button = page.locator("#play-btn:not([disabled])");
  if (!(await button.isVisible())) return null;
  await page.locator("#hint").click();
  // The hint answers from its worker: a play turns the button to "Play", or it wiggles.
  await page.waitForTimeout(800);
  const play = page.locator("#play-btn", { hasText: "Play" });
  if ((await play.isVisible()) && (await play.isEnabled())) {
    if (opts.tv) await expect(opts.tv.locator(".tv-table .tile.draft").first()).toBeVisible();
    await play.click();
    await expect(page.locator("#play-btn:not([disabled])")).toBeHidden();
    return "played";
  }
  if (await play.isVisible()) await page.getByRole("button", { name: "Start over" }).click();
  await page.locator("#play-btn", { hasText: /Draw|Pass/ }).click();
  await expect(page.locator("#play-btn:not([disabled])")).toBeHidden();
  return "drew";
}

/** A phone's Menu, then Forfeit, confirmed. */
export async function forfeit(page: Page): Promise<void> {
  await page.getByRole("button", { name: "Menu" }).click();
  await page.getByRole("button", { name: "Forfeit" }).click();
  await page.locator("#forfeit").click();
}

/**
 * Watches the TV page from its first paint: any hand card or rack piece ever put in its DOM, even
 * for a frame, is noted (`handEverOnTv` reads it).
 */
const WATCH_HANDS = `
  window.__handSeen = [];
  const look = () => {
    for (const el of document.querySelectorAll(".card.mine, .tile.mine")) window.__handSeen.push(el.className);
  };
  new MutationObserver(look).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] });
`;

/** Every hand card or rack piece the TV page ever had in its DOM (none, for a TV). */
export const handEverOnTv = (tv: Page): Promise<string[]> => tv.evaluate(() => (window as unknown as { __handSeen: string[] }).__handSeen.slice(0, 10));

/** What a TV must never show: anyone's hand or rack. */
export async function noHandOnTv(tv: Page): Promise<void> {
  await expect(tv.locator(".card.mine")).toHaveCount(0);
  await expect(tv.locator(".tile.mine")).toHaveCount(0);
  await expect(tv.getByRole("group", { name: "Your hand" })).toHaveCount(0);
  await expect(tv.getByRole("group", { name: "Your rack" })).toHaveCount(0);
  await expect(tv.locator("#view-switch")).toHaveCount(0);
}

/** Every visible box under `root` that leaves the viewport. */
export async function outsideViewport(page: Page, selectors: string[]): Promise<string[]> {
  return page.evaluate((sel) => {
    const out: string[] = [];
    for (const s of sel)
      for (const el of document.querySelectorAll(s)) {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height || getComputedStyle(el).visibility === "hidden") continue;
        if (r.left < -0.5 || r.top < -0.5 || r.right > innerWidth + 0.5 || r.bottom > innerHeight + 0.5) out.push(`${s} ${Math.round(r.left)},${Math.round(r.top)} ${Math.round(r.right)},${Math.round(r.bottom)}`);
      }
    return out;
  }, selectors);
}
