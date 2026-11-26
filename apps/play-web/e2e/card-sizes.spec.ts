import { expect, test, type Page } from "@playwright/test";
import { newGame } from "@pounce/play-api/birdwatch/engine";
import { viewFor } from "@pounce/play-api/birdwatch/view";

import { firstRun, ownAddress, standInServer } from "./helpers";

import type { RoomView } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";
import type { TilesView } from "@pounce/play-api/tiles/view";

/**
 * On Cards (a phone whose table is on a TV), the hand is big, and it is never smaller first, not
 * for a frame: not as the view is drawn, not on the Cards/Table switch, not as a Tuna Tiles turn
 * hands the phone back its rack. Every frame, each hand card's drawn scale is sampled.
 */
const ME = "11111111-1111-4111-8111-111111111111";
const ada: RoomView["seats"][number] = { kind: "human", person: { id: ME, name: "Ada", cat: 1 }, yours: true, presence: "awake" };
const bot: RoomView["seats"][number] = { kind: "bot", yours: false, presence: null };

/** Hand cards on Cards: Cat Tower's controller, Tuna Tiles' rack, Birdwatch's Cards view. */
const HAND = ".ctl .card.mine, .tcl .tile.mine, .bw-table.cards-view .bw-hand-card";

/** Samples, every frame, the smallest scale any hand card on Cards is drawn at. */
const SAMPLER = (selector: string) => {
  const w = window as unknown as { __least: number; __frames: number };
  w.__least = Infinity;
  w.__frames = 0;
  const tick = () => {
    for (const el of document.querySelectorAll<HTMLElement>(selector)) {
      const m = new DOMMatrix(getComputedStyle(el).transform);
      w.__least = Math.min(w.__least, Math.hypot(m.a, m.b));
    }
    w.__frames += 1;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};

async function sampling(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as { __least: number; __frames: number };
    w.__least = Infinity;
    w.__frames = 0;
  });
}

/** The smallest scale seen since `sampling`, after at least 30 frames (the animations' length). */
async function least(page: Page): Promise<number> {
  await expect.poll(() => page.evaluate(() => (window as unknown as { __frames: number }).__frames)).toBeGreaterThan(30);
  return page.evaluate(() => (window as unknown as { __least: number }).__least);
}

const view = (page: Page, name: "Cards" | "Table") => page.locator("#view-switch").getByRole("button", { name, exact: true });

test.beforeEach(async ({ page, context }, info) => {
  test.skip(info.project.name !== "android-chrome" && info.project.name !== "iphone-safari", "phones at a TV table");
  await ownAddress(context);
  await page.addInitScript(SAMPLER, HAND);
  await page.goto("/play/");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
});

test("Cat Tower on Cards: the hand is never drawn small first, as it shows or on the switch", async ({ page }) => {
  const { send } = await standInServer(page);
  const game: CatTowerView = {
    round: 1, dealer: 0, turn: 1, step: "draw", status: "playing", deckCount: 40, discardTop: 0, discardCount: 1, phase: [0, 0], scores: [0, 0],
    laid: [null, null], handCounts: [10, 10], hands: { 0: [2, 13, 30, 47, 58, 71, 82, 3, 16, 41] }, pendingSkip: [false, false], winners: [], forfeited: [false, false],
  };
  send({ t: "snapshot", protocol: 1, seq: 1, room: { code: "BCDFG", name: "Sizes", status: "playing", youAreHost: true, seats: [ada, bot], game, screen: true } });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".ctl .card.mine")).toHaveCount(10);
  expect(await least(page)).toBeGreaterThan(0.97);

  await view(page, "Table").click();
  await expect(page.locator(".ctl")).toHaveCount(0);
  await sampling(page);
  await view(page, "Cards").click();
  await expect(page.locator(".ctl .card.mine")).toHaveCount(10);
  expect(await least(page)).toBeGreaterThan(0.97);
});

test("Tuna Tiles on Cards: the rack is never drawn small first when a turn hands it back", async ({ page }) => {
  const { send } = await standInServer(page);
  const tiles: TilesView = {
    status: "playing", turn: 1, turns: 3, table: [], poolCount: 60, rackCounts: [6, 14], racks: { 0: [0, 1, 2, 30, 31, 32] },
    opened: [false, false], passed: [false, false], winners: [], scores: [0, 0], forfeited: [false, false],
  };
  const room = (t: TilesView): RoomView => ({ code: "BCDFG", name: "Sizes", status: "playing", youAreHost: true, seats: [ada, bot], gameId: "tiles", game: null, tiles: t, screen: true });
  send({ t: "snapshot", protocol: 1, seq: 1, room: room(tiles) });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".tcl .tile.mine")).toHaveCount(6);
  expect(await least(page)).toBeGreaterThan(0.97);

  // Our turn: the full table. Then the House Cat's: the rack on Cards again.
  send({ t: "event", seq: 2, event: { kind: "tiles", event: { kind: "turn", seat: 0 } } });
  send({ t: "snapshot", protocol: 1, seq: 2, room: room({ ...tiles, turn: 0, turns: 4 }) });
  await expect(page.locator(".tcl")).toHaveCount(0);
  await sampling(page);
  send({ t: "event", seq: 3, event: { kind: "tiles", event: { kind: "turn", seat: 1 } } });
  send({ t: "snapshot", protocol: 1, seq: 3, room: room({ ...tiles, turn: 1, turns: 5 }) });
  await expect(page.locator(".tcl .tile.mine")).toHaveCount(6);
  expect(await least(page)).toBeGreaterThan(0.97);
});

test("Birdwatch on Cards: the hand is never drawn small first, as it shows or on the switch", async ({ page }) => {
  const { send } = await standInServer(page);
  const state = newGame(4, [1, 2, 3, 4]);
  const room: RoomView = { code: "BCDFG", name: "Sizes", status: "playing", youAreHost: true, seats: [ada, bot, bot, bot], gameId: "birdwatch", game: null, birdwatch: viewFor(state, [0]), screen: true };
  send({ t: "snapshot", protocol: 1, seq: 1, room });
  await page.goto("/play/t/BCDFG");
  const hand = page.locator(".bw-table.cards-view .bw-hand-card");
  await expect(hand.first()).toBeVisible();
  expect(await least(page)).toBeGreaterThan(0.97);

  await view(page, "Table").click();
  await expect(page.locator(".bw-table.cards-view")).toHaveCount(0);
  await page.waitForTimeout(500);
  await sampling(page);
  await view(page, "Cards").click();
  await expect(hand.first()).toBeVisible();
  expect(await least(page)).toBeGreaterThan(0.97);
});
