import { mkdirSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { dailyPhone, firstMove, type DailyPhone } from "./daily-phone";
import { closeAll, newPlayer } from "./helpers";
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
    // The test game's own watch view, from the web registry: the count so far.
    await expect(watching.locator(".dd-test-count")).toHaveText(`0 / ${target}`);
    await mom.moves(run, 0, 1);
    await expect(watching.locator(".dd-test-count")).toHaveText(`1 / ${target}`);
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
  test("a phone's Dish puts the board on the TV, shows it's on, and its run lands live", async ({ browser }) => {
    const tv = await openTv(browser);
    const jo = await newPlayer(browser, "Jo");
    const { page } = jo;
    await page.getByRole("button", { name: "Open the Dish" }).click();
    const tip = page.getByRole("button", { name: "Dismiss tip" });
    if (await tip.isVisible()) await tip.click();
    await expect(page.getByRole("button", { name: "Unlink" })).toHaveCount(0);
    await page.getByRole("button", { name: "Show board on TV" }).click();
    await boardPoster(tv.page).click();
    const { code } = await shownLink(tv, ".tv-board-link");
    await page.getByLabel("TV code").fill(code);
    await page.getByRole("button", { name: "Show", exact: true }).click();
    await expect(page.getByText("On the TV")).toBeVisible();
    await expect(board(tv.page)).toBeVisible();
    // The phone hears the TV come (`tvs`): Unlink appears on its Dish.
    await expect(page.getByRole("button", { name: "Unlink" })).toBeVisible();
    // Jo finishes a run on the phone; the TV's board cheers it as it lands.
    await page.goto("/play/daily/test");
    const step = page.getByRole("button", { name: "Step" });
    await expect(page.getByTestId("test-count")).toBeVisible();
    while (await step.isEnabled()) await step.click();
    await expect(row(tv.page, "test")).toHaveClass(/cheer/);
    await expect(row(tv.page, "test").locator(".tv-row-result")).toHaveText(/^\d+:\d{2}$/);
    await closeAll(tv.context, jo.context);
  });

  for (const [game, title] of [
    ["sniff", "Sniff"],
    ["nine-lives", "Nine Lives"],
    ["cat-nap", "Cat Nap"],
    ["box-fort", "Box Fort"],
  ] as const) {
    test(`watching ${title}: the card, its own view live at 1080p, and its end`, async ({ browser }) => {
      const tv = await openTv(browser);
      const mom = await dailyPhone("Mom", 3);
      await linked(tv, mom);
      expect((await mom.board()).tvs, "the phone's board counts the TV").toBe(1);
      const begun = await mom.begin(game);
      expect(await mom.showOnTv(begun.run, true)).toBe(204);
      await expect(tv.page.locator(".tv-watch-card")).toContainText(`Mom is playing ${title}. Spoilers.`);
      await expect(tv.page.getByRole("button", { name: "Not now" })).toBeFocused();
      await tv.page.keyboard.press("ArrowLeft");
      await tv.page.keyboard.press("Enter");
      const stage = tv.page.locator(`.tv-watch[data-game="${game}"] .tv-watch-stage`);
      // The game's own view (the registry's, in its own chunk), not the placeholder.
      await expect(stage.locator(".tv-watch-placeholder")).toHaveCount(0);
      await expect.poll(() => stage.evaluate((el) => el.querySelectorAll("*").length)).toBeGreaterThan(3);
      const before = await stage.innerHTML();
      const sent = await mom.send(begun.run, begun.seq, [firstMove(game, begun)]);
      expect(sent.ok).toBe(true);
      // The next frame redraws it.
      await expect.poll(() => stage.innerHTML()).not.toBe(before);
      await shot(tv.page, `watch-${game}`);
      // It fits 1080p: nothing past the stage (but a few pixels of a tilted tag) or off the screen.
      const fits = await stage.evaluate((el) => {
        const box = el.getBoundingClientRect();
        const slack = 6;
        const out = [...el.querySelectorAll("*")]
          .map((d) => ({ d, r: d.getBoundingClientRect() }))
          .filter(({ r }) => r.width > 0 && (r.left < box.left - slack || r.right > box.right + slack || r.top < box.top - slack || r.bottom > box.bottom + slack || r.top < 0 || r.bottom > innerHeight));
        return out.map(({ d, r }) => `${d.tagName}.${d.getAttribute("class")}:${Math.round(r.left)},${Math.round(r.top)},${Math.round(r.right)},${Math.round(r.bottom)}`).slice(0, 5);
      });
      expect(fits, `${title}'s watch view fits its stage at 1080p`).toEqual([]);
      // The run ends (a solve, or given up here): `watchEnd`, its result over the last frame, then the
      // board. (A run this quick is `tooFast`, so it stays off the board.)
      if (!sent.result) expect(await mom.giveUp(begun.run)).toBe(200);
      await expect(tv.page.locator(".tv-watch-ended")).toContainText(sent.result ? /\S/ : "Gave up");
      await expect(board(tv.page)).toBeVisible({ timeout: 10_000 });
      await tv.context.close();
    });
  }
});

