import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer } from "./helpers";
import { cell, enter, lives, openToday, readBoard, wrongDigit } from "./nine-lives-helpers";

/**
 * Nine Lives on a real network, and the Dish's clock (docs/daily-protocol.md "Active time"):
 *
 * - On slow 4G (about 400 ms each way, Chrome's own throttling), a number shows at once as
 *   "checking", never as right, and turns red (or locks) when the server answers.
 * - Offline, it stays "checking" and the screen says Reconnecting; back online, the answer lands.
 * - The clock counts only play time: a hidden tab and a trip to the Dish don't add to the result,
 *   and the time before the pause, with no move, still counts (the pause's empty batch).
 */

/** Chrome's network throttling, as a slow 4G phone sees it. */
async function slow4g(page: Page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 400, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 });
  return cdp;
}

test("on slow 4G a number shows at once as checking, then turns red; offline it waits and says so", async ({ browser }, info) => {
  test.skip(!/chrome/.test(info.project.name), "Chrome's throttling");
  const ruby = await newPlayer(browser, "Ruby");
  const { page } = ruby;
  const solution = await openToday(page);
  const open = (await readBoard(page)).filter((c) => c.d === 0).map((c) => c.i);
  const cdp = await slow4g(page);

  // Wrong: checking at once, then red once the answer is back, with a life gone.
  const a = open[0]!;
  await cell(page, a).click();
  const t0 = Date.now();
  await page.keyboard.press(String(wrongDigit(solution, a)));
  await expect(cell(page, a)).toHaveAttribute("aria-label", /, checking$/, { timeout: 300 });
  const shownMs = Date.now() - t0;
  await page.screenshot({ path: info.outputPath("nine-lives-slow-checking.png") });
  await expect(cell(page, a)).toHaveAttribute("aria-label", /, wrong$/);
  const answeredMs = Date.now() - t0;
  await expect(lives(page)).toHaveAccessibleName("2 lives left");
  await page.waitForTimeout(500);
  await page.screenshot({ path: info.outputPath("nine-lives-slow-wrong.png") });
  console.log(`slow 4g: checking after ${shownMs} ms, wrong after ${answeredMs} ms`);
  // One round trip on slow 4G, never a batch's second on top of it.
  expect(answeredMs).toBeLessThan(2500);

  // Right: checking, then locked.
  const b = open[1]!;
  await enter(page, b, solution[b]!);
  await expect(cell(page, b)).toHaveAttribute("aria-label", new RegExp(`, ${solution[b]}$`));

  // Offline: the number stays checking, never taken, and the screen says Reconnecting.
  await cdp.send("Network.emulateNetworkConditions", { offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await page.context().setOffline(true);
  const c = open[2]!;
  await cell(page, c).click();
  await page.keyboard.press(String(solution[c]));
  await expect(page.getByRole("status").filter({ hasText: "Reconnecting" })).toBeVisible();
  await page.waitForTimeout(1500);
  await expect(cell(page, c)).toHaveAttribute("aria-label", /, checking$/);
  await page.screenshot({ path: info.outputPath("nine-lives-offline.png") });
  await page.context().setOffline(false);
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await expect(cell(page, c)).toHaveAttribute("aria-label", new RegExp(`, ${solution[c]}$`), { timeout: 20_000 });
  await expect(page.getByText("Reconnecting")).toBeHidden();
  await closeAll(ruby.context);
});

test("the clock counts only play time: a hidden tab and a trip to the Dish don't count", async ({ browser }) => {
  const max = await newPlayer(browser, "Max");
  const { page } = max;
  const solution = await openToday(page);
  const open = (await readBoard(page)).filter((c) => c.d === 0).map((c) => c.i);
  const t0 = Date.now();
  await enter(page, open[0]!, solution[open[0]!]!);
  const empties: number[] = [];
  page.on("request", (r) => {
    const body = r.url().includes("/moves") ? (r.postDataJSON() as { moves: unknown[]; activeMs: number } | null) : null;
    if (body && body.moves.length === 0) empties.push(body.activeMs);
  });
  // Three seconds of thinking with no move: play time, kept by the pause's empty batch.
  await page.waitForTimeout(3000);

  // The tab hides for 6 seconds.
  const hide = (hidden: boolean) =>
    page.evaluate((h) => {
      Object.defineProperty(document, "visibilityState", { configurable: true, get: () => (h ? "hidden" : "visible") });
      document.dispatchEvent(new Event("visibilitychange"));
    }, hidden);
  await hide(true);
  await page.waitForTimeout(6000);
  await hide(false);

  // Off to the Dish for 6 seconds, then back to the same run.
  await page.getByRole("button", { name: "Dish" }).first().click();
  await expect(page).toHaveURL(/\/play\/daily$/);
  await page.waitForTimeout(6000);
  await page.getByRole("button", { name: "Play Nine Lives" }).click();
  await expect(page.getByRole("group", { name: "Nine Lives" })).toBeVisible();
  await expect(cell(page, open[0]!)).toHaveAttribute("aria-label", new RegExp(`, ${solution[open[0]!]}$`));

  // Give up: the result's time leaves out the 12 seconds away.
  const answer = page.waitForResponse((r) => r.url().includes("/giveup"));
  await page.getByRole("button", { name: "Give up" }).click();
  await page.locator("#give-up-yes").click();
  const { result } = (await (await answer).json()) as { result: { timeMs: number; percent: number } };
  const wall = Date.now() - t0;
  console.log(`active time: result ${result.timeMs} ms, wall ${wall} ms`);
  expect(result.timeMs).toBeLessThan(wall - 10_000);
  expect(result.timeMs, "the thinking before the tab hid").toBeGreaterThanOrEqual(3000);
  expect(empties.length, "an empty batch as the clock paused").toBeGreaterThanOrEqual(1);
  expect(empties[0]).toBeGreaterThanOrEqual(3000);
  // The end: Gave up, and how far it got.
  await expect(page.getByRole("heading", { name: "Gave up" })).toBeVisible();
  await expect(page.locator(".dd-end-result")).toHaveText(`${result.percent}%`);
  await closeAll(max.context);
});
