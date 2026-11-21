import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer, scan } from "./helpers";

/**
 * Cat Nap in the browser, end to end, against today's real quilt (`DAILY=on`): Home's treat opens
 * it, a tap cycles a cell, a drag marks a row "no cat" in one move, the board survives a reload,
 * and hints place the server's cats until the quilt is solved. The page never learns the solution
 * any other way, so the hints are how a test reaches the end.
 */

const cells = (page: Page) => page.getByTestId("catnap-quilt").locator("rect.cn-cell");
const cell = (page: Page, i: number) => cells(page).nth(i);

async function size(page: Page): Promise<number> {
  await expect(cells(page).first()).toBeVisible();
  const count = await cells(page).count();
  const n = Math.round(Math.sqrt(count));
  expect(n * n).toBe(count);
  expect(n).toBeGreaterThanOrEqual(5);
  expect(n).toBeLessThanOrEqual(9);
  return n;
}

/** Presses on one cell's middle and drags to another's, as a finger would. */
async function drag(page: Page, from: number, to: number) {
  const a = (await cell(page, from).boundingBox())!;
  const b = (await cell(page, to).boundingBox())!;
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) await page.mouse.move(a.x + a.width / 2 + ((b.x - a.x) * i) / 8, a.y + a.height / 2 + ((b.y - a.y) * i) / 8);
  await page.mouse.up();
}

test("Cat Nap plays to the end: a tap, a drag, a reload, hints, solved", async ({ browser }, info) => {
  const lu = await newPlayer(browser, "Lu");
  const { page } = lu;
  await page.getByRole("button", { name: "Cat Nap Play" }).click();
  await expect(page).toHaveURL(/\/play\/daily\/cat-nap$/);
  await expect(page.getByRole("timer")).toBeVisible();
  const n = await size(page);

  // A tap cycles a cell: no cat, a cat, empty.
  await cell(page, 0).click();
  await expect(cell(page, 0)).toHaveAttribute("aria-label", /, no cat$/);
  await cell(page, 0).click();
  await expect(cell(page, 0)).toHaveAttribute("aria-label", /, cat$/);
  await cell(page, 0).click();
  await expect(cell(page, 0)).not.toHaveAttribute("aria-label", /cat$/);

  // A drag along the bottom row marks it "no cat" (a touch phone's drag is the same pointer events).
  const last = n * (n - 1);
  if (info.project.name === "laptop-chrome") {
    await drag(page, last, last + n - 1);
  } else {
    for (let i = last; i < last + n; i++) await cell(page, i).click();
  }
  await expect(cell(page, last + n - 1)).toHaveAttribute("aria-label", /, no cat$/);
  await scan(page, "Cat Nap");

  // The moves go in their batch within a second; a reload comes back to the server's board.
  await page.waitForTimeout(1500);
  await page.reload();
  await expect(cell(page, last + n - 1)).toHaveAttribute("aria-label", /, no cat$/);

  // Hints place the server's cats, one each, until the quilt is solved.
  const hint = page.getByTestId("catnap-hint");
  const locked = page.locator('rect.cn-cell[aria-label$=", cat, locked"]');
  const end = page.getByRole("heading", { name: "Solved" });
  for (let i = 0; i < n && !(await end.isVisible()); i++) {
    await expect(hint).toBeEnabled();
    await hint.click();
    await expect.poll(async () => (await end.isVisible()) || (await locked.count()) === i + 1).toBe(true);
  }
  await expect(end).toBeVisible();
  await expect(page.getByText("1st today")).toBeVisible();
  await closeAll(lu.context);
});
