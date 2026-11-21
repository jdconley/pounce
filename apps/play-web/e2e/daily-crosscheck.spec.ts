import { readFileSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer } from "./helpers";

/**
 * The Daily Dish cross-platform check, browser half. Skipped unless `CROSSCHECK_PLAN` names a plan
 * (the harness writes it from the server's secret and the date): for each game, one fixed move
 * list. This plays that list through the page's own controls, paced past the game's floor, and
 * the harness compares what the server answered with the iPhone's run of the same list.
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
