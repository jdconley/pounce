import { expect, test } from "@playwright/test";

import { closeAll, newPlayer, scan } from "./helpers";
import { cell, fill, openToday, readBoard } from "./nine-lives-helpers";

/**
 * Nine Lives, the Daily Dish's sudoku, end to end against the real Worker (`DAILY=on`): Home's
 * Today row opens today's puzzle, a hint fills a cell, a clash shows and is erased, every open cell
 * is filled, and the run ends Solved (too fast for the board, as a test's always is), with the way
 * back to the Dish. Its frame gate is `daily-nine-lives-frames.spec.ts`.
 */

test("Nine Lives plays to the end: a hint, a clash, every cell, Solved", async ({ browser }) => {
  const nia = await newPlayer(browser, "Nia");
  const { page } = nia;
  const solution = await openToday(page);
  await expect(page.getByRole("timer")).toBeVisible();
  await scan(page, "Nine Lives");

  // A hint fills one open cell with its answer.
  await page.getByRole("button", { name: "Hint" }).click();
  await expect.poll(async () => (await readBoard(page)).filter((c) => c.hint).length).toBe(1);
  const hinted = (await readBoard(page)).find((c) => c.hint)!;
  expect(hinted.d).toBe(solution[hinted.i]);

  // A number that a row, column or box already has clashes, and Erase takes it back.
  const open = (await readBoard(page)).find((c) => c.d === 0)!;
  const row = Math.floor(open.i / 9);
  const rowGiven = (await readBoard(page)).find((c) => Math.floor(c.i / 9) === row && c.given)!;
  await cell(page, open.i).click();
  await page.keyboard.press(String(rowGiven.d));
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", /clash/);
  await page.getByRole("button", { name: "Erase" }).click();
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", /empty$/);

  await fill(page, solution);
  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  // Minutes faster than any person: the server keeps it off the board.
  await expect(page.getByText(/Too fast for the board · 1 hint/)).toBeVisible();
  await scan(page, "Nine Lives solved");

  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await expect(page).toHaveURL(/\/play\/daily$/);
  await expect(page.getByRole("heading", { name: "Nine Lives", level: 3 })).toBeVisible();
  await closeAll(nia.context);
});
