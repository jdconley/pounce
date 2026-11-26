import { expect, type Page } from "@playwright/test";

/**
 * Playing Birdwatch in a browser the way a person does: from what the table shows. "keys" plays
 * by keyboard (focus a card, Enter; 1 to 4 for trump), "taps" by tapping each card's corner (a
 * card's corner is what shows in a tight fan).
 */
export type How = "keys" | "taps";

export type BwStats = { steps: number; bids: number; nests: number; trumps: number; partners: number; plays: number; curtains: number; hands: Set<string> };
export const newStats = (): BwStats => ({ steps: 0, bids: 0, nests: 0, trumps: 0, partners: 0, plays: 0, curtains: 0, hands: new Set() });

const handCards = (page: Page) => page.locator(".bw-hand-card");

/** Taps a hand card where it shows in the fan: its top-left corner, under its numeral. */
async function tapCorner(page: Page, i: number): Promise<void> {
  const card = handCards(page).nth(i);
  const box = await card.boundingBox();
  if (!box) return;
  await page.mouse.click(box.x + box.width * 0.22, box.y + box.height * 0.22);
}

async function pickCard(page: Page, i: number, how: How): Promise<void> {
  if (how === "taps") return tapCorner(page, i);
  await handCards(page).nth(i).locator("button").focus();
  await page.keyboard.press("Enter");
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
    const words = (await page.locator(".bw-nest .bw-cue-line").textContent()) ?? "";
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
  if (await page.locator(".bw-cue.mine").isVisible()) {
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
      const summary = page.locator(".bw-summary .title");
      if ((await summary.count()) > 0)
        stats.hands.add(
          (await summary
            .first()
            .textContent()
            .catch(() => null)) ?? "",
        );
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
