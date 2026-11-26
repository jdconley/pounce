import { expect, test, type Page } from "@playwright/test";

import { bwStep, newStats, playToTheEnd, type How } from "./birdwatch-helpers";
import { closeAll, newPlayer, tableCode } from "./helpers";

/**
 * Birdwatch in the browser, against the real server's House Cats: full games at 4, 5 and 6 seats
 * under each rule set, the lobby's rule pills, Swap seats and ribbons, and pass and play behind
 * the curtain. A laptop plays by keyboard; the phone (android-chrome) taps. The iPhone project
 * leaves these to those two (playwright.config.ts), to keep CI quick.
 */
// House Cats move fast on the test server; the table's own pacing is what takes the time.
test.use({ reducedMotion: "reduce", actionTimeout: 15_000 });

const how = (): How => (test.info().project.name === "laptop-chrome" ? "keys" : "taps");

/** A Birdwatch table from Home's shelf, its rule set picked, House Cats in the seats to `seats`. */
async function birdTable(page: Page, rules: "Official" | "Tucker" | "Friesen", seats: number): Promise<string> {
  await page.getByRole("button", { name: "Play Birdwatch" }).click();
  const code = await tableCode(page);
  // A first table gets three House Cats, so Start is lit at once.
  await expect(page.getByRole("button", { name: "House Cat" }).nth(2)).toBeVisible();
  await page.getByRole("radio", { name: rules }).click();
  await expect(page.getByRole("radio", { name: rules })).toHaveAttribute("aria-checked", "true");
  for (let n = 4; n < seats; n++) {
    const before = await page.locator(".lobby-seat.bot").count();
    await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await expect(page.locator(".lobby-seat.bot")).toHaveCount(before + 1);
  }
  return code;
}

for (const [seats, rules] of [
  [4, "Official"],
  [5, "Tucker"],
  [6, "Friesen"],
] as const) {
  test(`Birdwatch: ${seats} players, ${rules} rules, a full game against House Cats`, async ({ browser }) => {
    test.skip(seats !== 5 && test.info().project.name === "android-chrome", "the phone plays the 5-player game; the laptop plays all three");
    test.setTimeout(16 * 60_000);
    const { context, page } = await newPlayer(browser, "Grandma");
    await birdTable(page, rules, seats);
    await page.getByRole("button", { name: "Start" }).click();
    await expect(page.locator(".bw-table")).toBeVisible();
    await expect(page.locator(".bw-seat")).toHaveCount(seats - 1);
    await expect(page.locator(".bw-chip")).toHaveCount(seats === 5 ? 5 : seats / 2);

    const stats = await playToTheEnd([page], [how()], { minutes: 14 });
    console.log(`Birdwatch ${seats}p ${rules}: ${JSON.stringify({ ...stats, hands: stats.hands.size })}`);
    expect(stats.plays).toBeGreaterThan(8);
    // Every game took the feeder and named trump at least once (it bids until it wins one).
    expect(stats.nests).toBeGreaterThanOrEqual(1);
    expect(stats.trumps).toBeGreaterThanOrEqual(1);
    if (seats === 5) expect(stats.partners).toBeGreaterThanOrEqual(1);
    const over = page.getByRole("dialog", { name: /wins?$|^Game over$/ });
    await expect(over).toBeVisible();
    await expect(over.getByRole("button", { name: "Play again" })).toBeVisible();
    await context.close();
  });
}

test("Birdwatch lobby: the host picks the rules, swaps seats, and teams wear ribbons", async ({ browser }) => {
  test.skip(test.info().project.name !== "laptop-chrome", "one lobby check is enough");
  const host = await newPlayer(browser, "Leo");
  const code = await birdTable(host.page, "Official", 4);
  await expect(host.page.getByText("1s out, Bird wild.")).toBeVisible();
  await host.page.getByRole("radio", { name: "Friesen" }).click();
  await expect(host.page.getByText("1s high, Bird follows suit.")).toBeVisible();

  // A guest sees the rules, and can't change them.
  const guest = await newPlayer(browser, "Kiki", { path: `/play/j/${code}` });
  await expect(guest.page.getByRole("radio", { name: "Friesen" })).toHaveAttribute("aria-checked", "true");
  await expect(guest.page.getByRole("radio", { name: "Tucker" })).toBeDisabled();

  // Teams by seat order: seats 0 and 2, 1 and 3. Kiki took the first House Cat's seat (seat 1).
  const ribbon = (page: Page, name: string) =>
    page
      .getByRole("button", { name: new RegExp(`^${name}`) })
      .first()
      .evaluate((el) => getComputedStyle(el).getPropertyValue("--ribbon").trim());
  const leoBefore = await ribbon(host.page, "Leo");
  expect(await ribbon(host.page, "Kiki")).not.toBe(leoBefore);

  // Swap Kiki to Leo's side: the seat menu's Swap seats, then the seat to swap with.
  await host.page.getByRole("button", { name: "Kiki, on another device" }).click();
  await host.page.locator("#swap-seats").click();
  await expect(host.page.getByText("Tap a seat to swap")).toBeVisible();
  // Seat 2 is Leo's teammate's: the first House Cat after Kiki.
  await host.page.getByRole("button", { name: "Swap with House Cat" }).first().click();
  await expect.poll(() => ribbon(host.page, "Kiki")).toBe(leoBefore);
  await expect.poll(() => ribbon(guest.page, "Kiki")).toBe(await ribbon(guest.page, "Leo"));

  // How to play, for the rule set on the table.
  await host.page.getByRole("button", { name: "How to play" }).click();
  await expect(host.page.getByRole("dialog", { name: "How to play" }).getByText("follows suit like any trump")).toBeVisible();
  await closeAll(host.context, guest.context);
});

test("Birdwatch pass and play: each hand behind the curtain, never another's", async ({ browser }) => {
  test.skip(test.info().project.name !== "laptop-chrome", "one pass-and-play check is enough");
  test.setTimeout(6 * 60_000);
  const { context, page } = await newPlayer(browser, "Dad");
  await page.getByRole("button", { name: "Play Birdwatch" }).click();
  await tableCode(page);
  await page.getByRole("button", { name: "This device", exact: true }).click();
  await page.getByLabel("Your name").fill("Kid");
  await page.getByRole("button", { name: "Done" }).click();
  await expect(page.getByRole("button", { name: "Kid, on this device" })).toBeVisible();
  await page.getByRole("button", { name: "Start" }).click();
  // Whoever acts first on this device sees the curtain, never a hand.
  const curtain = page.getByRole("dialog", { name: /Pass to (Dad|Kid)/ });
  await expect(curtain).toBeVisible({ timeout: 60_000 });
  await expect(page.locator(".bw-hand-card")).toHaveCount(0);
  // Play on (passing every bid) until the device has changed hands three times; each time the
  // curtain is up, no hand shows.
  const stats = newStats();
  const deadline = Date.now() + 4 * 60_000;
  while (stats.curtains < 3 && Date.now() < deadline) {
    if (await curtain.isVisible()) await expect(page.locator(".bw-hand-card")).toHaveCount(0);
    const r = await bwStep(page, "keys", stats, { bid: () => false });
    if (r === "over") break;
    if (r === null) await page.waitForTimeout(150);
  }
  expect(stats.curtains).toBeGreaterThanOrEqual(3);
  await context.close();
});
