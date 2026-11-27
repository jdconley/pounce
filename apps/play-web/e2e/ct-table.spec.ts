import { expect, test, type Page } from "@playwright/test";

import { firstRun, ownAddress, standInServer } from "./helpers";

import type { RoomView, ServerMessage } from "@pounce/play-api/protocol";
import type { GameEvent } from "@pounce/play-api/rules/engine";
import type { CatTowerView } from "@pounce/play-api/rules/view";

/**
 * The Cat Tower table on a phone, handed its room by a stand-in for the server: who is pickled,
 * and the Table a phone on Cards turns to when its player lays down.
 */
const ME = "11111111-1111-4111-8111-111111111111";
const SHOTS = process.env.SHOTS;
const CUCUMBER = 104;

const seats: RoomView["seats"] = [
  { kind: "human", person: { id: ME, name: "Ada", cat: 1 }, yours: true, presence: "awake" },
  { kind: "bot", yours: false, presence: null },
  { kind: "human", person: { id: "22222222-2222-4222-8222-222222222222", name: "Bo", cat: 5 }, yours: false, presence: "awake" },
];

const game = (over: Partial<CatTowerView> = {}): CatTowerView => ({
  round: 1,
  dealer: 2,
  turn: 0,
  step: "play",
  status: "playing",
  deckCount: 40,
  discardTop: 0,
  discardCount: 1,
  phase: [0, 2, 1],
  scores: [0, 0, 0],
  laid: [null, null, null],
  handCounts: [8, 10, 10],
  hands: { 0: [CUCUMBER, 1, 13, 25, 4, 16, 28, 9] },
  pendingSkip: [false, false, false],
  winners: [],
  forfeited: [false, false, false],
  ...over,
});
const room = (g: CatTowerView, over: Partial<RoomView> = {}): RoomView => ({ code: "BCDFG", name: "Pickles", status: "playing", youAreHost: true, seats, game: g, ...over });

/** Plays `events` from the server, then the snapshot after them. */
function server(send: (m: ServerMessage) => void) {
  let seq = 1;
  return (events: GameEvent[], after: RoomView) => {
    for (const event of events) send({ t: "event", seq: ++seq, event: { kind: "game", event } });
    send({ t: "snapshot", protocol: 1, seq, room: after });
  };
}

const avatar = (page: Page, name: string) => page.locator(".avatar-at .seat-avatar", { has: page.locator(".name-tag", { hasText: name }) });

test.beforeEach(async ({ page, context }, info) => {
  test.skip(info.project.name === "laptop-firefox" || info.project.name === "laptop-safari", "phones and the laptop");
  await ownAddress(context);
  await page.goto("/play/");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
});

