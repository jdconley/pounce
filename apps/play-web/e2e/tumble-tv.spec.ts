import { expect, test, type Page } from "@playwright/test";

import { closeAll } from "./helpers";
import { keysTurn, playing, setDowns, watchWire, type Wire } from "./tumble-helpers";
import { openTv, phonesJoin, startFromPhone, tvMakes } from "./tv-helpers";

/**
 * Toy Tumble on the TV page (spec §5.6): the TV makes the table, two phones and a House Cat sit,
 * and the TV shows all three boxes live while the phones play, with chips on the phones. Reloaded
 * mid-round, the TV draws every box at once from the sync it gets.
 */
test.use({ actionTimeout: 15_000 });

/** Each box's stack height on the TV, read off its labels' signature (held|waiting|state|height). */
const heights = async (tv: Page): Promise<number[]> =>
  ((await tv.locator(".tt-tv").getAttribute("data-sig")) ?? "")
    .split(",")
    .filter(Boolean)
    .map((s) => Number(s.split("|")[3] ?? 0));

/** A few drops from each phone whose box is in play. */
async function drops(phones: Page[], n: number): Promise<void> {
  for (let k = 0; k < n; k++) {
    for (const p of phones) if (await playing(p)) await keysTurn(p, k);
    await phones[0]!.waitForTimeout(150);
  }
}

test("the TV shows every Toy Tumble box live, and draws them all again after a reload mid-round", async ({ browser }) => {
  test.setTimeout(4 * 60_000);
  const tv = await openTv(browser);
  const code = await tvMakes(tv, "Toy Tumble");
  const wires: Wire[] = [];
  const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"], undefined, (page) => wires.push(watchWire(page)));
  const phones = [ava!.page, ben!.page];
  await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
  await ava!.page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
  await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(3);
  await expect(tv.page.locator(".tv-lobby-rules")).toHaveText("Cats: Easy");
  await startFromPhone(...phones);

  // Three boxes in one row, named, with the round over them.
  await expect(tv.page.locator(".tt-tv-box")).toHaveCount(3);
  await expect(tv.page.locator(".tt-tv-round")).toHaveText("Round 1");
  const names = await tv.page.locator(".tt-tv-box").evaluateAll((els) => els.map((e) => e.getAttribute("aria-label")));
  expect(names).toEqual(expect.arrayContaining(["Ava", "Ben", "House Cat"]));
  // At a TV table, a phone's opponents are chips; the TV has the boxes.
  await expect(ava!.page.locator(".tt-chip")).toHaveCount(2);
  await expect(ava!.page.locator(".tt-mini")).toHaveCount(0);

  // The phones play; both their stacks grow on the TV.
  for (const p of phones) await expect.poll(() => playing(p), { timeout: 10_000 }).toBe(true);
  await drops(phones, 4);
  for (const w of wires) expect(setDowns(w)).toBeGreaterThanOrEqual(3);
  await expect.poll(async () => (await heights(tv.page)).filter((h) => h > 0).length, { timeout: 10_000 }).toBeGreaterThanOrEqual(2);

  // A reload mid-round: the TV goes straight back to the table and draws every box from one sync.
  const before = await heights(tv.page);
  await tv.page.reload();
  await expect(tv.page.locator(".tt-tv-box")).toHaveCount(3, { timeout: 15_000 });
  await expect.poll(async () => (await heights(tv.page)).filter((h) => h > 0).length, { timeout: 10_000 }).toBeGreaterThanOrEqual(Math.min(2, before.filter((h) => h > 0).length));
  const wake = tv.page.getByRole("button", { name: "Press OK for sound" });
  if (await wake.isVisible()) await tv.page.keyboard.press("Enter");
  // And it stays live: the next drops show.
  const after = (await heights(tv.page)).join();
  await drops(phones, 3);
  await expect.poll(async () => (await heights(tv.page)).join(), { timeout: 10_000 }).not.toBe(after);
  await closeAll(tv.context, ava!.context, ben!.context);
});
