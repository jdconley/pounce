import { devices, expect, test, type Page, type WebSocketRoute } from "@playwright/test";

import { catTowerTurn, closeAll, deckCount, newPlayer, scan, tableCode } from "./helpers";
import {
  controllerTurn,
  ctMyTurn,
  forfeit,
  handEverOnTv,
  noHandOnTv,
  openTv,
  outsideViewport,
  phonesJoin,
  playCatTowerTurns,
  poster,
  shownLink,
  startFromPhone,
  tilesTurn,
  toyBox,
  tvDeck,
  tvMakes,
  tvPage,
  tvTable,
  TV_VIEWPORT,
} from "./tv-helpers";

/**
 * Pounce on the TV in a browser: a TV page (1920×1080, a device of its own) shows the table, and
 * browser phones (Pixel 7 and iPhone 13) play it from the controller, "Cards". Runs in the
 * `tv-chrome` project only.
 */

const banner = (tv: Page) => tv.locator(".tv-banner:not(.lost)");
const view = (phone: Page, name: "Cards" | "Table") => phone.locator("#view-switch").getByRole("button", { name, exact: true });

/** Each phone shows the controller, on "Cards". */
async function onCards(...phones: Page[]) {
  for (const p of phones) {
    await expect(p.locator(".ctl")).toBeVisible();
    await expect(view(p, "Cards")).toHaveAttribute("aria-pressed", "true");
  }
}

/** Each phone shows today's full table, with no switch: no TV is showing it. */
async function fullTable(...phones: Page[]) {
  for (const p of phones) {
    await expect(p.locator("#view-switch")).toHaveCount(0);
    await expect(p.locator(".ctl")).toHaveCount(0);
    await expect(p.locator(".ct-table")).toBeVisible();
    await expect(p.locator("#deck .pile-count")).toBeVisible();
  }
}

/** A Cat Tower turn on the full table, whoever's it is, seen by the other phone. */
async function fullTableTurn(phones: Page[]) {
  for (let i = 0; i < 60; i++) {
    for (const p of phones) {
      const before = await deckCount(p);
      if (await catTowerTurn(p)) {
        for (const other of phones) if (other !== p) await expect.poll(() => deckCount(other)).toBeLessThan(before);
        return;
      }
    }
    await phones[0]!.waitForTimeout(250);
  }
  throw new Error("no turn came");
}

