import { spawn } from "node:child_process";

import { devices, expect, test, type Browser, type Page } from "@playwright/test";

import { BASE } from "../playwright.config";

import { birdTable, playToTheEnd } from "./birdwatch-helpers";
import { catTowerTurn, closeAll, deckCount, newPlayer, ownAddress, tableCode } from "./helpers";
import { controllerTurn, forfeit, handEverOnTv, noHandOnTv, startFromPhone, tvDeck, tvMakes, tvPage, TV_VIEWPORT, type Tv } from "./tv-helpers";

/**
 * A web player and an iOS-protocol client at one table: `pounce-e2e` (PounceKit, the app's own
 * networking and models) joins the web player's table and plays its seat, as the iPhone app
 * would. Needs the built CLI: POUNCE_E2E=apps/play-ios/PounceKit/.build/debug/pounce-e2e (on a
 * Mac; `swift build --product pounce-e2e`). Skipped without it.
 */
const CLI = process.env.POUNCE_E2E;

test.skip(!CLI, "POUNCE_E2E is not set");

/** Sound and vibration off, on a phone and on a TV page (each keeps its own settings). */
const QUIET = JSON.stringify({ sound: false, haptics: false });
const MUTED = {
  storageState: {
    cookies: [],
    origins: [
      {
        origin: new URL(BASE).origin,
        localStorage: [
          { name: "pounce.settings", value: QUIET },
          { name: "pounce.tv.settings", value: QUIET },
        ],
      },
    ],
  },
};

/** A TV page as `openTv` makes one, with its sound off from the first paint; `before` runs ahead of every page script. */
async function openMutedTv(browser: Browser, before?: string): Promise<Tv> {
  const context = await browser.newContext({ viewport: TV_VIEWPORT, isMobile: false, hasTouch: false, ...MUTED });
  await ownAddress(context);
  if (before) await context.addInitScript(before);
  return { context, page: await tvPage(context), links: [] };
}

