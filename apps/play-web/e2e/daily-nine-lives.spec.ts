import { expect, test } from "@playwright/test";

import { closeAll, newPlayer, scan } from "./helpers";
import { cell, dismissTip, enter, fill, lives, openToday, readBoard, wrongDigit } from "./nine-lives-helpers";

/**
 * Nine Lives, the Daily Dish's number grid, end to end against the real Worker (`DAILY=on`), on
 * the lives rules the browser asks for: three lives, three free hints. Home's Today row opens
 * today's puzzle; a wrong number turns red and costs a life; three of them fill in the solution
 * and end the run out of lives; hints run out at three; and a resumed run keeps its lives, hints
 * and wrong numbers. Its frame gate is `daily-nine-lives-frames.spec.ts`.
 */

const hint = (page: import("@playwright/test").Page) => page.getByRole("button", { name: /^Hint/ });

test("Nine Lives plays to the end: a hint, a wrong number, every cell, Solved", async ({ browser }) => {
  const nia = await newPlayer(browser, "Nia");
  const { page } = nia;
  const solution = await openToday(page);
  await expect(page.getByRole("timer")).toBeVisible();
  await expect(lives(page)).toHaveAccessibleName("3 lives left");
  await expect(hint(page)).toHaveAccessibleName("Hint, 3 left");
  await scan(page, "Nine Lives");

  // A hint fills one open cell with its answer, and one fewer is left.
  await hint(page).click();
  await expect.poll(async () => (await readBoard(page)).filter((c) => c.hint).length).toBe(1);
  const hinted = (await readBoard(page)).find((c) => c.hint)!;
  expect(hinted.d).toBe(solution[hinted.i]);
  await expect(hint(page)).toHaveAccessibleName("Hint, 2 left");
  await expect(page.getByText("Three hints a day.")).toBeVisible();
  await dismissTip(page);

  // A wrong number: the server says so at once, it turns red, and a life goes. Erase takes it back.
  const open = (await readBoard(page)).find((c) => c.d === 0)!;
  await enter(page, open.i, wrongDigit(solution, open.i));
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", /, wrong$/);
  await expect(lives(page)).toHaveAccessibleName("2 lives left");
  await expect(page.getByText("Wrong numbers cost a life.")).toBeVisible();
  await page.getByRole("button", { name: "Erase" }).click();
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", /empty$/);

  // A right number stays, and locks: Erase leaves it.
  await enter(page, open.i, solution[open.i]!);
  await page.getByRole("button", { name: "Erase" }).click();
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", new RegExp(`, ${solution[open.i]}$`));

  await fill(page, solution);
  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  // Minutes faster than any person: the server keeps it off the board. The hint cost no time.
  await expect(page.getByText(/Too fast for the board · 1 hint/)).toBeVisible();
  await scan(page, "Nine Lives solved");

  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await expect(page).toHaveURL(/\/play\/daily$/);
  await expect(page.getByRole("heading", { name: "Nine Lives", level: 3 })).toBeVisible();
  await closeAll(nia.context);
});

test("Nine Lives: three wrong numbers fill in the solution, Out of lives", async ({ browser }) => {
  const otto = await newPlayer(browser, "Otto");
  const { page } = otto;
  const solution = await openToday(page);
  const open = (await readBoard(page)).filter((c) => c.d === 0).map((c) => c.i);
  for (const [n, i] of open.slice(0, 3).entries()) {
    await enter(page, i, wrongDigit(solution, i));
    if (n < 2) await expect(lives(page)).toHaveAccessibleName(`${2 - n} ${n === 1 ? "life" : "lives"} left`);
    await dismissTip(page);
  }
  // The board fills in every open cell with its answer, under one line, then the end.
  await expect(page.locator(".nl-status").getByText("Out of lives")).toBeVisible();
  await expect.poll(async () => (await readBoard(page)).filter((c) => c.answer).length).toBe(open.length);
  for (const c of await readBoard(page)) expect(c.d).toBe(solution[c.i]);
  await expect(page.getByRole("heading", { name: "Out of lives" })).toBeVisible();
  await expect(page.locator(".dd-end")).toBeInViewport();
  await scan(page, "Nine Lives out of lives");

  // Resumed: still the solution, no lives, and the end.
  await page.reload();
  await expect(page.getByRole("heading", { name: "Out of lives" })).toBeVisible();
  await expect.poll(async () => (await readBoard(page)).filter((c) => c.answer).length).toBe(open.length);
  await closeAll(otto.context);
});

test("Nine Lives: three hints, then the button is spent; a resumed run keeps its lives, hints and wrong numbers", async ({ browser }) => {
  const ada = await newPlayer(browser, "Ada");
  const { page } = ada;
  const solution = await openToday(page);
  let asked: import("@playwright/test").Request | null = null;
  page.on("request", (r) => {
    if (r.url().includes("/hint")) asked = r;
  });
  for (let n = 3; n > 0; n--) {
    await hint(page).click();
    await expect(hint(page)).toHaveAccessibleName(`Hint, ${n - 1} left`);
    await dismissTip(page);
  }
  await expect(hint(page)).toBeDisabled();
  expect((await readBoard(page)).filter((c) => c.hint)).toHaveLength(3);

  // A fourth, asked of the server anyway (the page's own call, again, with the count at three), is refused.
  const last = asked as import("@playwright/test").Request | null;
  expect(last).not.toBeNull();
  const { authorization } = await last!.allHeaders();
  const fourth = await page.request.post(last!.url(), { headers: { authorization: authorization! }, data: { hints: 3 } });
  expect(await fourth.json()).toMatchObject({ ok: false, error: "illegal" });

  const open = (await readBoard(page)).find((c) => c.d === 0)!;
  await enter(page, open.i, wrongDigit(solution, open.i));
  await expect(lives(page)).toHaveAccessibleName("2 lives left");

  await page.reload();
  await expect(page.getByRole("group", { name: "Nine Lives" })).toBeVisible();
  await expect(lives(page)).toHaveAccessibleName("2 lives left");
  await expect(hint(page)).toHaveAccessibleName("Hint, 0 left");
  await expect(hint(page)).toBeDisabled();
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", new RegExp(`, ${wrongDigit(solution, open.i)}, wrong$`));
  // The same wrong number again isn't sent, and costs nothing.
  const sent: string[] = [];
  page.on("request", (r) => {
    if (r.url().includes("/moves")) sent.push(r.postData() ?? "");
  });
  await page.getByRole("button", { name: "Erase" }).click();
  await cell(page, open.i).click();
  await page.keyboard.press(String(wrongDigit(solution, open.i)));
  await expect(cell(page, open.i)).toHaveAttribute("aria-label", /, wrong$/);
  await page.waitForTimeout(1500);
  expect(sent).toEqual([]);
  await expect(lives(page)).toHaveAccessibleName("2 lives left");
  await closeAll(ada.context);
});
