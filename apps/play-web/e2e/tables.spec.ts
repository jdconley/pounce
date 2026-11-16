import { expect, test } from "@playwright/test";

import { catTowerTurn, closeAll, deckCount, newPlayer, tableCode } from "./helpers";

test.describe("two browsers at one table", () => {
  test("Cat Tower: a guest from the invite link takes the seat, both play, a forfeit ends it, Play again deals anew", async ({ browser }) => {
    const host = await newPlayer(browser, "Grandma");
    await host.page.getByRole("button", { name: "Play Cat Tower" }).click();
    const code = await tableCode(host.page);
    // A first table gets a House Cat, so Start is lit at once.
    await expect(host.page.getByRole("button", { name: "House Cat" }).first()).toBeVisible();

    const guest = await newPlayer(browser, "Mia", { path: `/play/j/${code}` });
    await expect(guest.page).toHaveURL(new RegExp(`/play/t/${code}$`));
    // The guest took the House Cat's seat.
    await expect(host.page.getByRole("button", { name: "Mia, on another device" })).toBeVisible();
    await expect(guest.page.getByRole("button", { name: "Grandma, on another device" })).toBeVisible();

    await host.page.getByRole("button", { name: "Start" }).click();
    await expect(host.page.locator("#deck")).toBeVisible();
    await expect(guest.page.locator("#deck")).toBeVisible();

    // Take turns: each move shows on the other screen.
    let turns = 0;
    for (let i = 0; i < 40 && turns < 4; i++) {
      for (const p of [host.page, guest.page]) {
        const before = await deckCount(p);
        if (await catTowerTurn(p)) {
          turns++;
          const other = p === host.page ? guest.page : host.page;
          await expect.poll(() => deckCount(other)).toBeLessThan(before);
        }
      }
      await host.page.waitForTimeout(250);
    }
    expect(turns).toBeGreaterThanOrEqual(4);

    // Grandma forfeits: Mia wins, and Play again deals a new table.
    await host.page.getByRole("button", { name: "Menu" }).click();
    await host.page.getByRole("button", { name: "Forfeit" }).click();
    await expect(host.page.getByText("Mia wins.")).toBeVisible();
    await host.page.locator("#forfeit").click();
    await expect(guest.page.getByRole("dialog", { name: "Mia wins" })).toBeVisible();
    await guest.page.getByRole("button", { name: "Play again" }).click();
    await guest.page.waitForURL((url) => /\/play\/t\/[A-Z0-9]{5}$/.test(url.pathname) && !url.pathname.endsWith(code));
    await closeAll(host.context, guest.context);
  });

  test("Tuna Tiles: both see each draw, and the table plays to game over", async ({ browser }) => {
    const host = await newPlayer(browser, "Leo");
    await host.page.getByRole("button", { name: "Play Tuna Tiles" }).click();
    const code = await tableCode(host.page);
    const guest = await newPlayer(browser, "Kiki", { path: `/play/j/${code}` });
    await expect(host.page.getByRole("button", { name: "Kiki, on another device" })).toBeVisible();
    await host.page.getByRole("button", { name: "Start" }).click();
    const pool = (p: typeof host.page) => p.getByRole("img", { name: /Toy box: \d+ pieces/ });
    await expect(pool(host.page)).toBeVisible();
    let draws = 0;
    for (let i = 0; i < 40 && draws < 4; i++) {
      for (const p of [host.page, guest.page]) {
        const button = p.locator("#play-btn:not([disabled])");
        if (await button.isVisible()) {
          const before = await pool(p).getAttribute("aria-label");
          await button.click();
          draws++;
          const other = p === host.page ? guest.page : host.page;
          await expect.poll(() => pool(other).getAttribute("aria-label")).not.toBe(before);
        }
      }
      await host.page.waitForTimeout(250);
    }
    expect(draws).toBeGreaterThanOrEqual(4);
    await guest.page.getByRole("button", { name: "Menu" }).click();
    await guest.page.getByRole("button", { name: "Forfeit" }).click();
    await guest.page.locator("#forfeit").click();
    await expect(host.page.getByRole("dialog", { name: "Leo wins" })).toBeVisible();
    await expect(guest.page.getByRole("dialog", { name: "Leo wins" })).toBeVisible();
    await closeAll(host.context, guest.context);
  });
});

test("pass and play: a second person on this device, and the curtain between turns", async ({ browser }) => {
  const { context, page } = await newPlayer(browser, "Dad");
  await page.getByRole("button", { name: "Play Cat Tower" }).click();
  await tableCode(page);
  await page.getByRole("button", { name: "This device", exact: true }).click();
  await page.getByLabel("Your name").fill("Kid");
  await page.getByRole("button", { name: "Done" }).click();
  await expect(page.getByRole("button", { name: "Kid, on this device" })).toBeVisible();
  await page.getByRole("button", { name: "Start" }).click();
  // Whoever is first on this device sees the curtain, never the hand.
  await expect(page.getByRole("dialog", { name: /Pass to (Dad|Kid)/ })).toBeVisible({ timeout: 30_000 });
  await expect(page.locator(".card.mine")).toHaveCount(0);
  const hold = page.getByRole("button", { name: "Hold to see your hand" });
  const box = await hold.boundingBox();
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(900);
  await page.mouse.up();
  await expect(page.locator(".card.mine").first()).toBeVisible();
  await context.close();
});

test("practice against the House Cat, from Home, in one tap", async ({ browser }) => {
  const { context, page } = await newPlayer(browser, "Solo");
  await page.getByRole("button", { name: "Practice" }).click();
  await expect(page.locator("#deck")).toBeVisible();
  await expect(page.getByRole("img", { name: /House Cat/ }).first()).toBeVisible();
  await context.close();
});
