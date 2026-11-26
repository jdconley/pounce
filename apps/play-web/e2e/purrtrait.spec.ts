import { devices, expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer } from "./helpers";
import { differ, drawerPage, drawStroke, easelPicture, inked, liftCurtain, phoneScans, PURR, purrTv, tvMakesPurrtrait } from "./purr-helpers";

/**
 * Purrtrait end to end (design §12): the TV page is the easel; three phones, one of them shared by
 * two players, join from the code the TV shows and play a whole game. Each drawing shows on the TV
 * while it is drawn; a TV reloaded mid-turn, after an undo and a clear, comes back with the same
 * picture. Joining works only from the TV's current code, and a removed phone stays out.
 */

test.describe.configure({ mode: "serial" });

test("a TV and three phones, one shared, play a whole game, and the TV shows every drawing as it is drawn", async ({ browser }) => {
  test.setTimeout(600_000);
  const tv = await purrTv(browser);
  await tvMakesPurrtrait(tv);
  const mom = await phoneScans(browser, tv, "Mom", devices["Pixel 7"]);
  const dad = await phoneScans(browser, tv, "Dad", devices["iPhone 13"]);
  const kids = await phoneScans(browser, tv, "Ava", devices["Pixel 7"]);
  // Leo plays on Ava's phone.
  await kids.page.locator("#purr-this-device").click();
  await kids.page.getByLabel("Your name").fill("Leo");
  await kids.page.getByRole("button", { name: "Done" }).click();
  await expect(tv.page.locator(".tv-lobby .tv-seat:not(.open)")).toHaveCount(4);
  // The host picks the turn's time; the TV says it.
  await mom.page.getByRole("radio", { name: "0:45" }).click();
  await expect(tv.page.locator("#tv-purr-timer")).toHaveText("0:45 a turn");
  await mom.page.locator("#start").click();
  await expect(tv.page.locator(".purr-tv")).toBeVisible();

  const pages = [mom.page, dad.page, kids.page];
  // Everyone draws twice: 4 players, 8 turns.
  for (let turn = 0; turn < 8; turn++) {
    const drawer = await drawerPage(pages);
    if ((await drawer.locator(".curtain").count()) > 0) await liftCurtain(drawer);
    const cards = drawer.locator("#purr-cards");
    if (await cards.isVisible().catch(() => false)) await drawer.locator(turn % 2 ? "#pick-tricky" : "#pick-easy").click();
    await expect(drawer.locator("#purr-easel")).toBeVisible();
    await expect(tv.page.locator("#tv-group")).toBeVisible();
    // Nobody else's phone shows the word or the drawing.
    for (const other of pages.filter((p) => p !== drawer)) {
      await expect(other.locator("#purr-easel")).toHaveCount(0);
      await expect(other.locator("#purr-look")).toBeVisible();
    }
    const before = inked(await easelPicture(tv.page));
    await drawStroke(drawer, [[0.15, 0.55], [0.5, 0.35], [0.85, 0.55], [0.5, 0.8]]);
    // The line shows on the TV while it is drawn.
    await expect.poll(async () => inked(await easelPicture(tv.page)), { message: "the stroke on the TV" }).toBeGreaterThan(before + 10);

    if (turn === 1) await reloadKeepsTheDrawing(tv.page, drawer);

    if (turn % 4 === 2) {
      await drawer.locator("#purr-give-up").click();
      await drawer.locator("#purr-give-up-yes").click();
      await expect(tv.page.locator(".purr-reveal")).toContainText(/Gave up/);
    } else {
      await drawer.locator("#purr-got-it").click();
      await drawer.locator(".purr-who-btn").first().click();
      await expect(tv.page.locator(".purr-reveal")).toContainText(/got it/);
    }
    // After the reveal, the next turn blanks the easel.
    await expect(tv.page.locator(".purr-reveal")).toBeHidden({ timeout: 20_000 });
  }
  await expect(tv.page.locator(".tv-over")).toBeVisible();
  for (const p of pages) await expect(p.locator(".game-over")).toBeVisible();
  await closeAll(mom.context, dad.context, kids.context, tv.context);
});