test("a web player and the iOS client play Cat Tower at one table", async ({ browser }, info) => {
  test.skip(info.project.name !== "android-chrome", "one browser is enough for the mixed table");
  const web = await newPlayer(browser, "Webby", { context: MUTED });
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
  const tv = await openMutedTv(browser);
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
    const web = await newPlayer(browser, "Webby", { path: `/play/j/${code}`, context: MUTED });
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

/**
 * Birdwatch with the iOS client at the table: `pounce-e2e birdwatch` plays its seat from what the
 * server sends it (`bidRange`, `fromNest`, `partnerChoices`, `playable`), as the app does, and
 * every table is played to game over. Each client must end without an error: the CLI fails on any
 * error the server sends it, and the browsers on a page error or an error frame from the server.
 */
test.describe("Birdwatch", () => {
  // House Cats move fast on the test server; the table's own pacing is what takes the time.
  test.use({ reducedMotion: "reduce" });

  /** `pounce-e2e` with these arguments against the test server: its output, line by line, and its exit. */
  function swift(args: string[]) {
    const lines: string[] = [];
    const proc = spawn(CLI as string, [...args, "--base", BASE], { stdio: ["ignore", "pipe", "pipe"] });
    let rest = "";
    const take = (d: Buffer) => {
      const parts = (rest + String(d)).split("\n");
      rest = parts.pop() ?? "";
      lines.push(...parts);
    };
    proc.stdout.on("data", take);
    proc.stderr.on("data", take);
    const exited = new Promise<number | null>((resolve) => proc.on("exit", (c) => resolve(c)));
    const text = () => [...lines, rest].join("\n");
    return { proc, lines, exited, text };
  }

  /** Page errors and the server's error frames on `page` (its sockets from now on). */
  function errorsOn(page: Page, who: string): string[] {
    const out: string[] = [];
    page.on("pageerror", (e) => out.push(`${who} pageerror: ${e.message}`));
    page.on("websocket", (ws) =>
      ws.on("framereceived", (f) => {
        const text = String(f.payload);
        if (text.includes('"t":"error"')) out.push(`${who} server error: ${text.slice(0, 200)}`);
      }),
    );
    return out;
  }

  /** A muted phone, named on Home, then at `path` (an invite link) with its errors watched from the start. */
  async function phone(browser: Browser, name: string, path?: string) {
    const p = await newPlayer(browser, name, { context: { ...devices["Pixel 7"], ...MUTED } });
    const errors = errorsOn(p.page, name);
    if (path) await p.page.goto(path);
    return { ...p, errors };
  }

  async function exitOf(exited: Promise<number | null>, seconds: number): Promise<number | null | "running"> {
    return Promise.race([exited, new Promise<"running">((r) => setTimeout(() => r("running"), seconds * 1000))]);
  }

  const RULES = { Official: "official", Tucker: "tucker", Friesen: "friesen" } as const;

  for (const [seats, rules, host] of [
    [4, "Official", "web"],
    [5, "Tucker", "ios"],
    [6, "Friesen", "web"],
  ] as const) {
    test(`a web player and the iOS client play Birdwatch to the end: ${seats} players, ${rules}, the ${host === "web" ? "web player" : "iOS client"} hosts`, async ({ browser }, info) => {
      test.skip(info.project.name !== "android-chrome", "one browser is enough for the mixed table");
      test.setTimeout(25 * 60_000);
      const id = RULES[rules];
      let web: Awaited<ReturnType<typeof phone>>;
      let ios: ReturnType<typeof swift>;
      if (host === "web") {
        // The web player makes the table, picks the rules and fills it with House Cats; the iOS
        // client takes a House Cat's seat, as the app does.
        web = await phone(browser, "Webby");
        const code = await birdTable(web.page, rules, seats);
        ios = swift(["birdwatch", "join", code, "--rules", id, "--name", "Remote", "--cat", "5", "--timeout", "1400"]);
        await expect(web.page.getByRole("button", { name: "Remote, on another device" })).toBeVisible({ timeout: 60_000 });
        await expect(web.page.locator(".lobby-seat.bot")).toHaveCount(seats - 2);
        await web.page.getByRole("button", { name: "Start" }).click();
      } else {
        // The iOS client makes the table, sets the rules, leaves a seat open for the web player
        // and fills the rest with House Cats; it starts once the web player has sat down.
        ios = swift(["birdwatch", "host", "--rules", id, "--seats", String(seats), "--guests", "1", "--name", "Remote", "--cat", "5", "--timeout", "1400"]);
        await expect.poll(() => /^room ([A-Z0-9]{5})$/m.exec(ios.text())?.[1], { timeout: 30_000 }).toBeTruthy();
        const code = /^room ([A-Z0-9]{5})$/m.exec(ios.text())![1]!;
        await expect.poll(() => ios.text(), { timeout: 30_000 }).toContain("waiting for 1 guest");
        web = await phone(browser, "Webby", `/play/j/${code}`);
        await expect(web.page).toHaveURL(new RegExp(`/play/t/${code}$`));
      }
      try {
        await expect(web.page.locator(".bw-table")).toBeVisible({ timeout: 60_000 });
        await expect(web.page.locator(".bw-seat")).toHaveCount(seats - 1);
        await expect(web.page.locator(".bw-chip")).toHaveCount(seats === 5 ? 5 : seats / 2);

        const stats = await playToTheEnd([web.page], ["taps"], { minutes: 20 });
        console.log(`mixed Birdwatch ${seats}p ${rules}: web ${JSON.stringify({ ...stats, hands: stats.hands.size })}`);
        expect(stats.plays).toBeGreaterThan(8);
        await expect(web.page.getByRole("dialog", { name: /wins?$|^Game over$/ })).toBeVisible();

        // The iOS client saw the same game end, under the same rules, with no error.
        expect(await exitOf(ios.exited, 60), "the iOS client's exit").toBe(0);
        const out = ios.text();
        expect(out).toContain(`dealt rules=${id} seats=${seats}`);
        expect(out).toMatch(new RegExp(`^birdwatch over rules=${id} seats=${seats} hands=\\d+ winners=\\[\\d`, "m"));
        expect(out).toMatch(/^\[(remote|host)\] hand 1 /m);
        expect(out).toMatch(/plays=[1-9]/);
        expect(out).not.toContain("FAIL");
        expect(web.errors).toEqual([]);
        await closeAll(web.context);
      } finally {
        ios.proc.kill();
        console.log(ios.text());
      }
    });
  }

  /**
   * Watches the TV page from its first paint: any hand card or partner mark ever put in its DOM,
   * even for a frame, is noted.
   */
  const WATCH_BIRD = `
    window.__birdSeen = [];
    const look = () => {
      for (const el of document.querySelectorAll(".bw-hand-card, .bw-partner-mark, #bw-partner-mark")) window.__birdSeen.push(el.className || el.id);
    };
    new MutationObserver(look).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] });
  `;

  test("the iOS client at a TV table: a TV page, the iOS client and a browser phone play Birdwatch to the end", async ({ browser }, info) => {
    test.skip(info.project.name !== "android-chrome", "one browser is enough for the mixed table");
    test.setTimeout(25 * 60_000);
    // The TV makes the table; the iOS client sits first, so it is the host and picks the rules.
    const tv = await openMutedTv(browser, WATCH_BIRD);
    const tvErrors = errorsOn(tv.page, "TV");
    const code = await tvMakes(tv, "Birdwatch");
    await expect(tv.page.locator(".tv-lobby-rules")).toHaveText("Official");

    const ios = swift(["birdwatch", "join", code, "--rules", "tucker", "--name", "Remote", "--cat", "5", "--timeout", "1400"]);
    try {
      await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(1, { timeout: 60_000 });
      await expect(tv.page.getByRole("img", { name: "Remote" })).toBeVisible();
      await expect(tv.page.locator(".tv-lobby-rules")).toHaveText("Tucker");

      // A browser phone joins from the lobby's link, sits, adds three House Cats and starts.
      const web = await phone(browser, "Webby", `/play/j/${code}`);
      await expect(web.page).toHaveURL(new RegExp(`/play/t/${code}$`));
      await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
      await expect(web.page.getByRole("radio", { name: "Tucker" })).toHaveAttribute("aria-checked", "true");
      for (let n = 2; n < 5; n++) {
        await web.page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
        await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(n + 1);
      }
      await startFromPhone(web.page);
      await expect(tv.page.locator(".bw-tv")).toBeVisible();
      await expect(tv.page.locator(".bw-tv .bw-seat")).toHaveCount(5);
      await expect(tv.page.locator(".bw-tv-rules")).toHaveText("Tucker, to 500");
      await expect(web.page.locator(".bw-table.cards-view")).toBeVisible();

      const stats = await playToTheEnd([web.page], ["taps"], { minutes: 20 });
      console.log(`mixed Birdwatch TV 5p Tucker: phone ${JSON.stringify({ ...stats, hands: stats.hands.size })}`);
      expect(stats.plays).toBeGreaterThan(8);

      // The TV shows the end, and never showed a hand or the partner mark.
      await expect(tv.page.getByRole("dialog", { name: /wins?$|^Game over$/ })).toBeVisible({ timeout: 60_000 });
      expect(await exitOf(ios.exited, 60), "the iOS client's exit").toBe(0);
      const out = ios.text();
      expect(out).toContain("dealt rules=tucker seats=5");
      expect(out).toMatch(/^birdwatch over rules=tucker seats=5 hands=\d+ winners=\[\d/m);
      expect(out).not.toContain("FAIL");
      await noHandOnTv(tv.page);
      await expect(tv.page.locator(".bw-hand-card, .bw-partner-mark")).toHaveCount(0);
      expect(await tv.page.evaluate(() => (window as unknown as { __birdSeen?: string[] }).__birdSeen?.slice(0, 10)), "hand cards or a partner mark ever in the TV's DOM").toEqual([]);
      expect(await handEverOnTv(tv.page), "hand cards ever in the TV's DOM").toEqual([]);
      expect([...web.errors, ...tvErrors]).toEqual([]);
      await closeAll(web.context);
    } finally {
      ios.proc.kill();
      console.log(ios.text());
      await tv.context.close();
    }
  });
});