test.describe("a TV and two browser phones", () => {
  test("a TV and two browser phones play Cat Tower to the end", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const [ava] = await phonesJoin(browser, code, ["Ava"]);
    // Ben has played before: he scans the lobby's QR from his own Home, and goes straight to his seat.
    const ben = await newPlayer(browser, "Ben", { context: devices["iPhone 13"] });
    await ben.page.goto(`/play/j/${code}`);
    await expect(ben.page).toHaveURL(new RegExp(`/play/t/${code}$`));
    // Each cat walks onto the TV's rug as its phone sits.
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
    await expect(tv.page.getByText("Press Start on any phone")).toBeVisible();
    await startFromPhone(ava!.page, ben!.page);

    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await expect(banner(tv.page)).toHaveText(/^(Ava|Ben)'s turn$/);
    await onCards(ava!.page, ben!.page);

    // Real turns: draws and discards, and a lay down when a hand makes the level. Each shows on the TV.
    const { laid } = await playCatTowerTurns(tv.page, [ava!.page, ben!.page], 12, {
      layDown: true,
      each: async () => {
        await expect(banner(tv.page)).toHaveText(/^(Ava|Ben)'s turn$/);
      },
    });
    test.info().annotations.push({ type: "lay downs", description: String(laid) });
    console.log(`Cat Tower on the TV: 12 turns, ${laid} lay down(s)`);
    if (laid > 0) await expect(tv.page.locator(".tv-table .group-zone").first()).toBeVisible();

    // Ben forfeits: the game is over, and the TV shows it.
    await forfeit(ben!.page);
    const over = tv.page.getByRole("dialog", { name: "Ava wins" });
    await expect(over).toBeVisible();
    await expect(over.getByText("Play again on any phone")).toBeVisible();
    await expect(ava!.page.getByRole("dialog", { name: "Ava wins" })).toBeVisible();
    await closeAll(tv.context, ava!.context, ben!.context);
  });

  test("a TV and two browser phones play Tuna Tiles to the end", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Tuna Tiles");
    const [kiki, leo] = await phonesJoin(browser, code, ["Kiki", "Leo"]);
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
    await startFromPhone(kiki!.page, leo!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await expect(banner(tv.page)).toHaveText(/^(Kiki|Leo)'s turn$/);

    // Off turn a phone holds its rack (the controller); on its turn it shows the table to play on.
    const phones = [kiki!.page, leo!.page];
    let turns = 0;
    let plays = 0;
    for (let i = 0; i < 80 && turns < 6; i++) {
      for (const p of phones) {
        const other = phones.find((o) => o !== p)!;
        if (!(await p.locator("#play-btn:not([disabled])").isVisible())) continue;
        await expect(other.locator(".tcl")).toBeVisible();
        await expect(other.locator(".tcl .tile.mine").first()).toBeVisible();
        const before = { pool: await toyBox(tv.page), laid: await tv.page.locator(".tv-table .tile:not(.draft)").count() };
        const did = await tilesTurn(p, { tv: tv.page });
        if (!did) continue;
        turns++;
        if (did === "played") plays++;
        // The TV shows the play or the draw.
        await expect
          .poll(async () => ({ pool: await toyBox(tv.page), laid: await tv.page.locator(".tv-table .tile:not(.draft)").count() }))
          .not.toEqual(before);
        await noHandOnTv(tv.page);
      }
      await tv.page.waitForTimeout(250);
    }
    expect(turns).toBe(6);
    test.info().annotations.push({ type: "plays", description: String(plays) });
    console.log(`Tuna Tiles on the TV: ${turns} turns, ${plays} play(s)`);

    await forfeit(leo!.page);
    const over = tv.page.getByRole("dialog", { name: "Kiki wins" });
    await expect(over).toBeVisible();
    await expect(over.getByText("Play again on any phone")).toBeVisible();
    await closeAll(tv.context, kiki!.context, leo!.context);
  });

  test("a pass-and-play phone with a TV", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const { context, page } = await newPlayer(browser, "Dad", { path: `/play/j/${code}`, context: devices["Pixel 7"] });
    await expect(page).toHaveURL(new RegExp(`/play/t/${code}$`));
    await page.getByRole("button", { name: "This device", exact: true }).click();
    await page.getByLabel("Your name").fill("Kid");
    await page.getByRole("button", { name: "Done" }).click();
    await expect(page.getByRole("button", { name: "Kid, on this device" })).toBeVisible();
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
    await startFromPhone(page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();

    // The phone hides each hand behind the curtain; the TV plays the turns as usual. A Cucumber
    // skips the other seat, so after one the same person goes again, hand still showing.
    let last = "";
    let skipped = false;
    for (let turn = 0; turn < 3; turn++) {
      if (skipped) {
        await expect(banner(tv.page)).toHaveText(`${last}'s turn`);
      } else {
        const curtain = page.getByRole("dialog", { name: /^Pass to (Dad|Kid)$/ });
        await expect(curtain).toBeVisible({ timeout: 30_000 });
        const who = ((await curtain.getAttribute("aria-label")) ?? "").replace("Pass to ", "");
        expect(who).not.toBe(last);
        last = who;
        await expect(banner(tv.page)).toHaveText(`${who}'s turn`);
        await expect(page.locator(".card.mine")).toHaveCount(0);
        await noHandOnTv(tv.page);

        const hold = page.getByRole("button", { name: "Hold to see your hand" });
        const box = (await hold.boundingBox())!;
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down();
        await page.waitForTimeout(900);
        await page.mouse.up();
      }
      await expect(page.locator(".ctl .card.mine").first()).toBeVisible();

      const before = await tvDeck(tv.page);
      expect(await controllerTurn(page)).toBe("turn");
      await expect.poll(() => tvDeck(tv.page)).toBeLessThan(before);
      // Then either the curtain for the other seat, or (a Cucumber skipped it) this seat's deck again.
      const curtainNext = page.getByRole("dialog", { name: /^Pass to (Dad|Kid)$/ });
      const deckAgain = page.locator("#deck:not([disabled])");
      await expect(curtainNext.or(deckAgain)).toBeVisible({ timeout: 30_000 });
      skipped = await deckAgain.isVisible();
    }
    await closeAll(tv.context, context);
  });

  test("the Cards/Table switch survives the TV leaving and coming back", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"]);
    await startFromPhone(ava!.page, ben!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await onCards(ava!.page, ben!.page);

    // Ava would rather watch the table on her phone.
    await view(ava!.page, "Table").click();
    await expect(view(ava!.page, "Table")).toHaveAttribute("aria-pressed", "true");
    await expect(ava!.page.locator(".ctl")).toHaveCount(0);
    await expect(ava!.page.locator(".ct-table .card.mine").first()).toBeVisible();

    // The TV goes. After its grace, both phones show the full table, with no switch, and play on.
    await tv.page.close();
    await fullTable(ava!.page, ben!.page);
    await fullTableTurn([ava!.page, ben!.page]);

    // The TV comes back to the table it kept. Ben is on Cards again; Ava stays on Table.
    tv.page = await tvPage(tv.context);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await onCards(ben!.page);
    await expect(view(ava!.page, "Table")).toHaveAttribute("aria-pressed", "true");
    await expect(ava!.page.locator(".ctl")).toHaveCount(0);
    await expect.poll(() => tvDeck(tv.page)).toBe(await deckCount(ava!.page));

    // The choice is this phone's, for this table: it holds after a reload.
    await ava!.page.reload();
    await expect(view(ava!.page, "Table")).toHaveAttribute("aria-pressed", "true");
    await expect(ava!.page.locator(".ctl")).toHaveCount(0);
    await closeAll(tv.context, ava!.context, ben!.context);
  });

  test("the TV drops mid-hand and comes back", async ({ browser }) => {
    const tv = await openTv(browser);
    // The TV's table socket, cut and restored by the test.
    let cut = false;
    const open = new Set<{ page: WebSocketRoute; server: WebSocketRoute }>();
    await tv.page.routeWebSocket(/\/v1\/rooms\/[A-Z0-9]+\/ws/, (ws) => {
      if (cut) return void ws.close({ code: 1011, reason: "cut" });
      const pair = { page: ws, server: ws.connectToServer() };
      open.add(pair);
      ws.onClose(() => open.delete(pair));
    });
    const code = await tvMakes(tv, "Cat Tower");
    const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"]);
    await startFromPhone(ava!.page, ben!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await playCatTowerTurns(tv.page, [ava!.page, ben!.page], 2);

    // Mid-hand, the TV loses the table: it says so over the last table it showed.
    cut = true;
    for (const pair of [...open]) {
      await pair.server.close();
      await pair.page.close({ code: 1011, reason: "cut" });
    }
    await expect(tv.page.locator(".tv-banner.lost")).toHaveText(/Reconnecting/);
    // After the grace the phones show the full table and keep playing.
    await fullTable(ava!.page, ben!.page);
    await fullTableTurn([ava!.page, ben!.page]);
    await fullTableTurn([ava!.page, ben!.page]);

    // Back: the TV catches up with the turns it missed, and the phones go back to Cards.
    const deck = await deckCount(ava!.page);
    cut = false;
    await expect(banner(tv.page)).toHaveText(/^(Ava|Ben)'s turn$/, { timeout: 30_000 });
    await expect.poll(() => tvDeck(tv.page)).toBe(deck);
    await onCards(ava!.page, ben!.page);

    // A reload (a new deploy, the TV turned off and on) goes straight back into the same table, with
    // no Start: the table shows at once, and one press of OK turns the sound on.
    await tv.page.reload();
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await expect(banner(tv.page)).toHaveText(/^(Ava|Ben)'s turn$/);
    const wake = tv.page.getByRole("button", { name: "Press OK for sound" });
    await expect(wake).toBeFocused();
    await playCatTowerTurns(tv.page, [ava!.page, ben!.page], 1);
    await tv.page.keyboard.press("Enter");
    await expect(wake).toBeHidden();
    // That press was for the sound only: it opened nothing.
    await expect(tv.page.getByRole("dialog", { name: "Menu" })).toBeHidden();
    await playCatTowerTurns(tv.page, [ava!.page, ben!.page], 1);
    await closeAll(tv.context, ava!.context, ben!.context);
  });

  test("a phone links its table to a TV on its home screen, by QR link and by backup code", async ({ browser }) => {
    // By backup code: Ava's lobby, Show on TV, the code typed as it reads (in lower case, even).
    const one = await openTv(browser);
    const ava = await newPlayer(browser, "Ava", { context: devices["Pixel 7"] });
    await ava.page.getByRole("button", { name: "Play Cat Tower" }).click();
    const x = await tableCode(ava.page);
    const typed = await shownLink(one);
    await ava.page.locator("#show-on-tv").click();
    const sheet = ava.page.getByRole("dialog", { name: "Show on TV" });
    await sheet.getByLabel("TV code").fill(typed.code.toLowerCase());
    await expect(sheet.getByLabel("TV code")).toHaveValue(typed.code);
    await sheet.getByRole("button", { name: "Show", exact: true }).click();
    await expect(ava.page.locator(".toast.good", { hasText: "On the TV" })).toBeVisible();
    expect(await tvTable(one.page)).toBe(x);

    // By QR link: a second TV's QR opens the TV-link page on Ben's phone; his table goes there.
    const two = await openTv(browser);
    const ben = await newPlayer(browser, "Ben", { context: devices["iPhone 13"] });
    await ben.page.getByRole("button", { name: "Play Tuna Tiles" }).click();
    const y = await tableCode(ben.page);
    const scanned = await shownLink(two);
    // The QR holds <origin>/tv/<token>. Opened here, on this server: under wrangler dev the origin
    // the Worker sees (and puts in the link) is the production host its route names.
    const qrPath = new URL(scanned.url).pathname;
    expect(qrPath).toMatch(/^\/tv\/[A-Za-z0-9_-]{22}$/);
    await ben.page.goto(qrPath);
    await expect(ben.page).toHaveURL(/\/play\/tv-link\/[A-Za-z0-9_-]+$/);
    await expect(ben.page.getByRole("heading", { name: "Put a table on the TV" })).toBeVisible();
    await expect(ben.page.getByRole("heading", { name: "New game" })).toBeVisible();
    await ben.page.getByRole("heading", { name: "Your tables" }).waitFor();
    await ben.page.locator(".table-card", { hasText: y }).click();
    await expect(ben.page).toHaveURL(new RegExp(`/play/t/${y}$`));
    await expect(ben.page.locator(".toast.good", { hasText: "On the TV" })).toBeVisible();
    expect(await tvTable(two.page)).toBe(y);

    // The first TV, showing Ava's table, offers another link from its menu; Ben moves it to his.
    await one.page.keyboard.press("Escape");
    await one.page.getByRole("button", { name: "Link another table" }).click();
    const again = await shownLink(one, ".tv-link-card");
    await ben.page.locator("#show-on-tv").click();
    const sheet2 = ben.page.getByRole("dialog", { name: "Show on TV" });
    await sheet2.getByLabel("TV code").fill(again.code);
    await sheet2.getByRole("button", { name: "Show", exact: true }).click();
    const move = ben.page.getByRole("dialog", { name: "Move the TV to this table?" });
    await expect(move).toBeVisible();
    await move.getByRole("button", { name: "Move", exact: true }).click();
    await expect(ben.page.locator(".toast.good", { hasText: "On the TV" })).toBeVisible();
    await expect.poll(() => tvTable(one.page)).toBe(y);
    await closeAll(one.context, two.context, ava.context, ben.context);
  });

  test("the controller fits phone sizes", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const small = await newPlayer(browser, "Great Aunt Josephine", { path: `/play/j/${code}`, context: { ...devices["Pixel 7"], viewport: { width: 320, height: 568 } } });
    const big = await newPlayer(browser, "Mo", { path: `/play/j/${code}`, context: { ...devices["iPhone 13"], viewport: { width: 430, height: 932 } } });
    await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
    await startFromPhone(small.page, big.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    const phones = [small.page, big.page];
    await onCards(...phones);

    const PARTS = ["#view-switch", ".ctl-status-pill", "#table-menu", "#deck", "#discard", ".deck.rest", ".discard.rest", ".ctl .tray", ".ctl-actions .btn", ".ctl .card.mine"];
    const fits = async (p: Page, step: string) => {
      const size = p.viewportSize()!;
      expect(await outsideViewport(p, PARTS), `${size.width}x${size.height} ${step}: outside the viewport`).toEqual([]);
      await expect(p.locator(".ctl .card.mine")).not.toHaveCount(0);
      for (const c of await p.locator(".ctl .card.mine").all()) await expect(c).toBeInViewport();
    };

    // Each phone in each step: off turn, draw, then play.
    const seen = new Set<string>();
    for (let i = 0; i < 60 && seen.size < 6; i++) {
      for (const p of phones) {
        const w = p.viewportSize()!.width;
        const live = p.locator("#deck:not([disabled])");
        const rest = p.locator(".ctl .deck.rest");
        // Settled first: off turn (the deck rests) or this phone's turn (its deck is live).
        await expect(rest.or(live)).toBeVisible();
        if (!(await live.isVisible())) {
          await fits(p, "off turn");
          seen.add(`${w} off`);
          continue;
        }
        await expect(p.locator("#deck")).toBeInViewport({ ratio: 1 });
        await fits(p, "draw");
        seen.add(`${w} draw`);
        const cards = p.locator(".card.mine .card-inner");
        const before = await cards.count();
        await p.locator("#deck").click();
        await expect(cards).toHaveCount(before + 1);
        await cards.last().press("Enter");
        await expect(p.locator("#discard-btn:not([disabled])")).toBeInViewport({ ratio: 1 });
        await fits(p, "play");
        seen.add(`${w} play`);
        await p.locator("#discard-btn").click();
        // The card left the hand. (A Cucumber skips the other phone: this one may go again.)
        await expect.poll(() => cards.count()).toBeLessThanOrEqual(before);
      }
    }
    expect([...seen].sort()).toEqual(["320 draw", "320 off", "320 play", "430 draw", "430 off", "430 play"]);
    await closeAll(tv.context, small.context, big.context);
  });

  test("Discard tapped while the drawn card flies over it discards", async ({ browser }) => {
    // The drawn card flies from the deck to the hand across the Discard button. A tap on the
    // button then must reach the button, not grab the card in flight (a lost discard leaves the
    // turn half done). The page's animations run at 1/20th speed so the flight can be caught.
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const phones = (await phonesJoin(browser, code, ["Ava", "Ben"])).map((p) => p!);
    await startFromPhone(phones[0]!.page, phones[1]!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    await expect.poll(async () => (await ctMyTurn(phones[0]!.page)) || (await ctMyTurn(phones[1]!.page))).toBe(true);
    const page = (await ctMyTurn(phones[0]!.page)) ? phones[0]!.page : phones[1]!.page;
    const cards = page.locator(".card.mine .card-inner");
    const before = await cards.count();
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Animation.enable");
    await cdp.send("Animation.setPlaybackRate", { playbackRate: 0.05 });
    await page.locator("#deck").click();
    await expect(cards).toHaveCount(before + 1);
    // A card picked while the drawn one is still on its way: Discard comes up.
    await cards.first().press("Enter");
    await expect(page.locator("#discard-btn")).toBeEnabled();
    // Wait for the flying card to cover the middle of the button, then tap there, as a finger does.
    const target = await page.waitForFunction(() => {
      const button = document.getElementById("discard-btn")?.getBoundingClientRect();
      if (!button) return null;
      const x = button.left + button.width / 2;
      const y = button.top + button.height / 2;
      // Is a moving card's own shape over that point? Asked with hit-testing on for the moving
      // cards for this one synchronous look (it may be off for them), and put back at once.
      const moving = [...document.querySelectorAll<HTMLElement>(".card.mine")].filter((c) => c.getAnimations().length > 0);
      const saved = moving.map((c) => c.style.pointerEvents);
      for (const c of moving) c.style.pointerEvents = "auto";
      const over = document.elementFromPoint(x, y)?.closest(".card.mine");
      moving.forEach((c, i) => (c.style.pointerEvents = saved[i]!));
      return over && moving.includes(over as HTMLElement) ? { x, y } : null;
    }, undefined, { polling: 10, timeout: 10_000 });
    const { x, y } = (await target.jsonValue())!;
    await page.mouse.click(x, y);
    await cdp.send("Animation.setPlaybackRate", { playbackRate: 1 });
    // The discard went: the hand is back to its size.
    await expect(cards).toHaveCount(before);
    await closeAll(tv.context, ...phones.map((p) => p.context));
  });

  test("the TV never shows a hand", async ({ browser }) => {
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"]);
    await noHandOnTv(tv.page);
    await startFromPhone(ava!.page, ben!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    // The TV shows the table (every seat, the piles), and no hand: not even the cards the phones hold.
    await expect(tv.page.getByRole("img", { name: /^Ava, 1[01] cards/ })).toBeVisible();
    await expect(tv.page.getByRole("img", { name: /^Ben, 1[01] cards/ })).toBeVisible();
    await noHandOnTv(tv.page);

    // Ben watches on Table: his phone holds his hand on the full table. The TV still has none.
    await view(ben!.page, "Table").click();
    await expect(ben!.page.locator(".ct-table .card.mine").first()).toBeVisible();
    await noHandOnTv(tv.page);

    // Turns from both phones: Ava on Cards, Ben on his full table. After each, still no hand.
    let turns = 0;
    for (let i = 0; i < 80 && turns < 4; i++) {
      for (const turn of [() => controllerTurn(ava!.page), () => catTowerTurn(ben!.page)]) {
        const before = await tvDeck(tv.page);
        if (!(await turn())) continue;
        turns++;
        await expect.poll(() => tvDeck(tv.page)).toBeLessThan(before);
        await noHandOnTv(tv.page);
      }
      await tv.page.waitForTimeout(250);
    }
    expect(turns).toBe(4);
    // The menu over the table shows no hand either.
    await tv.page.keyboard.press("Escape");
    await expect(tv.page.getByRole("dialog", { name: "Menu" })).toBeVisible();
    await noHandOnTv(tv.page);
    await tv.page.keyboard.press("Escape");
    await expect(tv.page.getByRole("dialog", { name: "Menu" })).toBeHidden();

    await forfeit(ava!.page);
    await expect(tv.page.getByRole("dialog", { name: "Ben wins" })).toBeVisible();
    await noHandOnTv(tv.page);
    // Not even for a frame between the checks: the page watched its own DOM throughout.
    expect(await handEverOnTv(tv.page)).toEqual([]);
    await closeAll(tv.context, ava!.context, ben!.context);
  });
  test("a turn counts when the server's answer comes late", async ({ browser }) => {
    // A move's events come first and the snapshot that settles it after (as on a slow runner or
    // link): the drawn card shows while the draw is still in flight, and the phone must not offer
    // a discard it will refuse.
    const tv = await openTv(browser);
    const code = await tvMakes(tv, "Cat Tower");
    const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"]);
    await startFromPhone(ava!.page, ben!.page);
    await expect(tv.page.locator(".tv-table")).toBeVisible();
    for (const p of [ava!.page, ben!.page]) {
      let queue = Promise.resolve();
      await p.routeWebSocket(/\/v1\/rooms\/[A-Z0-9]+\/ws/, (ws) => {
        const server = ws.connectToServer();
        server.onMessage((m) => {
          const late = String(m).includes('"t":"snapshot"');
          queue = queue.then(() => (late ? new Promise((r) => setTimeout(r, 300)) : undefined)).then(() => ws.send(m));
        });
        ws.onMessage((m) => server.send(m));
      });
      await p.reload();
      await expect(p.getByRole("group", { name: "Your hand" })).toBeVisible();
    }
    await view(ben!.page, "Table").click();
    let turns = 0;
    for (let i = 0; i < 80 && turns < 4; i++) {
      for (const turn of [() => controllerTurn(ava!.page), () => catTowerTurn(ben!.page)]) {
        const before = await tvDeck(tv.page);
        if (!(await turn())) continue;
        turns++;
        await expect.poll(() => tvDeck(tv.page)).toBeLessThan(before);
      }
      await tv.page.waitForTimeout(250);
    }
    expect(turns).toBe(4);
    await closeAll(tv.context, ava!.context, ben!.context);
  });
});

test("no serious accessibility problems on the TV, its phones and the TV-link page", async ({ browser }) => {
  const tv = await openTv(browser);
  await expect(poster(tv.page, "Cat Tower")).toBeVisible();
  await shownLink(tv);
  await scan(tv.page, "TV home");
  const code = await tvMakes(tv, "Cat Tower");
  const [ava, ben] = await phonesJoin(browser, code, ["Ava", "Ben"]);
  await expect(tv.page.locator(".tv-seat:not(.open)")).toHaveCount(2);
  await scan(tv.page, "TV lobby");
  await startFromPhone(ava!.page, ben!.page);
  await expect(tv.page.locator(".tv-table")).toBeVisible();
  await onCards(ava!.page, ben!.page);
  await scan(tv.page, "TV table");
  await scan(ava!.page, "phone controller (Pixel 7)");
  await scan(ben!.page, "phone controller (iPhone 13)");
  await tv.page.keyboard.press("Escape");
  await expect(tv.page.getByRole("dialog", { name: "Menu" })).toBeVisible();
  await scan(tv.page, "TV menu");

  // Another TV's QR, opened on Ava's phone: the TV-link page, listing the table she sits at.
  const two = await openTv(browser);
  const link = await shownLink(two);
  await ava!.page.goto(new URL(link.url).pathname);
  await expect(ava!.page.getByRole("heading", { name: "Put a table on the TV" })).toBeVisible();
  await expect(ava!.page.getByRole("heading", { name: "Your tables" })).toBeVisible();
  await expect(ava!.page.locator(".table-card", { hasText: code })).toBeVisible();
  await scan(ava!.page, "TV-link page");
  await closeAll(tv.context, two.context, ava!.context, ben!.context);
});

test("a TV browser too old for the app is told what to use instead", async ({ browser }) => {
  const context = await browser.newContext({ viewport: TV_VIEWPORT });
  const words = "Use a laptop or an Apple TV.";
  const app = /\/play\/assets\/index-[^/]+\.js$/;

  // The app's module never runs (blocked here; on an old TV, refused): told once the page has loaded.
  const blocked = await context.newPage();
  await blocked.route(app, (r) => r.abort());
  await blocked.goto("/play/tv");
  await expect(blocked.getByText(words)).toBeVisible({ timeout: 10_000 });

  // It runs but can't be parsed, as on Tizen and webOS with an older Chromium: told at once, on the
  // module's SyntaxError, well before the load check would.
  const old = await context.newPage();
  await old.route(app, (r) => r.fulfill({ contentType: "text/javascript", body: "const pounce = ;" }));
  await old.goto("/play/tv");
  await expect(old.getByText(words)).toBeVisible({ timeout: 1000 });

  // Only the TV page says it: a phone page with no app shows nothing of the kind.
  const phone = await context.newPage();
  await phone.route(app, (r) => r.abort());
  await phone.goto("/play/");
  await phone.waitForTimeout(4000);
  await expect(phone.getByText(words)).toHaveCount(0);

  // A TV browser that runs the app never sees it.
  const fine = await context.newPage();
  await fine.goto("/play/tv");
  await expect(fine.getByRole("button", { name: "Start", exact: true })).toBeVisible();
  await fine.waitForTimeout(4000);
  await expect(fine.getByText(words)).toHaveCount(0);
  await expect(fine.getByRole("button", { name: "Start", exact: true })).toBeVisible();
  await context.close();
});
