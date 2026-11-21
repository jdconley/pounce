import { mkdirSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { dailyPhone, type DailyPhone } from "./daily-phone";
import { openTv, shownLink, type Tv } from "./tv-helpers";

/**
 * Tonight's board on the browser TV (daily games design §8), against a server with the Daily Dish
 * on and its test game (`DAILY=on`, `DAILY_TEST=on`). The phones are plain HTTP (`daily-phone.ts`);
 * the TV page is what's looked at. `TV_BOARD_SHOTS=1` saves 1080p screenshots.
 */

const SHOTS = process.env.TV_BOARD_SHOTS ? new URL("../../../docs/screenshots/tv-board/", import.meta.url) : null;
if (SHOTS) mkdirSync(SHOTS, { recursive: true });
const shot = async (page: Page, name: string) => {
  if (!SHOTS) return;
  // Every picture on the page decoded, and entrances finished, so the shot shows what a person sees.
  await page.waitForFunction(() => [...document.images].every((i) => i.complete));
  await page.screenshot({ path: new URL(`web-${name}.png`, SHOTS).pathname, animations: "disabled" });
};

export const boardPoster = (page: Page) => page.getByRole("button", { name: "Tonight's board" });
const board = (page: Page) => page.locator(".tv-board");
const row = (page: Page, game: string, player = "me") => page.locator(`.tv-board-game[data-game="${game}"] .tv-board-row[data-player="${player}"]`);

/** A TV on its home, linked to `phone`'s board from Tonight's board's own link. */
async function linked(tv: Tv, phone: DailyPhone): Promise<void> {
  await expect(boardPoster(tv.page)).toBeVisible();
  await boardPoster(tv.page).click();
  await expect(tv.page.getByRole("button", { name: "Back" })).toBeFocused();
  const { code } = await shownLink(tv, ".tv-board-link");
  expect(await phone.linkBoard(code)).toBe(200);
  await expect(board(tv.page)).toBeVisible();
  await expect(tv.page.locator('.tv-board-game[data-game="test"]')).toBeVisible();
}

/** The page again, with its "Press OK for sound" pressed. */
async function reloadTv(page: Page): Promise<void> {
  await page.reload();
  const wake = page.getByRole("button", { name: "Press OK for sound" });
  const start = page.getByRole("button", { name: "Start", exact: true });
  await expect(wake.or(start)).toBeVisible();
  await (await wake.isVisible() ? wake : start).click();
}

test.describe("Tonight's board on the TV", () => {
  test("a phone links the board with the poster's code, and the TV keeps it", async ({ browser }) => {
    const tv = await openTv(browser);
    await expect(tv.page.locator(".tv-home-screen .tv-qr svg")).toBeVisible();
    await shot(tv.page, "home");
    await boardPoster(tv.page).click();
    await expect(tv.page.locator(".tv-board-link .tv-code")).toHaveText(/^[A-Z0-9]{6}$/);
    await shot(tv.page, "link");
    await tv.page.keyboard.press("Escape");
    await expect(tv.page.locator(".tv-board-link")).toBeHidden();
    const mom = await dailyPhone("Mom");
    await linked(tv, mom);
    await expect(tv.page.locator(".tv-dish-empty")).toContainText("Nobody has played yet");
    await shot(tv.page, "board-empty");
    await reloadTv(tv.page);
    await expect(board(tv.page)).toBeVisible();
    await tv.context.close();
  });

  test("home's own link takes a board too", async ({ browser }) => {
    const tv = await openTv(browser);
    const { code } = await shownLink(tv);
    const mom = await dailyPhone("Mom");
    expect(await mom.linkBoard(code)).toBe(200);
    await expect(board(tv.page)).toBeVisible();
    await tv.context.close();
  });

  test("a result arrives live: the row cheers, and the Dish counts it", async ({ browser }) => {
    const tv = await openTv(browser);
    const mom = await dailyPhone("Mom", 3);
    await linked(tv, mom);
    const { run, target } = await mom.start();
    await mom.moves(run, 0, target);
    await expect(row(tv.page, "test")).toHaveClass(/cheer/);
    await expect(row(tv.page, "test").locator(".tv-row-result")).toHaveText(/^\d+:\d{2}$/);
    await expect(tv.page.locator('.tv-dish-row[data-player="me"] .tv-dish-points')).toHaveText("4");
    await shot(tv.page, "cheer");
    await expect(row(tv.page, "test")).not.toHaveClass(/cheer/, { timeout: 5000 });
    await tv.context.close();
  });

  test("a long name fits its card", async ({ browser }) => {
    const tv = await openTv(browser);
    const phone = await dailyPhone("Bartholomew Wiggles", 6);
    await linked(tv, phone);
    const { run, target } = await phone.start();
    await phone.moves(run, 0, target);
    await expect(row(tv.page, "test")).toBeVisible();
    // Measured at rest: the cheer's slide-in starts off to the right.
    await expect(row(tv.page, "test")).not.toHaveClass(/cheer/, { timeout: 5000 });
    await expect(row(tv.page, "test").locator(".tv-row-name")).toHaveText("Bartholomew Wiggles");
    await shot(tv.page, "long-name");
    for (const box of [tv.page.locator(".tv-board-game").first(), tv.page.locator(".tv-dish-row").first()]) {
      const fits = await box.evaluate((el) => el.scrollWidth <= el.clientWidth + 1);
      expect(fits, "the card holds the long name").toBe(true);
    }
    await tv.context.close();
  });

  test("the watch card: Not now is focused, Watch shows the run, its end goes back to the board", async ({ browser }) => {
    const tv = await openTv(browser);
    const mom = await dailyPhone("Mom", 3);
    await linked(tv, mom);
    const { run, target } = await mom.start();
    // The paw holds the remote's focus when the card comes up: the card takes it anyway.
    await tv.page.getByRole("button", { name: "Menu" }).focus();
    expect(await mom.showOnTv(run, true)).toBe(204);
    const card = tv.page.locator(".tv-watch-card");
    await expect(card).toContainText("Mom is playing Test. Spoilers.");
    await expect(tv.page.getByRole("button", { name: "Not now" })).toBeFocused();
    await shot(tv.page, "card");
    await tv.page.keyboard.press("ArrowLeft");
    await expect(tv.page.getByRole("button", { name: "Watch" })).toBeFocused();
    await tv.page.keyboard.press("Enter");
    const watching = tv.page.locator('.tv-watch[data-game="test"]');
    await expect(watching.locator(".tv-watch-count")).toHaveText("0");
    await mom.moves(run, 0, 1);
    await expect(watching.locator(".tv-watch-count")).toHaveText("1");
    await shot(tv.page, "watch");
    await mom.moves(run, 1, target);
    await expect(tv.page.locator(".tv-watch-ended")).toContainText("Solved");
    await shot(tv.page, "watch-ended");
    await expect(board(tv.page)).toBeVisible({ timeout: 10_000 });
    await tv.context.close();
  });

  test("the watch card goes by itself after 20 seconds", async ({ browser }) => {
    const tv = await openTv(browser);
    const mom = await dailyPhone("Mom");
    await linked(tv, mom);
    const { run } = await mom.start();
    await mom.showOnTv(run, true);
    const card = tv.page.locator(".tv-watch-card");
    await expect(card).toBeVisible();
    await tv.page.waitForTimeout(18_000);
    await expect(card).toBeVisible();
    await expect(card).toBeHidden({ timeout: 5000 });
    await tv.context.close();
  });

  test("Unlink in the TV's menu goes home, and the TV forgets the board", async ({ browser }) => {
    const tv = await openTv(browser);
    await linked(tv, await dailyPhone("Mom"));
    await tv.page.keyboard.press("Escape");
    await expect(tv.page.getByRole("button", { name: "Play a game" })).toBeFocused();
    await shot(tv.page, "menu");
    await tv.page.getByRole("button", { name: "Unlink" }).click();
    await expect(boardPoster(tv.page)).toBeVisible();
    await reloadTv(tv.page);
    await expect(boardPoster(tv.page)).toBeVisible();
    await tv.context.close();
  });

  test("Play a game keeps the board: its poster opens it again", async ({ browser }) => {
    const tv = await openTv(browser);
    await linked(tv, await dailyPhone("Mom"));
    await tv.page.keyboard.press("Escape");
    await tv.page.getByRole("button", { name: "Play a game" }).click();
    await expect(boardPoster(tv.page)).toBeVisible();
    await boardPoster(tv.page).click();
    await expect(board(tv.page)).toBeVisible();
    await tv.context.close();
  });

  test("unlinked from the phone, the TV goes home", async ({ browser }) => {
    const tv = await openTv(browser);
    const mom = await dailyPhone("Mom");
    await linked(tv, mom);
    expect(await mom.unlink()).toBe(204);
    await expect(boardPoster(tv.page)).toBeVisible();
    await reloadTv(tv.page);
    await expect(board(tv.page)).toBeHidden();
    await tv.context.close();
  });
});
