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