test("a Cucumber's target shows pickled until the turn played in its place is over", async ({ page }, info) => {
  const { send } = await standInServer(page);
  const play = server(send);
  send({ t: "snapshot", protocol: 1, seq: 1, room: room(game()) });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(8);
  const cat = avatar(page, "House Cat");
  await expect(cat).not.toHaveClass(/\bpickled\b/);

  // Ada pickles the House Cat, who is next: its turn goes by at once, and Bo plays in its place.
  play(
    [
      { kind: "discarded", seat: 0, card: CUCUMBER, skipTarget: 1 },
      { kind: "skipped", seat: 1 },
      { kind: "turn", seat: 2 },
    ],
    room(game({ turn: 2, step: "draw", discardTop: CUCUMBER, discardCount: 2, handCounts: [7, 10, 10], hands: { 0: [1, 13, 25, 4, 16, 28, 9] } })),
  );
  await expect(page.locator(".cue")).toHaveText("Bo's turn");
  await expect(cat).toHaveClass(/\bpickled\b/);
  await expect(cat).toHaveAttribute("aria-label", /, pickled/);
  await expect(cat.locator(".pickled-tag")).toHaveText("Pickled");
  await expect(page.locator(".tower")).toHaveAttribute("aria-label", /House Cat: level 3, pickled/);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/pickled-phone-${info.project.name}.png` });

  // Bo draws: still Bo's turn, still pickled.
  play([{ kind: "drew", seat: 2, from: "deck" }], room(game({ turn: 2, step: "play", deckCount: 39, discardTop: CUCUMBER, discardCount: 2, handCounts: [7, 10, 11], hands: { 0: [1, 13, 25, 4, 16, 28, 9] } })));
  await expect(page.locator("#deck .pile-count")).toHaveText("39");
  await expect(cat).toHaveClass(/\bpickled\b/);

  // Bo's turn ends: the House Cat is back in the game.
  play(
    [
      { kind: "discarded", seat: 2, card: 50 },
      { kind: "turn", seat: 0 },
    ],
    room(game({ turn: 0, step: "draw", deckCount: 39, discardTop: 50, discardCount: 3, handCounts: [7, 10, 10], hands: { 0: [1, 13, 25, 4, 16, 28, 9] } })),
  );
  await expect(page.locator(".cue")).toHaveText("Draw a card");
  await expect(cat).not.toHaveClass(/\bpickled\b/);
  await expect(cat).not.toHaveAttribute("aria-label", /pickled/);
});

test("a Cucumber aimed past the next player shows pickled while it waits", async ({ page }) => {
  const { send } = await standInServer(page);
  const play = server(send);
  send({ t: "snapshot", protocol: 1, seq: 1, room: room(game()) });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(8);

  // Ada pickles Bo: the House Cat plays first, and Bo waits, pickled.
  play(
    [
      { kind: "discarded", seat: 0, card: CUCUMBER, skipTarget: 2 },
      { kind: "turn", seat: 1 },
    ],
    room(game({ turn: 1, step: "draw", discardTop: CUCUMBER, discardCount: 2, handCounts: [7, 10, 10], hands: { 0: [1, 13, 25, 4, 16, 28, 9] }, pendingSkip: [false, false, true] })),
  );
  const bo = avatar(page, "Bo");
  await expect(bo).toHaveClass(/\bpickled\b/);
  await expect(avatar(page, "House Cat")).not.toHaveClass(/\bpickled\b/);
});

test("laying down on Cards turns this phone to the Table, and no one else's does", async ({ page }, info) => {
  test.skip(info.project.name === "laptop-chrome", "a phone at a TV table");
  const { send } = await standInServer(page);
  const play = server(send);
  // A TV shows the table: this phone is on Cards.
  const hand = [1, 13, 25, 4, 16, 28, 9, 11];
  const tv = (g: CatTowerView) => room(g, { screen: true });
  const two = { seats: seats.slice(0, 2) };
  const g0 = game({ phase: [0, 0], scores: [0, 0], laid: [null, null], handCounts: [8, 10], hands: { 0: hand }, pendingSkip: [false, false], forfeited: [false, false], dealer: 1, turn: 1, step: "play" });
  send({ t: "snapshot", protocol: 1, seq: 1, room: { ...tv(g0), ...two } });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".ctl")).toBeVisible();
  const view = (name: "Cards" | "Table") => page.locator("#view-switch").getByRole("button", { name, exact: true });
  await expect(view("Cards")).toHaveAttribute("aria-pressed", "true");

  // The House Cat lays down: this phone stays on Cards.
  const cats: CatTowerView["laid"][number] = [
    { kind: "set", cards: [7, 19, 31], value: 8 },
    { kind: "set", cards: [10, 22, 34], value: 11 },
  ];
  const g1 = { ...g0, laid: [null, cats], handCounts: [8, 4] };
  play([{ kind: "laidDown", seat: 1, groups: cats! }], { ...tv(g1), ...two });
  // (The event has its moment on stage, then the snapshot lands.)
  await page.waitForTimeout(900);
  await expect(page.locator(".ctl")).toBeVisible();
  await expect(view("Cards")).toHaveAttribute("aria-pressed", "true");

  // Ada lays down (her turn now): the Table, with her groups and the House Cat's.
  const mine: CatTowerView["laid"][number] = [
    { kind: "set", cards: [1, 13, 25], value: 2 },
    { kind: "set", cards: [4, 16, 28], value: 5 },
  ];
  const g2 = { ...g1, turn: 0, laid: [mine, cats], handCounts: [2, 4], hands: { 0: [9, 11] } };
  play([{ kind: "turn", seat: 0 }, { kind: "laidDown", seat: 0, groups: mine! }], { ...tv(g2), ...two });
  await expect(page.locator(".ctl")).toHaveCount(0);
  await expect(view("Table")).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".ct-table .group-zone")).toHaveCount(4);
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(2);
  await page.waitForTimeout(700);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/laid-down-table-${info.project.name}.png` });

  // It stays, as a press of the switch would: through a reload, and until Cards is pressed.
  await page.reload();
  await expect(view("Table")).toHaveAttribute("aria-pressed", "true");
  await view("Cards").click();
  await expect(page.locator(".ctl")).toBeVisible();
});

