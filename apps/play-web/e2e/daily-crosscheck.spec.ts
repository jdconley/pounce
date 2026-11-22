import { readFileSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer } from "./helpers";
import { openTv } from "./tv-helpers";

/**
 * The Daily Dish cross-platform check, browser half. Skipped unless `CROSSCHECK_PLAN` names a plan
 * (the harness writes it from the server's secret and the date): for each game, one fixed move
 * list. This plays that list through the page's own controls, paced past the game's floor, and
 * the harness compares what the server answered with the iPhone's run of the same list.
 *
 * With `CROSSCHECK_TV=1`, the browser TV instead: it opens Tonight's board's link and waits; the
 * harness (`api.mjs tv`) links it and plays each game with Show on TV on. This presses Watch on
 * each offer and stays on the run to its end, and the proxy records every frame the TV is sent.
 * `TV_SHOTS_DIR` keeps a picture of each run's end.
 */
type Plan = { game: string; paceMs: number; moves: Record<string, unknown>[] };
const file = process.env.CROSSCHECK_PLAN;
const plans: Plan[] = file ? (JSON.parse(readFileSync(file, "utf8")) as { plans: Plan[] }).plans : [];

async function pace(page: Page, t0: number, k: number, gap: number) {
  const wait = t0 + gap * (k + 1) - Date.now();
  if (wait > 0) await page.waitForTimeout(wait);
}

async function open(page: Page, game: string): Promise<number> {
  const started = page.waitForResponse((r) => r.url().includes(`/v1/daily/${game}/start`) && r.ok());
  await page.goto(`/play/daily/${game}`);
  await started;
  const t0 = Date.now();
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible().catch(() => false)) await tip.click();
  return t0;
}

/** Box Fort's board, as the play view reports it. */
type Board = { rug: number[]; pieces: [number, number][][]; placed: boolean[]; over: string | null; ready: boolean; x: number; y: number; cell: number };
const board = async (page: Page) => JSON.parse((await page.locator(".bf").getAttribute("data-board")) ?? "null") as Board;

async function dragPiece(page: Page, slot: number, row: number, col: number) {
  const b = await board(page);
  const cells = b.pieces[slot]!;
  const root = (await page.locator(".bf").boundingBox())!;
  const rows = Math.max(...cells.map(([r]) => r)) + 1;
  const cols = Math.max(...cells.map(([, c]) => c)) + 1;
  const to = { x: root.x + b.x + (col + cols / 2) * b.cell, y: root.y + b.y + (row + rows + 1.1) * b.cell };
  const from = (await page.getByTestId(`boxfort-slot-${slot}`).boundingBox())!;
  const start = { x: from.x + from.width / 2, y: from.y + from.height / 2 };
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  for (let i = 1; i <= 12; i++) await page.mouse.move(start.x + ((to.x - start.x) * i) / 12, start.y + ((to.y - start.y) * i) / 12);
  await page.mouse.up();
}

for (const plan of plans) {
  test(`crosscheck ${plan.game}: the plan's moves in the browser`, async ({ browser }) => {
    test.setTimeout(400_000);
    const who = await newPlayer(browser, "Crosscheck");
    const { page } = who;
    const t0 = await open(page, plan.game);
    const end = page.getByRole("heading", { name: /^(Solved|Missed|Fort done)$/ });
    for (const [k, move] of plan.moves.entries()) {
      await pace(page, t0, k, plan.paceMs);
      if (plan.game === "nine-lives") {
        await page.locator(`.nl-board [data-cell="${move.i}"]`).click();
        await page.keyboard.press(String(move.d));
      } else if (plan.game === "cat-nap") {
        await page.getByTestId("catnap-quilt").locator("rect.cn-cell").nth((move.cells as number[])[0]!).click();
      } else if (plan.game === "sniff") {
        const keys = page.getByRole("group", { name: "Keyboard" });
        for (const l of (move.word as string).toUpperCase()) await keys.getByRole("button", { name: new RegExp(`^${l}(,|$)`) }).click();
        await keys.getByRole("button", { name: "Sniff" }).click();
        await expect(page.getByRole("group", { name: `Try ${k + 1}` }).locator(".sniff-tag[data-mark]")).toHaveCount(5);
      } else {
        await expect.poll(async () => (await board(page)).ready, { timeout: 15_000 }).toBe(true);
        await dragPiece(page, move.slot as number, move.row as number, move.col as number);
        await expect.poll(async () => { const b = await board(page); return b.over !== null || b.placed[move.slot as number] === true || !b.ready; }).toBe(true);
      }
    }
    await expect(end).toBeVisible({ timeout: 20_000 });
    await page.waitForTimeout(1500);
    await closeAll(who.context);
  });
}

test("crosscheck tv: the browser TV watches each game the harness plays", async ({ browser }) => {
  test.skip(process.env.CROSSCHECK_TV !== "1", "no CROSSCHECK_TV");
  test.setTimeout(1_500_000);
  const tv = await openTv(browser);
  const { page } = tv;
  const shots = process.env.TV_SHOTS_DIR;
  await page.getByRole("button", { name: "Tonight's board" }).click();
  await expect(page.locator(".tv-board-link .tv-code")).toHaveText(/^[A-Z0-9]{6}$/);
  await expect(page.locator(".tv-board")).toBeVisible({ timeout: 300_000 });
  for (let n = 1; n <= 4; n++) {
    await expect(page.locator(".tv-watch-card")).toBeVisible({ timeout: 300_000 });
    await expect(page.getByRole("button", { name: "Not now" })).toBeFocused();
    // A press that lands while the card is still settling is lost, so press until Watch has focus.
    await expect(async () => {
      await page.keyboard.press("ArrowLeft");
      await expect(page.getByRole("button", { name: "Watch" })).toBeFocused({ timeout: 1000 });
    }).toPass({ timeout: 15_000 });
    await page.keyboard.press("Enter");
    const watching = page.locator(".tv-watch[data-game]");
    await expect(watching).toBeVisible();
    const game = await watching.getAttribute("data-game");
    await expect(page.locator(".tv-watch-ended")).toBeVisible({ timeout: 300_000 });
    await page.waitForTimeout(1000);
    if (shots) await page.screenshot({ path: `${shots}/web-crosscheck-${game}.png` });
    await expect(page.locator(".tv-board")).toBeVisible({ timeout: 20_000 });
  }
  if (shots) await page.screenshot({ path: `${shots}/web-crosscheck-board.png` });
  await tv.context.close();
});

