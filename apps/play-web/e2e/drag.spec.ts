import { expect, test, type Page } from "@playwright/test";

import { firstRun, ownAddress, standInServer } from "./helpers";

import type { ClientMessage, RoomView } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";
import type { TilesView } from "@pounce/play-api/tiles/view";

/**
 * A drag lasts longer than the moment it started in: whatever changes while a card or a piece is
 * held (our draw is answered, our turn comes) counts when it is dropped. The table is handed the
 * room by a stand-in for the server's socket, so each change lands mid-drag, every time.
 */
const ME = "11111111-1111-4111-8111-111111111111";
const seats: RoomView["seats"] = [
  { kind: "human", person: { id: ME, name: "Ada", cat: 1 }, yours: true, presence: "awake" },
  { kind: "bot", yours: false, presence: null },
];

const center = async (page: Page, selector: string) => {
  const b = (await page.locator(selector).first().boundingBox())!;
  return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
};

type Point = { x: number; y: number };

/** Moves the mouse from `a` to `b` in steps, as a hand does. */
async function glide(page: Page, a: Point, b: Point) {
  for (let i = 1; i <= 10; i++) await page.mouse.move(a.x + ((b.x - a.x) * i) / 10, a.y + ((b.y - a.y) * i) / 10);
}

/** Presses at `from` and carries it halfway to `to`: the drag is under way. Returns where it is. */
async function lift(page: Page, from: Point, to: Point): Promise<Point> {
  const mid = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 };
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await glide(page, from, mid);
  return mid;
}

async function drop(page: Page, at: Point, to: Point) {
  await glide(page, at, to);
  await page.mouse.up();
}

const acts = (sent: ClientMessage[]) => sent.flatMap((m) => (m.t === "act" ? [m] : []));

test.beforeEach(async ({ page, context }, info) => {
  test.skip(info.project.name !== "laptop-chrome" && info.project.name !== "android-chrome", "Chrome, mouse and touch-sized");
  await ownAddress(context);
  await page.goto("/play/");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
});

test("a card picked up before our draw is answered still discards", async ({ page }) => {
  const { send, sent } = await standInServer(page);
  const game: CatTowerView = {
    round: 1,
    dealer: 1,
    turn: 0,
    step: "draw",
    status: "playing",
    deckCount: 40,
    discardTop: 1,
    discardCount: 1,
    phase: [0, 0],
    scores: [0, 0],
    laid: [null, null],
    handCounts: [10, 10],
    hands: { 0: [2, 13, 30, 47, 58, 71, 82, 3, 16, 41] },
    pendingSkip: [false, false],
    winners: [],
    forfeited: [false, false],
  };
  const room = (g: CatTowerView, acks: string[]): RoomView => ({ code: "BCDFG", name: "Drag", status: "playing", youAreHost: true, seats, game: g, link: { ping: 3000, acks } });
  send({ t: "snapshot", protocol: 1, seq: 1, room: room(game, []) });
  await page.goto("/play/t/BCDFG");
  const cards = page.locator(".card.mine .card-inner");
  await expect(cards).toHaveCount(10);

  // Draw: the card arrives, and the server's answer (the snapshot that acknowledges it) waits.
  await page.locator("#deck").click();
  await expect.poll(() => acts(sent).length).toBe(1);
  const draw = acts(sent)[0]!;
  send({ t: "event", seq: 2, event: { kind: "game", event: { kind: "drew", seat: 0, from: "deck", card: 60 } } });
  await expect(cards).toHaveCount(11);

  // Pick a card up while the draw is still in flight.
  const pile = await center(page, "#discard");
  const held = await lift(page, await center(page, ".card.mine .card-inner"), pile);
  await expect(page.locator(".card.mine.dragging")).toHaveCount(1);

  // The answer lands mid-drag (its deck count shows it has), then the card goes on the pile.
  const hand = [...game.hands[0]!, 60];
  send({ t: "snapshot", protocol: 1, seq: 2, room: room({ ...game, step: "play", deckCount: 38, handCounts: [11, 10], hands: { 0: hand } }, [draw.id!]) });
  await expect(page.locator("#deck")).toHaveAttribute("aria-label", /^Deck, 38 cards/);
  await drop(page, held, pile);

  await expect.poll(() => acts(sent).map((m) => m.action.type)).toEqual(["draw", "discard"]);
});

