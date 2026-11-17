import { spawn } from "node:child_process";

import { expect, test } from "@playwright/test";

import { BASE } from "../playwright.config";

import { catTowerTurn, closeAll, deckCount, newPlayer, tableCode } from "./helpers";
import { controllerTurn, forfeit, handEverOnTv, noHandOnTv, openTv, startFromPhone, tvDeck, tvMakes } from "./tv-helpers";

/**
 * A web player and an iOS-protocol client at one table: `pounce-e2e` (PounceKit, the app's own
 * networking and models) joins the web player's table and plays its seat, as the iPhone app
 * would. Needs the built CLI: POUNCE_E2E=apps/play-ios/PounceKit/.build/debug/pounce-e2e (on a
 * Mac; `swift build --product pounce-e2e`). Skipped without it.
 */
const CLI = process.env.POUNCE_E2E;

test.skip(!CLI, "POUNCE_E2E is not set");

test("a web player and the iOS client play Cat Tower at one table", async ({ browser }, info) => {
  test.skip(info.project.name !== "android-chrome", "one browser is enough for the mixed table");
  const web = await newPlayer(browser, "Webby");
  await web.page.getByRole("button", { name: "Play Cat Tower" }).click();
  const code = await tableCode(web.page);

  const lines: string[] = [];
  const ios = spawn(CLI as string, ["join", code, "--name", "Remote", "--cat", "5", "--base", BASE, "--timeout", "300"], { stdio: ["ignore", "pipe", "pipe"] });
  ios.stdout.on("data", (d) => lines.push(...String(d).trim().split("\n")));
  ios.stderr.on("data", (d) => lines.push(...String(d).trim().split("\n")));
  try {
    // The iOS client takes the House Cat's seat, as the app does.
    await expect(web.page.getByRole("button", { name: "Remote, on another device" })).toBeVisible({ timeout: 60_000 });
    await web.page.getByRole("button", { name: "Start" }).click();
    await expect(web.page.locator("#deck")).toBeVisible();

    // Play turns from the web; the iOS client plays its own between them.
    let webTurns = 0;
    for (let i = 0; i < 120 && webTurns < 5; i++) {
      const before = await deckCount(web.page);
      if (await catTowerTurn(web.page)) {
        webTurns++;
        // Then the remote seat plays (from the deck or the discard) and the turn comes back.
        await expect(web.page.locator("#deck:not([disabled])")).toBeVisible({ timeout: 60_000 });
        expect(await deckCount(web.page)).toBeLessThan(before);
      } else {
        await web.page.waitForTimeout(300);
      }
    }
    expect(webTurns).toBe(5);
    expect(lines.join("\n")).toContain(`joined ${code}`);
    expect(lines.join("\n")).toContain("game started");

    await web.page.getByRole("button", { name: "Menu" }).click();
    await web.page.getByRole("button", { name: "Forfeit" }).click();
    await web.page.locator("#forfeit").click();
    await expect(web.page.getByRole("dialog", { name: "Remote wins" })).toBeVisible();
  } finally {
    ios.kill();
    console.log(lines.join("\n"));
  }
});

test("the iOS client at a TV table: a TV page, the iOS client and a browser phone play Cat Tower", async ({ browser }, info) => {
  test.skip(info.project.name !== "android-chrome", "one browser is enough for the mixed table");
  // The TV makes the table; the iOS client sits first, as a phone scanning the lobby would.
  const tv = await openTv(browser);
  const code = await tvMakes(tv, "Cat Tower");

  const lines: string[] = [];
  const ios = spawn(CLI as string, ["join", code, "--name", "Remote", "--cat", "5", "--base", BASE, "--timeout", "300"], { stdio: ["ignore", "pipe", "pipe"] });
  ios.stdout.on("data", (d) => lines.push(...String(d).trim().split("\n")));
  ios.stderr.on("data", (d) => lines.push(...String(d).trim().split("\n")));
  const exited = new Promise<number | null>((resolve) => ios.on("exit", (c) => resolve(c)));
  try {
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(1, { timeout: 60_000 });
    await expect(tv.page.getByRole("img", { name: "Remote" })).toBeVisible();

    // A browser phone joins from the lobby's link, sits, and starts the game.
    const web = await newPlayer(browser, "Webby", { path: `/play/j/${code}` });
    await expect(web.page).toHaveURL(new RegExp(`/play/t/${code}$`));
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
    await startFromPhone(web.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await expect(web.page.locator(".ctl")).toBeVisible();

    // The browser phone plays from the controller; the iOS client plays its own turns between.
    let webTurns = 0;
    for (let i = 0; i < 200 && webTurns < 4; i++) {
      const before = await tvDeck(tv.page);
      if (await controllerTurn(web.page)) {
        webTurns++;
        await expect.poll(() => tvDeck(tv.page)).toBeLessThan(before);
        // Then Remote draws and discards, and the turn comes back to the phone.
        await expect(web.page.locator("#deck:not([disabled])")).toBeVisible({ timeout: 60_000 });
        await noHandOnTv(tv.page);
      } else {
        await web.page.waitForTimeout(300);
      }
    }
    expect(webTurns).toBe(4);
    expect(lines.join("\n")).toContain(`joined ${code}`);
    expect(lines.join("\n")).toContain("game started");

    // The browser phone forfeits: Remote wins, the TV shows it, and the iOS client sees the end.
    await forfeit(web.page);
    const over = tv.page.getByRole("dialog", { name: "Remote wins" });
    await expect(over).toBeVisible();
    await expect(over.getByText("Play again on any phone")).toBeVisible();
    expect(await Promise.race([exited, new Promise<"running">((r) => setTimeout(() => r("running"), 30_000))]), "the iOS client's exit").toBe(0);
    expect(lines.join("\n")).toMatch(/rounds=\d+ winners=\d/);
    expect(await handEverOnTv(tv.page), "hand cards ever in the TV's DOM").toEqual([]);
    await closeAll(web.context);
  } finally {
    ios.kill();
    console.log(lines.join("\n"));
    await tv.context.close();
  }
});
