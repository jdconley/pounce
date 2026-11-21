import { expect, type Page } from "@playwright/test";

/** Reading and playing Nine Lives' board in a page, for its specs. */

type Cell = { i: number; d: number; given: boolean; hint: boolean; clash: boolean };

/** The board as the cells' labels say it ("Row 1, column 2, 7, given"). */
export async function readBoard(page: Page): Promise<Cell[]> {
  return page.locator('.nl-board button[data-cell]').evaluateAll((els) =>
    els
      .map((el) => {
        const parts = (el.getAttribute("aria-label") ?? "").split(", ");
        const d = Number(parts[2]);
        return { i: Number(el.getAttribute("data-cell")), d: Number.isInteger(d) ? d : 0, given: parts.includes("given"), hint: parts.includes("hint"), clash: parts.includes("clash") };
      })
      .sort((a, b) => a.i - b.i),
  );
}

/** The one solution of `cells` (0 for open), by backtracking on the most constrained cell. */
export function solve(cells: number[]): number[] {
  const g = [...cells];
  const free = (i: number) => {
    const [r, c] = [Math.floor(i / 9), i % 9];
    let used = 0;
    for (let k = 0; k < 9; k++) {
      used |= 1 << g[r * 9 + k]! | (1 << g[k * 9 + c]!);
      used |= 1 << g[(Math.floor(r / 3) * 3 + Math.floor(k / 3)) * 9 + Math.floor(c / 3) * 3 + (k % 3)]!;
    }
    return [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((d) => !(used & (1 << d)));
  };
  const go = (): boolean => {
    let best = -1;
    let options: number[] = [];
    for (let i = 0; i < 81; i++) {
      if (g[i]) continue;
      const f = free(i);
      if (best < 0 || f.length < options.length) [best, options] = [i, f];
      if (f.length === 0) return false;
    }
    if (best < 0) return true;
    for (const d of options) {
      g[best] = d;
      if (go()) return true;
    }
    g[best] = 0;
    return false;
  };
  if (!go()) throw new Error("no solution");
  return g;
}

export const cell = (page: Page, i: number) => page.locator(`.nl-board [data-cell="${i}"]`);

/** Opens today's Nine Lives from Home and returns its solution. */
export async function openToday(page: Page): Promise<number[]> {
  // Fails within the expect timeout, not the test's, when Home has no Today row.
  const play = page.getByRole("button", { name: /^Nine Lives Play/ });
  await expect(play).toBeVisible();
  await play.click();
  await expect(page).toHaveURL(/\/play\/daily\/nine-lives$/);
  await expect(page.getByRole("group", { name: "Nine Lives" })).toBeVisible();
  const board = await readBoard(page);
  expect(board).toHaveLength(81);
  const givens = board.map((c) => (c.given ? c.d : 0));
  expect(givens.filter(Boolean).length).toBeGreaterThanOrEqual(17);
  return solve(givens);
}

/** Fills every open cell with its answer: tap the cell, press its number. */
export async function fill(page: Page, solution: number[], between = 0) {
  for (const c of await readBoard(page)) {
    if (c.d === solution[c.i]) continue;
    await cell(page, c.i).click();
    await page.keyboard.press(String(solution[c.i]));
    if (between) await page.waitForTimeout(between);
  }
}