/**
 * A family of six across the four games, everyone done in some and playing in others: Dad and Kid
 * tie for second in Sniff, Mom has two crowns, and the numbers run big (12,840 points, an hour).
 */
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
  const answer: BoardAnswer = {
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
  const [sniff, nineLives, , boxFort] = answer.games;
  sniff!.rows[2] = { ...sniff!.rows[2]!, rank: 2, result: { ...sniff!.rows[2]!.result!, guesses: sniff!.rows[1]!.result!.guesses } };
  nineLives!.rows[1] = { ...nineLives!.rows[1]!, result: { ...nineLives!.rows[1]!.result!, timeMs: 3_725_000 } };
  boxFort!.rows[0] = { ...boxFort!.rows[0]!, result: { ...boxFort!.rows[0]!.result!, points: 12_840 } };
  return answer;
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
  // Ties share a rank; the crowns and the big numbers show, whole.
  await expect(page.locator('.tv-board-game[data-game="sniff"] .tv-rank')).toHaveText(["1", "2", "2", "4", "5", "6"]);
  await expect(page.locator(".tv-dish-crowns img")).toHaveCount(2);
  await expect(page.locator('.tv-board-game[data-game="box-fort"] .tv-row-result').first()).toHaveText("12,840");
  await expect(page.locator('.tv-board-game[data-game="nine-lives"] .tv-row-result').nth(1)).toHaveText("1:02:05");
  const smallest = await page.locator(".tv-board-row .tv-row-name, .tv-board-row .tv-row-result, .tv-board-row .tv-rank").evaluateAll((els) => Math.min(...els.map((e) => parseFloat(getComputedStyle(e).fontSize))));
  expect(smallest, "the smallest row text, px at 1080p").toBeGreaterThanOrEqual(28);
  await shot(page, "board-family");
  await context.close();
});

test("a game this build has no watch view for shows a placeholder while someone plays", async ({ browser }) => {
  const context = await browser.newContext({ viewport: TV_VIEWPORT, isMobile: false, hasTouch: false });
  await context.addInitScript(() => localStorage.setItem("pounce.tv.board", JSON.stringify({ token: "F".repeat(22), until: Date.now() + 86_400_000 })));
  await context.routeWebSocket(/\/v1\/daily\/board\/ws/, (ws) => {
    ws.send(JSON.stringify({ t: "board", board: familyBoard() }));
    ws.send(JSON.stringify({ t: "watchOffer", player: "pr_mom", name: "Mom", cat: 3, game: "yarn-ball" }));
    ws.send(JSON.stringify({ t: "watch", player: "pr_mom", game: "yarn-ball", puzzle: {}, state: {} }));
  });
  const page = await tvPage(context);
  await expect(page.getByRole("button", { name: "Not now" })).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("Enter");
  const watching = page.locator('.tv-watch[data-game="yarn-ball"]');
  await expect(watching.locator(".tv-watch-placeholder")).toBeVisible();
  await context.close();
});
