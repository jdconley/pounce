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
