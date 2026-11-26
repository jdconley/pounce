import { expect, type Page } from "@playwright/test";

import { tableCode } from "./helpers";

/**
 * Playing Birdwatch in a browser the way a person does: from what the table shows. Every read of
 * something that can vanish (a summary, a card) is one that never waits: a driver waiting on the
 * table while the table waits on the driver is a game that never ends. The spec also caps every
 * action's wait (`actionTimeout`), so a wait like that fails in seconds, not at the test's end.
 * "keys" plays by keyboard (focus a card, Enter; 1 to 4 for trump), "taps" by tapping each card's
 * corner (a card's corner is what shows in a tight fan).
 */
export type How = "keys" | "taps";

export type BwStats = { steps: number; bids: number; nests: number; trumps: number; partners: number; plays: number; curtains: number; hands: Set<string> };
export const newStats = (): BwStats => ({ steps: 0, bids: 0, nests: 0, trumps: 0, partners: 0, plays: 0, curtains: 0, hands: new Set() });

const handCards = (page: Page) => page.locator(".bw-hand-card");

/**
 * A point on the page where hand card `i` is what a finger would touch: in a fan, cards overlap
 * and turn, so its box's corner can be its neighbour. Tries points from its top-left inward.
 */
export async function cardPoint(page: Page, i: number): Promise<{ x: number; y: number } | null> {
  // Over all the cards at once (no wait for card `i`): the hand may have changed since `i` was picked.
  return handCards(page).evaluateAll((els, i) => {
    const el = els[i];
    if (!el) return null;
    const r = el.getBoundingClientRect();
    for (const fy of [0.25, 0.4, 0.15, 0.55]) {
      for (const fx of [0.2, 0.3, 0.12, 0.4, 0.5, 0.6]) {
        const x = r.left + r.width * fx;
        const y = r.top + r.height * fy;
        if (document.elementFromPoint(x, y)?.closest(".bw-hand-card") === el) return { x, y };
      }
    }
    return null;
  }, i);
}

/** Taps a hand card where it shows in the fan. */
async function tapCorner(page: Page, i: number): Promise<void> {
  const at = await cardPoint(page, i);
  if (at) await page.mouse.click(at.x, at.y);
}

async function pickCard(page: Page, i: number, how: How): Promise<void> {
  if (how === "taps") return tapCorner(page, i);
  // Focus it without waiting for it (it may have left the hand), then Enter.
  const focused = await handCards(page).evaluateAll((els, i) => {
    const button = els[i]?.querySelector("button");
    button?.focus();
    return button !== undefined && button !== null && document.activeElement === button;
  }, i);
  if (focused) await page.keyboard.press("Enter");
}

/** Holds the curtain's button until the hand shows. */
async function holdCurtain(page: Page): Promise<void> {
  const hold = page.getByRole("button", { name: "Hold to see your hand" });
  const box = await hold.boundingBox();
  if (!box) return;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(900);
  await page.mouse.up();
}

/**
 * One move, if this page has one to make: lifts the curtain, bids (the least, while `bid` says so)
 * or passes, puts back the nest, names trump, calls a partner, or plays the first card it may.
 * "over" once the game-over dialog is up; null when nothing is this page's to do.
 */