/** Undo and clear on the drawer's phone, then the TV reloads: it comes back with the same picture. */
async function reloadKeepsTheDrawing(tv: Page, drawer: Page): Promise<void> {
  await drawStroke(drawer, [[0.1, 0.9], [0.9, 0.9]]);
  await drawer.locator("#purr-undo").click();
  await drawer.locator("#purr-clear").click();
  await expect.poll(async () => inked(await easelPicture(tv))).toBeLessThan(5);
  await drawer.getByRole("radio", { name: "Blue" }).click();
  await drawStroke(drawer, [[0.2, 0.3], [0.8, 0.3], [0.8, 0.7], [0.2, 0.7], [0.2, 0.3]]);
  await drawer.getByRole("radio", { name: "Red" }).click();
  await drawer.getByRole("radio", { name: "Thick" }).click();
  await drawStroke(drawer, [[0.3, 0.5], [0.7, 0.5]]);
  await drawStroke(drawer, [[0.5, 0.4], [0.5, 0.6]]);
  await drawer.locator("#purr-undo").click();
  await expect.poll(async () => inked(await easelPicture(tv))).toBeGreaterThan(30);
  // Settled: what the TV shows now is everything sent.
  await tv.waitForTimeout(400);
  const live = await easelPicture(tv);
  await tv.reload();
  await tv.getByRole("button", { name: "Press OK for sound" }).click();
  await expect(tv.locator("#tv-easel")).toBeVisible();
  await expect.poll(async () => differ(live, await easelPicture(tv)), { message: "the TV's picture after a reload" }).toBeLessThanOrEqual(Math.ceil(live.ink.length * 0.01));
}

test("joining is only from the TV's code, and a removed phone stays out", async ({ browser }) => {
  test.setTimeout(240_000);
  const tv = await purrTv(browser);
  const code = await tvMakesPurrtrait(tv);
  const host = await phoneScans(browser, tv, "Mom");

  // A wrong or stale key, or the plain table link: refused.
  const stale = await newPlayer(browser, "Stranger", { path: `/play/e/${code}?near=ZZZZZZZZ`, context: { ...devices["iPhone 13"], baseURL: PURR } });
  await expect(stale.page.locator("#table-refused")).toHaveText("Scan the code on the TV.");
  await stale.page.goto(`/play/t/${code}`);
  await expect(stale.page.locator("#table-refused")).toHaveText("Scan the code on the TV.");

  // The code the TV shows, typed: in.
  const typed = ((await tv.page.locator(".tv-lobby .tv-code").textContent()) ?? "").replace(/\s/g, "");
  const guest = await newPlayer(browser, "Dad", { path: "/play/join", context: { ...devices["Pixel 7"], baseURL: PURR } });
  await guest.page.getByLabel("Table code").fill(typed);
  await guest.page.getByRole("button", { name: "Join", exact: true }).click();
  await expect(guest.page.getByRole("button", { name: /^Dad, on this device/ })).toBeVisible();
  await expect(tv.page.locator(".tv-lobby .tv-seat:not(.open)")).toHaveCount(2);

  // The host removes Dad: his phone is out, and stays out, even with a fresh code.
  await host.page.getByRole("button", { name: /^Dad, on another device/ }).click();
  await host.page.locator("#remove-seat").click();
  await expect(guest.page.locator("#table-refused")).toHaveText("The host removed you from this table.");
  await expect(tv.page.locator(".tv-lobby .tv-seat:not(.open)")).toHaveCount(1);
  const fresh = (await tv.page.locator(".tv-lobby .tv-qr[data-url]").getAttribute("data-url"))!;
  await guest.page.goto(fresh);
  await expect(guest.page.locator("#table-refused")).toHaveText("The host removed you from this table.");
  await closeAll(host.context, stale.context, guest.context, tv.context);
});