test("a piece picked up before our turn comes is placed when it does", async ({ page }) => {
  const { send, sent } = await standInServer(page);
  const tiles: TilesView = {
    status: "playing",
    turn: 1,
    turns: 3,
    table: [],
    poolCount: 60,
    rackCounts: [6, 14],
    racks: { 0: [0, 1, 2, 30, 31, 32] },
    opened: [false, false],
    passed: [false, false],
    winners: [],
    scores: [0, 0],
    forfeited: [false, false],
  };
  const room = (t: TilesView): RoomView => ({ code: "BCDFG", name: "Drag", status: "playing", youAreHost: true, seats, gameId: "tiles", game: null, tiles: t, link: { ping: 3000, acks: [] } });
  send({ t: "snapshot", protocol: 1, seq: 1, room: room(tiles) });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".tile.mine .tile-inner")).toHaveCount(6);
  const board = await center(page, ".board");

  // Pick a piece up on the House Cat's turn: it can only be moved along the rack, for now.
  const held = await lift(page, await center(page, ".tile.mine .tile-inner"), board);
  await expect(page.locator(".tile.mine.dragging")).toHaveCount(1);

  // Our turn comes mid-drag; the piece is dropped on the table.
  send({ t: "event", seq: 2, event: { kind: "tiles", event: { kind: "turn", seat: 0 } } });
  send({ t: "snapshot", protocol: 1, seq: 2, room: room({ ...tiles, turn: 0, turns: 4 }) });
  await expect(page.locator(".tt-table.my-turn")).toBeVisible();
  await drop(page, held, await center(page, "#new-set"));

  await expect(page.locator(".set-zone")).toHaveCount(1);
  expect(acts(sent)).toEqual([]);
});

/**
 * Hits forgive the hand. The card the player sees is the one that counts: a group lit as a fit
 * takes the card on release, wherever the finger is over it, and a card that fits one place only
 * goes there from anywhere on the table.
 */