export async function bwStep(page: Page, how: How, stats: BwStats, opts: { bid?: () => boolean } = {}): Promise<"over" | "acted" | null> {
  if (await page.locator(".game-over").isVisible()) return "over";
  if (await page.getByRole("button", { name: "Hold to see your hand" }).isVisible()) {
    await holdCurtain(page);
    stats.curtains++;
    return "acted";
  }
  const label = await page.locator(".bw-hand-zone").count();
  if (label === 0) return null;
  const bid = page.locator("#bw-bid:not([disabled])");
  if (await bid.isVisible()) {
    stats.steps++;
    await expect(page.locator("#bw-pass")).toBeEnabled();
    // Keys go to the table, not to a card or button that has focus.
    if (how === "keys") await page.evaluate(() => (document.activeElement as HTMLElement | null)?.blur());
    if (opts.bid?.() ?? false) {
      if (how === "keys") await page.keyboard.press("Enter");
      else await bid.click();
      stats.bids++;
    } else if (how === "keys") await page.keyboard.press("p");
    else await page.locator("#bw-pass").click();
    await expect(page.locator("#bw-bid"))
      .toBeHidden({ timeout: 10_000 })
      .catch(() => undefined);
    return "acted";
  }
  const done = page.locator("#bw-nest-done");
  if (await done.isVisible()) {
    // The cards fly in from the feeder; then put back as many as it held, from the right of the fan.
    await page.waitForTimeout(500);
    if (how === "keys") await page.evaluate(() => (document.activeElement as HTMLElement | null)?.blur());
    const words = (await page.locator(".bw-nest .bw-cue-line").allTextContents()).join(" ");
    const need = Number(/\d+/.exec(words)?.[0] ?? 0);
    const n = await handCards(page).count();
    for (let k = 0; k < need; k++) await pickCard(page, n - 1 - k, how);
    await expect(page.locator(".bw-nest .bw-cue-line")).toHaveText("Ready");
    if (how === "keys") {
      await page.locator("#bw-nest-done").focus();
      await page.keyboard.press("Enter");
    } else await done.click();
    await expect(done).toBeHidden({ timeout: 10_000 });
    stats.nests++;
    stats.steps++;
    return "acted";
  }
  const suits = page.locator(".bw-trumps .bw-suit");
  if (await suits.first().isVisible()) {
    // Live once the put-back has been answered.
    await expect(suits.first()).toBeEnabled();
    const all = await suits.evaluateAll((els) => els.map((el) => el.classList.contains("hint")));
    const i = Math.max(0, all.indexOf(true));
    if (how === "keys") await page.keyboard.press(String(i + 1));
    else await suits.nth(i).click();
    await expect(suits.first()).toBeHidden({ timeout: 10_000 });
    stats.trumps++;
    stats.steps++;
    return "acted";
  }
  const partner = page.locator(".bw-partner .bw-mini");
  if (await partner.first().isVisible()) {
    await expect(partner.first()).toBeEnabled();
    await partner.first().click();
    await expect(page.locator(".bw-partner")).toBeHidden({ timeout: 10_000 });
    stats.partners++;
    stats.steps++;
    return "acted";
  }
  // My turn to play, once the server has said which cards may go.
  if (await page.locator(".bw-table.choosing").isVisible()) {
    const dims = await handCards(page).evaluateAll((els) => els.map((el) => el.classList.contains("dim")));
    const i = dims.indexOf(false);
    if (i < 0) return null;
    const before = dims.length;
    if (how === "taps") {
      // Tap lifts it, a second tap plays it.
      await tapCorner(page, i);
      await tapCorner(page, i);
    } else await pickCard(page, i, how);
    await expect.poll(() => handCards(page).count(), { timeout: 10_000 }).toBeLessThan(before);
    stats.plays++;
    stats.steps++;
    return "acted";
  }
  return null;
}

/** Plays every page's moves until the game is over on all of them; the stats of the run. */
export async function playToTheEnd(pages: Page[], how: How[], opts: { bidOnce?: boolean; minutes?: number } = {}): Promise<BwStats> {
  const stats = newStats();
  let wonABid = false;
  const deadline = Date.now() + (opts.minutes ?? 12) * 60_000;
  const over = new Set<number>();
  while (over.size < pages.length) {
    if (Date.now() > deadline) throw new Error(`Birdwatch didn't end in ${opts.minutes ?? 12} minutes: ${JSON.stringify({ ...stats, hands: stats.hands.size })}`);
    let any = false;
    for (const [k, page] of pages.entries()) {
      if (over.has(k)) continue;
      // A read that never waits: the summary is gone the moment the next hand is dealt, and a
      // waiting read (textContent) would then wait for the next one, which needs this player's move.
      for (const title of await page.locator(".bw-summary .title").allTextContents()) stats.hands.add(title);
      // Bid the least until a bid is won once, so every game also takes the feeder and names trump.
      const r = await bwStep(page, how[k] ?? "keys", stats, { bid: () => !wonABid && (opts.bidOnce ?? true) });
      if (stats.nests > 0) wonABid = true;
      if (r === "over") over.add(k);
      if (r === "acted") any = true;
    }
    if (!any) await pages[0]!.waitForTimeout(150);
  }
  return stats;
}

/** A Birdwatch table from Home's shelf, its rule set picked, House Cats in the seats to `seats`. */
export async function birdTable(page: Page, rules: "Official" | "Tucker" | "Friesen", seats: number): Promise<string> {
  await page.getByRole("button", { name: "Play Birdwatch" }).click();
  const code = await tableCode(page);
  // A first table gets three House Cats, so Start is lit at once.
  await expect(page.getByRole("button", { name: "House Cat" }).nth(2)).toBeVisible();
  await page.getByRole("radio", { name: rules }).click();
  await expect(page.getByRole("radio", { name: rules })).toHaveAttribute("aria-checked", "true");
  for (let n = 4; n < seats; n++) {
    const before = await page.locator(".lobby-seat.bot").count();
    await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await expect(page.locator(".lobby-seat.bot")).toHaveCount(before + 1);
  }
  return code;
}
