import { spawn } from "node:child_process";

import { expect, test } from "@playwright/test";

import { BASE } from "../playwright.config";

import { catTowerTurn, deckCount, newPlayer, tableCode } from "./helpers";

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