test.describe("hits forgive the hand", () => {
  const label = (id: number) => `${(id % 12) + 1}, ${["tabby", "tuxedo", "calico", "gray"][Math.floor(id / 24)]}`;
  const myCard = (page: Page, id: number) => page.locator(`.card.mine .card-inner[aria-label="${label(id)}"]`);
  // Ada (seat 0) has laid 2s and 5s; the House Cat has laid 9s and a run from 3 to 6.
  const laid: CatTowerView["laid"] = [
    [
      { kind: "set", cards: [1, 13, 25], value: 2 },
      { kind: "set", cards: [4, 16, 28], value: 5 },
    ],
    [
      { kind: "set", cards: [8, 20, 32], value: 9 },
      { kind: "run", cards: [2, 3, 4, 5], start: 3, end: 6 },
    ],
  ];
  // 40 is a 5 (Ada's 5s only), 44 a 9 (the House Cat's 9s only), 30 a 7 (the run's high end only);
  // the 10s and 12s fit nowhere.
  const playing = (hand: number[]): CatTowerView => ({
    round: 1,
    dealer: 1,
    turn: 0,
    step: "play",
    status: "playing",
    deckCount: 40,
    discardTop: 0,
    discardCount: 1,
    phase: [0, 1],
    scores: [0, 0],
    laid,
    handCounts: [hand.length, 4],
    hands: { 0: hand },
    pendingSkip: [false, false],
    winners: [],
    forfeited: [false, false],
  });
  const room = (g: CatTowerView, acks: string[] = []): RoomView => ({ code: "BCDFG", name: "Drag", status: "playing", youAreHost: true, seats, game: g, link: { ping: 3000, acks } });
  const box = async (page: Page, selector: string, i = 0) => (await page.locator(selector).nth(i).boundingBox())!;
  const hits = (sent: ClientMessage[]) => acts(sent).flatMap((m) => (m.action.type === "hit" ? [m.action] : []));

  async function seated(page: Page, hand: number[]) {
    const server = await standInServer(page);
    server.send({ t: "snapshot", protocol: 1, seq: 1, room: room(playing(hand)) });
    await page.goto("/play/t/BCDFG");
    await expect(page.locator(".card.mine .card-inner")).toHaveCount(hand.length);
    await expect(page.locator(".group-zone")).toHaveCount(4);
    return server;
  }

  test("a card held over the group it fits lands there, with the finger off the group's edge", async ({ page }) => {
    const { sent } = await seated(page, [40, 9, 11, 33, 47]);
    const fives = await box(page, ".group-zone", 1);
    const card = (await myCard(page, 40).boundingBox())!;
    const from = { x: card.x + card.width / 2, y: card.y + card.height / 2 };
    // Held by its middle, the card covers the group's top while the finger is above it.
    const at = { x: fives.x + fives.width / 2, y: fives.y - card.height * 0.35 };
    const held = await lift(page, from, at);
    await glide(page, held, at);
    await expect(page.locator(".group-zone").nth(1)).toHaveClass(/\bgood\b/);
    await page.mouse.up();
    await expect.poll(() => hits(sent)).toEqual([{ type: "hit", card: 40, target: { seat: 0, group: 1 } }]);
  });

  test("a card that fits one group goes there from anywhere on the table", async ({ page }) => {
    const { sent } = await seated(page, [44, 9, 11, 33, 47]);
    const card = (await myCard(page, 44).boundingBox())!;
    const from = { x: card.x + card.width / 2, y: card.y + card.height / 2 };
    // Beside the piles, nowhere near the House Cat's 9s.
    const deck = await box(page, "#deck");
    const at = { x: Math.max(deck.x - card.width, 12), y: deck.y + deck.height / 2 };
    const held = await lift(page, from, at);
    await glide(page, held, at);
    await expect(page.locator(".group-zone").nth(2)).toHaveClass(/\bgood\b/);
    await page.mouse.up();
    await expect.poll(() => hits(sent)).toEqual([{ type: "hit", card: 44, target: { seat: 1, group: 0 } }]);
  });

  test("a card that fits one end of a run goes on that end, whichever half it is dropped on", async ({ page }) => {
    const { sent } = await seated(page, [30, 9, 11, 33, 47]);
    const run = await box(page, ".group-zone", 3);
    const card = (await myCard(page, 30).boundingBox())!;
    const from = { x: card.x + card.width / 2, y: card.y + card.height / 2 };
    // On the run's low end, where a 7 doesn't go.
    const at = { x: run.x + run.width * 0.2, y: run.y + run.height / 2 };
    const held = await lift(page, from, at);
    await glide(page, held, at);
    await expect(page.locator(".group-zone").nth(3)).toHaveClass(/\bgood\b/);
    await page.mouse.up();
    await expect.poll(() => hits(sent)).toEqual([{ type: "hit", card: 30, target: { seat: 1, group: 1 }, side: "end" }]);
  });

  test("a card dropped on a lit group while the last hit is in flight lands when it is answered", async ({ page }) => {
    const { send, sent } = await seated(page, [40, 44, 9, 11, 33, 47]);
    // The 5 goes on, and the server's answer waits.
    await myCard(page, 40).click();
    await page.locator(".group-zone").nth(1).click();
    await expect.poll(() => hits(sent).length).toBe(1);
    const first = acts(sent)[0]!;

    // The 9 is dropped on the 9s before that answer comes.
    const nines = await box(page, ".group-zone", 2);
    const card = (await myCard(page, 44).boundingBox())!;
    const at = { x: nines.x + nines.width / 2, y: nines.y + nines.height / 2 };
    const held = await lift(page, { x: card.x + card.width / 2, y: card.y + card.height / 2 }, at);
    await glide(page, held, at);
    await expect(page.locator(".group-zone").nth(2)).toHaveClass(/\bgood\b/);
    await page.mouse.up();
    expect(hits(sent)).toHaveLength(1);

    // The answer lands: the 9 follows.
    const after = playing([44, 9, 11, 33, 47]);
    after.laid = [[laid[0]![0]!, { kind: "set", cards: [4, 16, 28, 40], value: 5 }], laid[1]!];
    send({ t: "event", seq: 2, event: { kind: "game", event: { kind: "hit", seat: 0, card: 40, target: { seat: 0, group: 1 }, group: after.laid[0]![1]! } } });
    send({ t: "snapshot", protocol: 1, seq: 2, room: room(after, [first.id!]) });
    await expect.poll(() => hits(sent).map((h) => h.card)).toEqual([40, 44]);
    expect(hits(sent)[1]).toEqual({ type: "hit", card: 44, target: { seat: 1, group: 0 } });
  });

  test("before our draw a group doesn't light, as it can't take the card yet", async ({ page }) => {
    const server = await standInServer(page);
    server.send({ t: "snapshot", protocol: 1, seq: 1, room: room({ ...playing([40, 9, 11, 33, 47]), step: "draw" }) });
    await page.goto("/play/t/BCDFG");
    await expect(page.locator(".group-zone")).toHaveCount(4);
    const fives = await box(page, ".group-zone", 1);
    const card = (await myCard(page, 40).boundingBox())!;
    const at = { x: fives.x + fives.width / 2, y: fives.y + fives.height / 2 };
    const held = await lift(page, { x: card.x + card.width / 2, y: card.y + card.height / 2 }, at);
    await glide(page, held, at);
    await expect(page.locator(".card.mine.dragging")).toHaveCount(1);
    await expect(page.locator(".group-zone").nth(1)).toHaveClass("group-zone ");
    await page.mouse.up();
    await expect(myCard(page, 40)).toBeVisible();
    expect(hits(server.sent)).toEqual([]);
  });
});
