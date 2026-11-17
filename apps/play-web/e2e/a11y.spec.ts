import { expect, test } from "@playwright/test";

import { firstRun, scan } from "./helpers";

/**
 * Screen readers and keyboards (web player design, "Everything a player expects"): axe finds no
 * serious problem on the first run, Home, the lobby and both tables, and the keyboard alone can
 * draw and discard.
 */
test("no serious accessibility problems, and the keyboard plays a turn", async ({ page }, info) => {
  test.skip(info.project.name !== "laptop-chrome", "one pass is enough");
  await page.goto("/play/");
  await scan(page, "age");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
  await scan(page, "home");
  await page.getByRole("button", { name: "Play Tuna Tiles" }).click();
  await expect(page.getByRole("button", { name: "Start" })).toBeVisible();
  await scan(page, "lobby");
  await page.getByRole("button", { name: "Start" }).click();
  await expect(page.getByRole("img", { name: /Toy box/ })).toBeVisible();
  await scan(page, "tuna tiles");
  await page.goto("/play/");
  await page.getByRole("button", { name: "Practice" }).click();
  await expect(page.locator("#deck")).toBeVisible();
  await scan(page, "cat tower");
  // The keyboard alone: D draws on our turn, then pick a card and X discards it.
  await expect(page.locator("#deck:not([disabled])")).toBeVisible({ timeout: 60_000 });
  const before = Number(await page.locator("#deck .pile-count").textContent());
  await page.keyboard.press("d");
  await expect.poll(async () => Number(await page.locator("#deck .pile-count").textContent())).toBe(before - 1);
  await page.locator(".card.mine .card-inner").first().focus();
  await page.keyboard.press("Enter");
  await page.keyboard.press("x");
  await expect(page.locator("#deck")).toBeDisabled({ timeout: 15_000 });
});
