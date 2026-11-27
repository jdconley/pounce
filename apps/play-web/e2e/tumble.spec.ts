import { expect, test } from "@playwright/test";

import { closeAll, newPlayer } from "./helpers";
import { playing, playUntil, setDowns, tumbleTable, watchWire } from "./tumble-helpers";

/**
 * Toy Tumble in the browser, against the real server and its House Cats: two browser players and
 * a House Cat play a game to its end (a laptop by keys, a phone by touch), keyboard play moves,
 * turns and drops, and a player who reloads mid-round is back in it within 15 seconds. Built with
 * `WEB_TUMBLE=on`, so Home's shelf has the game.
 */
test.use({ actionTimeout: 15_000 });

const only = (names: string[]) => test.skip(!names.includes(test.info().project.name), `runs on ${names.join(" and ")}`);

test("Toy Tumble: two players and a House Cat play a game to its end", async ({ browser }) => {
  only(["laptop-chrome", "android-chrome"]);
  test.setTimeout(6 * 60_000);
  const touch = test.info().project.name === "android-chrome";
  const ann = await newPlayer(browser, "Ann");
  const wire = watchWire(ann.page);
  const code = await tumbleTable(ann.page);
  await expect(ann.page.getByRole("radio", { name: "Cats: Easy" })).toHaveAttribute("aria-checked", "true");
  await ann.page.getByRole("radio", { name: "Cats: Quick" }).click();
  await expect(ann.page.getByRole("radio", { name: "Cats: Quick" })).toHaveAttribute("aria-checked", "true");
  // No second seat on this device: a Toy Tumble seat is a device.
  await expect(ann.page.locator("#add-bar").getByRole("button", { name: "This device" })).toHaveCount(0);

  const ben = await newPlayer(browser, "Ben", { path: `/play/j/${code}` });
  await expect(ben.page).toHaveURL(new RegExp(`/play/t/${code}$`));
  // Ben took the first House Cat's seat; another cat sits down.
  await expect(ann.page.locator(".lobby-seat.bot")).toHaveCount(0);
  await ann.page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
  await expect(ann.page.locator(".lobby-seat.bot")).toHaveCount(1);
  await expect(ann.page.getByRole("button", { name: "Start" })).toBeEnabled();
  await ann.page.getByRole("button", { name: "Start" }).click();

  // The 3-2-1, then both boxes play, with the other two as minis.
  for (const p of [ann.page, ben.page]) await expect(p.locator(".tt-count-round")).toHaveText("Round 1");
  for (const p of [ann.page, ben.page]) await expect(p.locator("#tt-box")).toBeVisible();
  await expect(ann.page.locator(".tt-mini")).toHaveCount(2);
  await expect.poll(() => playing(ann.page), { timeout: 10_000 }).toBe(true);

  // Both play on till the game is over: a round each time one box is left.
  const over = ann.page.getByRole("dialog", { name: /wins$|^A tie$|^Game over$/ });
  await playUntil(
    [
      { page: ann.page, how: touch ? "touch" : "keys" },
      { page: ben.page, how: "keys" },
    ],
    () => over.isVisible(),
    5 * 60_000,
  );
  expect(setDowns(wire)).toBeGreaterThan(5);
  await expect(over.getByRole("button", { name: "Play again" })).toBeVisible();
  await expect(ben.page.getByRole("dialog", { name: /wins$|^A tie$|^Game over$/ })).toBeVisible();
  await closeAll(ann.context, ben.context);
});

test("Toy Tumble by keys: arrows move, Up and Z turn, Space drops, and the page never scrolls", async ({ browser }) => {
  only(["laptop-chrome", "android-chrome"]);
  test.setTimeout(2 * 60_000);
  const ann = await newPlayer(browser, "Ann");
  const wire = watchWire(ann.page);
  await tumbleTable(ann.page);
  await ann.page.getByRole("button", { name: "Start" }).click();
  await expect.poll(() => playing(ann.page), { timeout: 10_000 }).toBe(true);
  // The Start button had focus: Space must drop, not press it, and nothing may scroll.
  const moves = () => wire.sent.filter((e) => e[0] === "m") as ["m", number, number, number, number][];
  await ann.page.keyboard.press("ArrowLeft");
  await expect.poll(() => moves().length).toBeGreaterThan(0);
  const x0 = moves().at(-1)![3];
  await ann.page.keyboard.press("ArrowLeft");
  await expect.poll(() => moves().at(-1)![3]).toBe(x0 - 1);
  await ann.page.keyboard.press("ArrowRight");
  await expect.poll(() => moves().at(-1)![3]).toBe(x0);
  const rot = moves().at(-1)![2];
  await ann.page.keyboard.press("ArrowUp");
  await expect.poll(() => moves().at(-1)![2]).not.toBe(rot);
  await ann.page.keyboard.press("z");
  await expect.poll(() => moves().at(-1)![2]).toBe(rot);
  // Holding the arrow repeats it.
  await ann.page.keyboard.down("ArrowRight");
  await ann.page.waitForTimeout(400);
  await ann.page.keyboard.up("ArrowRight");
  await expect.poll(() => moves().at(-1)![3]).toBeGreaterThan(x0 + 2);
  await ann.page.keyboard.press("Space");
  await expect.poll(() => setDowns(wire)).toBe(1);
  expect(await ann.page.evaluate(() => [window.scrollX, window.scrollY, document.scrollingElement?.scrollTop ?? 0])).toEqual([0, 0, 0]);
  await closeAll(ann.context);
});

test("Toy Tumble: a player who reloads mid-round is back in it within 15 seconds", async ({ browser }) => {
  only(["laptop-chrome"]);
  test.setTimeout(2 * 60_000);
  const ann = await newPlayer(browser, "Ann");
  const code = await tumbleTable(ann.page);
  const ben = await newPlayer(browser, "Ben", { path: `/play/j/${code}` });
  await expect(ben.page).toHaveURL(new RegExp(`/play/t/${code}$`));
  // Ben sits in the House Cat's seat before Start.
  await expect(ann.page.locator(".lobby-seat.bot")).toHaveCount(0);
  await ann.page.getByRole("button", { name: "Start" }).click();
  await expect.poll(() => playing(ben.page), { timeout: 10_000 }).toBe(true);
  for (let i = 0; i < 3; i++) await ben.page.keyboard.press("Space");
  const back = Date.now();
  const wire = watchWire(ben.page);
  await ben.page.reload();
  // The box is back, not out, and plays on from the server's sync.
  await expect.poll(() => playing(ben.page), { timeout: 15_000 }).toBe(true);
  expect(Date.now() - back).toBeLessThan(15_000);
  await expect.poll(() => wire.syncs, { timeout: 5000 }).toBeGreaterThan(0);
  await expect(ann.page.locator(".tt-mini").filter({ has: ann.page.locator(".tt-state.out") })).toHaveCount(0);
  await ben.page.keyboard.press("Space");
  await expect.poll(() => setDowns(wire)).toBeGreaterThan(0);
  await closeAll(ann.context, ben.context);
});
