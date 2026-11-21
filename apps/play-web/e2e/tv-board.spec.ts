import { mkdirSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { dailyPhone, type DailyPhone } from "./daily-phone";
import { openTv, shownLink, tvPage, TV_VIEWPORT, type Tv } from "./tv-helpers";

import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyResult } from "@pounce/play-api/daily/module";

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

/** A family of six across the four games, everyone done in some and playing in others. */
function familyBoard(): BoardAnswer {
  const people = [
    ["me", "Mom", 3],
    ["pr_dad", "Dad", 1],
    ["pr_kid", "Kid", 5],
    ["pr_gpa", "Grandpa", 0],
    ["pr_nana", "Nana", 7],
    ["pr_bart", "Bartholomew Wiggles", 6],
  ] as const;
  const games = ["sniff", "nine-lives", "cat-nap", "box-fort"] as const;
  const result = (game: (typeof games)[number], i: number): DailyResult => ({
    game,
    date: "2026-11-23",
    number: 12,
    outcome: game === "box-fort" ? "done" : i === 4 ? "gaveUp" : "solved",
    timeMs: 95_000 + i * 41_000,
    hints: i === 3 ? 1 : 0,
    progress: 1,
    tooFast: false,
    ...(game === "sniff" ? { guesses: 3 + (i % 4) } : {}),
    ...(game === "box-fort" ? { points: 2400 - i * 310 } : {}),
  });
  return {
    date: "2026-11-23",
    games: games.map((game, g) => ({
      game,
      number: 12,
      rows: people.map(([player, name, cat], i) =>
        i < 6 - g ? { player, name, cat, rank: i + 1, result: result(game, i), playing: null } : { player, name, cat, rank: null, result: null, playing: { progress: 0.4 } },
      ),
    })),
    dish: { rows: people.map(([player, name, cat], i) => ({ player, name, cat, rank: i + 1, points: 16 - i * 3, crowns: i === 0 ? ["sniff", "nine-lives"] : [], ended: 4 })) },
    tvs: 1,
  };
}

test("a whole family fits each game's board, nothing under 28 at 1080p", async ({ browser }) => {
  const context = await browser.newContext({ viewport: TV_VIEWPORT, isMobile: false, hasTouch: false });
  // A board kept, and its socket answered here with the family's board.
  await context.addInitScript(() => localStorage.setItem("pounce.tv.board", JSON.stringify({ token: "F".repeat(22), until: Date.now() + 86_400_000 })));
  await context.routeWebSocket(/\/v1\/daily\/board\/ws/, (ws) => ws.send(JSON.stringify({ t: "board", board: familyBoard() })));
  const page = await tvPage(context);
  await expect(page.locator(".tv-board-game")).toHaveCount(4);
  for (const card of await page.locator(".tv-board-game").all()) {
    await expect(card.locator(".tv-board-row")).toHaveCount(6);
    await expect(card.locator(".tv-board-more")).toHaveCount(0);
    const size = await card.evaluate((el) => ({
      sh: el.scrollHeight,
      ch: el.clientHeight,
      sw: el.scrollWidth,
      cw: el.clientWidth,
      parts: [...el.children].map((c) => `${c.className}:${Math.round(c.getBoundingClientRect().height)}`),
      rows: [...el.querySelectorAll(".tv-board-row")].map((r) => Math.round(r.getBoundingClientRect().height)),
      // Anything that pokes out of the card, by how much.
      out: [...el.querySelectorAll("*")].filter((d) => d.getBoundingClientRect().bottom > el.getBoundingClientRect().bottom + 1).map((d) => `${d.className}:${Math.round(d.getBoundingClientRect().bottom - el.getBoundingClientRect().bottom)}`),
    }));
    expect(size.sh <= size.ch + 1 && size.sw <= size.cw + 1, `the card holds six rows: ${JSON.stringify(size)}`).toBe(true);
  }
  const smallest = await page.locator(".tv-board-row .tv-row-name, .tv-board-row .tv-row-result, .tv-board-row .tv-rank").evaluateAll((els) => Math.min(...els.map((e) => parseFloat(getComputedStyle(e).fontSize))));
  expect(smallest, "the smallest row text, px at 1080p").toBeGreaterThanOrEqual(28);
  await shot(page, "board-family");
  await context.close();
});