/**
 * Discarding with the level made in the trays asks "Lay down first?": people forget to lay down.
 * Lay down (the focused choice, so Enter) lays it down; Discard anyway discards; Esc goes back.
 * Nothing in the trays, or trays that don't make the level yet, discard without asking.
 */
test.describe("Lay down first?", () => {
  // 2s and 5s of three coats each make level 1 (two sets of three); the 10 and the 12 don't fit.
  const HAND = [1, 25, 49, 4, 28, 52, 9, 11];
  const label = (id: number) => `${(id % 12) + 1}, ${["tabby", "tuxedo", "calico", "gray"][Math.floor(id / 24)]}`;
  const two = seats.slice(0, 2);
  const turn = (over: Partial<CatTowerView> = {}) =>
    game({ phase: [0, 0], scores: [0, 0], laid: [null, null], handCounts: [8, 10], hands: { 0: HAND }, pendingSkip: [false, false], forfeited: [false, false], dealer: 1, turn: 0, step: "play", ...over });
  const acts = (sent: { t: string; action?: { type: string } }[]) => sent.flatMap((m) => (m.t === "act" && m.action ? [m.action] : []));
  const confirm = (page: Page) => page.getByRole("dialog", { name: "Lay down first?" });

  async function seated(page: Page, over: Partial<RoomView> = {}) {
    const server = await standInServer(page);
    server.send({ t: "snapshot", protocol: 1, seq: 1, room: { ...room(turn()), seats: two, ...over } });
    await page.goto("/play/t/BCDFG");
    await expect(page.locator(".card.mine .card-inner")).toHaveCount(8);
    return server;
  }
  /** Picks a card by key, and waits for the table to have taken it (its keys read the pick next). */
  async function pick(page: Page, id: number) {
    const c = page.locator(`.card.mine .card-inner[aria-label="${label(id)}"]`);
    await c.press("Enter");
    await expect(c).toHaveAttribute("aria-pressed", "true");
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  }

  /** Puts `ids` in tray `i` on the full table: pick a card, then its tray's key. */
  async function stage(page: Page, i: number, ids: number[]) {
    for (const id of ids) {
      await pick(page, id);
      await page.keyboard.press(String(i + 1));
      await expect(page.locator(`.tray`).nth(i)).toHaveAttribute("aria-label", new RegExp(`, ${ids.indexOf(id) + 1} of 3`));
    }
  }

  test.beforeEach(() => {
    const name = test.info().project.name;
    test.skip(name !== "android-chrome" && name !== "laptop-chrome", "one phone and the laptop");
  });

  test("with the level in the trays, a discard asks; Esc goes back, Discard anyway discards", async ({ page }, info) => {
    const { sent } = await seated(page);
    await stage(page, 0, [1, 25, 49]);
    await stage(page, 1, [4, 28, 52]);
    await expect(page.locator("#lay")).toHaveText("Lay down");
    await expect(page.locator("#lay")).toHaveAccessibleName("Lay down");
    if (SHOTS) await page.screenshot({ path: `${SHOTS}/lay-down-button-${info.project.name}.png` });

    // By tap: the 10, then the pile.
    await pick(page, 9);
    await page.locator("#discard").click();
    await expect(confirm(page)).toBeVisible();
    await expect(confirm(page).getByRole("button", { name: "Lay down" })).toBeFocused();
    if (SHOTS) {
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${SHOTS}/lay-down-first-${info.project.name}.png` });
    }
    await page.keyboard.press("Escape");
    await expect(confirm(page)).toBeHidden();

    // Back to the turn, the 10 still picked. By key: X asks too.
    await expect(page.locator(`.card.mine .card-inner[aria-label="${label(9)}"]`)).toHaveAttribute("aria-pressed", "true");
    await page.keyboard.press("x");
    await expect(confirm(page)).toBeVisible();
    await confirm(page).getByRole("button", { name: "Discard anyway" }).click();
    await expect(confirm(page)).toBeHidden();
    await expect.poll(() => acts(sent)).toEqual([{ type: "discard", card: 9 }]);
  });

  test("Lay down lays the level down by Enter, and a drag on the pile asks too", async ({ page }) => {
    const { sent } = await seated(page);
    await stage(page, 0, [1, 25, 49]);
    await stage(page, 1, [4, 28, 52]);

    // Dragged onto the pile: asked. Enter takes Lay down.
    const card = (await page.locator(`.card.mine .card-inner[aria-label="${label(11)}"]`).boundingBox())!;
    const pile = (await page.locator("#discard").boundingBox())!;
    await page.mouse.move(card.x + card.width / 2, card.y + card.height / 2);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) await page.mouse.move(card.x + card.width / 2 + ((pile.x + pile.width / 2 - card.x - card.width / 2) * i) / 10, card.y + card.height / 2 + ((pile.y + pile.height / 2 - card.y - card.height / 2) * i) / 10);
    await page.mouse.up();
    await expect(confirm(page)).toBeVisible();
    await expect(confirm(page).getByRole("button", { name: "Lay down" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(confirm(page)).toBeHidden();
    await expect.poll(() => acts(sent).map((a) => a.type)).toEqual(["layDown"]);
  });

  test("nothing in the trays: a discard goes without asking", async ({ page }) => {
    const { sent } = await seated(page);
    await pick(page, 9);
    await page.locator("#discard").click();
    await expect.poll(() => acts(sent)).toEqual([{ type: "discard", card: 9 }]);
    await expect(confirm(page)).toHaveCount(0);
  });

  test("trays that don't make the level yet keep their cards, and a discard goes without asking", async ({ page }) => {
    const { sent } = await seated(page);
    await stage(page, 0, [1, 25]);
    await pick(page, 9);
    await page.locator("#discard").click();
    await expect.poll(() => acts(sent)).toEqual([{ type: "discard", card: 9 }]);
    await expect(confirm(page)).toHaveCount(0);
  });

  test("on Cards at a TV table: the Discard button asks, and Lay down lays down", async ({ page }, info) => {
    test.skip(info.project.name !== "android-chrome", "a phone at a TV table");
    const { sent } = await seated(page, { screen: true });
    await expect(page.locator(".ctl")).toBeVisible();
    // Into the trays by tap: a card, then a part of its tray no card covers.
    const tapTray = async (i: number) => {
      const at = await page.locator(".ctl .tray").nth(i).evaluate((tray) => {
        const r = tray.getBoundingClientRect();
        for (let y = r.bottom - 4; y > r.top; y -= 6)
          for (let x = r.right - 4; x > r.left; x -= 6) {
            const hit = document.elementFromPoint(x, y);
            if (hit && tray.contains(hit)) return { x, y };
          }
        return null;
      });
      await page.mouse.click(at!.x, at!.y);
    };
    for (const [i, ids] of [[0, [1, 25, 49]], [1, [4, 28, 52]]] as const) {
      for (const [k, id] of ids.entries()) {
        await page.waitForTimeout(350);
        await pick(page, id);
        await tapTray(i);
        await expect(page.locator(".ctl .tray").nth(i)).toHaveAttribute("aria-label", new RegExp(`, ${k + 1} of 3`));
      }
    }
    await expect(page.locator("#lay")).toHaveText("Lay down");
    await pick(page, 9);
    await page.locator("#discard-btn").click();
    await expect(confirm(page)).toBeVisible();
    if (SHOTS) {
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${SHOTS}/lay-down-first-cards-${info.project.name}.png` });
    }
    await confirm(page).getByRole("button", { name: "Lay down" }).click();
    await expect.poll(() => acts(sent).map((a) => a.type)).toEqual(["layDown"]);
  });
});

