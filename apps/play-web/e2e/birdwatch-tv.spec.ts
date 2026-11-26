import { expect, test } from "@playwright/test";

import { bwStep, newStats } from "./birdwatch-helpers";
import { closeAll } from "./helpers";
import { forfeit, noHandOnTv, openTv, phonesJoin, startFromPhone, tvMakes } from "./tv-helpers";

/**
 * Birdwatch on the TV (design §5.6): the TV shows the window, the cats and their bid signs, the
 * sill, the trump badge and the score strip; the phone shows its hand and controls on Cards. The
 * phone's player leaves, a House Cat takes the seat, and with no person left the game ends.
 */
test.use({ reducedMotion: "reduce", actionTimeout: 15_000 });

test("a TV shows a Birdwatch table a phone plays on Cards, and never a hand", async ({ browser }) => {
  test.setTimeout(6 * 60_000);
  const tv = await openTv(browser);
  const code = await tvMakes(tv, "Birdwatch");
  await expect(tv.page.locator(".tv-lobby-rules")).toHaveText("Official");
  const [ava] = await phonesJoin(browser, code, ["Ava"]);
  // Three House Cats from the phone's lobby, so four sit down.
  for (let n = 1; n < 4; n++) {
    await ava!.page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(n + 1);
  }
  await ava!.page.getByRole("radio", { name: "Tucker" }).click();
  await expect(tv.page.locator(".tv-lobby-rules")).toHaveText("Tucker");
  await startFromPhone(ava!.page);

  await expect(tv.page.locator(".bw-tv")).toBeVisible();
  await expect(tv.page.locator(".bw-tv .bw-seat")).toHaveCount(4);
  await expect(tv.page.locator(".bw-tv-rules")).toHaveText("Tucker, to 500");
  // The phone is on Cards: its hand and controls, no window.
  await expect(ava!.page.locator(".bw-table.cards-view")).toBeVisible();
  await expect(ava!.page.locator(".bw-hand-card").first()).toBeVisible();

  // Play until a trick has landed on the TV's sill.
  const stats = newStats();
  const deadline = Date.now() + 3 * 60_000;
  let sill = 0;
  while (Date.now() < deadline && sill === 0) {
    const r = await bwStep(ava!.page, "taps", stats, { bid: () => stats.bids === 0 });
    sill = await tv.page.locator(".bw-tv .card.on-sill").count();
    if (r === null) await ava!.page.waitForTimeout(150);
  }
  expect(sill).toBeGreaterThan(0);
  await expect(tv.page.locator("#bw-trump")).toHaveAttribute("aria-label", /^Trump: /);
  await noHandOnTv(tv.page);
  await expect(tv.page.locator(".bw-hand-card")).toHaveCount(0);

  // Ava leaves: a House Cat takes her seat, and with nobody left the game ends.
  await forfeit(ava!.page);
  await expect(tv.page.getByRole("dialog", { name: "Game over" })).toBeVisible({ timeout: 60_000 });
  await closeAll(tv.context, ava!.context);
});