/** The Lay down button says so, and fits: the smallest phone, the largest text, a TV table's phone. */
test.describe("the Lay down button", () => {
  const HAND = [1, 25, 49, 4, 28, 52, 9, 11];
  const label = (id: number) => `${(id % 12) + 1}, ${["tabby", "tuxedo", "calico", "gray"][Math.floor(id / 24)]}`;
  const sizes = [
    { name: "se", viewport: { width: 375, height: 667 }, text: 16 },
    { name: "se-largest-text", viewport: { width: 375, height: 667 }, text: 26 },
  ];
  test.beforeEach(() => {
    test.skip(test.info().project.name !== "android-chrome", "phone sizes, set here");
  });
  for (const size of sizes) {
    for (const tv of [false, true]) {
      test(`${size.name}${tv ? " on Cards" : ""}: it reads "Lay down" and fits`, async ({ page }) => {
        await page.setViewportSize(size.viewport);
        await page.addInitScript((px) => addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = `${px}px`)), size.text);
        const server = await standInServer(page);
        const g = game({ phase: [0, 0], scores: [0, 0], laid: [null, null], handCounts: [8, 10], hands: { 0: HAND }, pendingSkip: [false, false], forfeited: [false, false], dealer: 1, turn: 0, step: "play" });
        server.send({ t: "snapshot", protocol: 1, seq: 1, room: { ...room(g), seats: seats.slice(0, 2), ...(tv ? { screen: true } : {}) } });
        await page.goto("/play/t/BCDFG");
        await expect(page.locator(".card.mine .card-inner")).toHaveCount(8);
        const trays = page.locator(tv ? ".ctl .tray" : ".tray");
        for (const [i, ids] of [[0, [1, 25, 49]], [1, [4, 28, 52]]] as const) {
          for (const [k, id] of ids.entries()) {
            await page.waitForTimeout(350);
            const c = page.locator(`.card.mine .card-inner[aria-label="${label(id)}"]`);
            await c.press("Enter");
            await expect(c).toHaveAttribute("aria-pressed", "true");
            await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
            if (tv) {
              const at = await trays.nth(i).evaluate((tray) => {
                const r = tray.getBoundingClientRect();
                for (let y = r.bottom - 4; y > r.top; y -= 6)
                  for (let x = r.right - 4; x > r.left; x -= 6) {
                    const hit = document.elementFromPoint(x, y);
                    if (hit && tray.contains(hit)) return { x, y };
                  }
                return null;
              });
              await page.mouse.click(at!.x, at!.y);
            } else await page.keyboard.press(String(i + 1));
            await expect(trays.nth(i)).toHaveAttribute("aria-label", new RegExp(`, ${k + 1} of 3`));
          }
        }
        const lay = page.locator("#lay");
        await expect(lay).toHaveText("Lay down");
        await expect(lay).toHaveAccessibleName("Lay down");
        await expect(lay).toBeInViewport({ ratio: 1 });
        // One line, nothing cut: the words fit the button.
        expect(await lay.evaluate((b) => b.scrollWidth <= b.clientWidth + 1 && b.getBoundingClientRect().height < 80)).toBe(true);
        await page.waitForTimeout(400);
        if (SHOTS) await page.screenshot({ path: `${SHOTS}/lay-down-button-${size.name}${tv ? "-cards" : ""}.png` });
      });
    }
  }
});
