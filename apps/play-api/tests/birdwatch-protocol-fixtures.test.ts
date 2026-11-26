import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { BIRD, type CardId } from "../src/birdwatch/cards";
import { actor, playable, type BirdAction, type BirdState } from "../src/birdwatch/engine";
import { birdwatch } from "../src/games/birdwatch";
import { parseClientMessage } from "../src/protocol";
import { RoomCore } from "../src/room/core";
import { createRng } from "../src/rules/rng";

import { bell, fish, mouse } from "./birdwatch-helpers";

import type { BirdView } from "../src/birdwatch/view";
import type { ClientMessage, Person, ServerMessage } from "../src/protocol";

/**
 * Birdwatch's wire samples, for the Swift client (PounceKit) and the web player the way the tile
 * game's are: they decode every server sample and encode every client sample, by `name`. Made
 * from real rooms. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/birdwatch-protocol-fixtures.test.ts`.
 */
type Sample<M> = { name: string; message: M };
type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Room = RoomCore<BirdState>;

const write = process.env.UPDATE_FIXTURES === "1";
const ON = ["cat-tower", "tiles", "birdwatch"] as const;

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const NAMES = ["Alice", "Bob", "Cleo", "Dev", "Eli", "Fay"];
const people: Person[] = NAMES.map((name, i) => ({ id: `${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}-1111-4111-8111-111111111111`, name, cat: i }));
const device = (seat: number) => `dev${"ABCDEF"[seat]}`;
const game = (r: Room) => r.state.gameState as BirdState;

/** A table of `seats` people, each on their own device, under `rules`. Not yet started unless `start`. */
function table(seats: number, rules: "official" | "tucker" | "friesen" = "official", start = true): Room {
  const state = RoomCore.create<BirdState>("BCDFG", "devA", 1_000, "Window Seat", undefined, "birdwatch");
  const r = new RoomCore<BirdState>(state, () => 1_000, createRng([1, 2, 3, 4]), undefined, 1, { streaks: false, games: ON });
  for (let seat = 0; seat < seats; seat++) {
    // A new lobby opens four seats: the host opens the rest.
    if (r.state.seats[seat]?.kind === "closed") r.handle("devA", { t: "configure", seat, kind: "open" });
    r.connect(device(seat));
    r.handle(device(seat), { t: "claim", seat, person: people[seat] as Person });
  }
  for (let seat = seats; seat < 6; seat++) r.handle("devA", { t: "configure", seat, kind: "closed" });
  if (rules !== "official") r.handle("devA", { t: "setOptions", options: { rules } });
  if (start) r.handle("devA", { t: "start" });
  return r;
}

/** The seat to act's action through the room. A sample built on a refused move would be a lie, so it throws. */
function act(r: Room, action: BirdAction | ((s: BirdState, seat: number) => BirdAction)): void {
  const s = game(r);
  const seat = actor(s) as number;
  const a = typeof action === "function" ? action(s, seat) : action;
  const out = r.handle(device(seat), { t: "act", seat, action: a });
  const refused = out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
  if (refused.length > 0) throw new Error(`${JSON.stringify(a)} refused: ${refused.join()}`);
}

/** Bidding: the first seat bids 70, everyone else passes, so it wins the bid. */
function bidOut(r: Room): number {
  const first = actor(game(r)) as number;
  act(r, { type: "bid", amount: 70 });
  while (game(r).phase === "bidding") act(r, { type: "pass" });
  return first;
}

const nest = (s: BirdState): BirdAction => ({ type: "nest", discard: [...s.fromNest] });
const first = (s: BirdState, seat: number): BirdAction => ({ type: "play", card: playable(s, seat)[0] as CardId });
const viewIn = (snap: Snapshot) => snap.room.birdwatch as BirdView;

function snapshots() {
  const lobby = table(4, "tucker", false).snapshotFor("devB");

  // Four players, official rules.
  const four = table(4);
  const bidding = four.snapshotFor(device(actor(game(four)) as number));
  const watching = four.snapshotFor(device(((actor(game(four)) as number) + 1) % 4));
  act(four, { type: "bid", amount: 75 });
  const bid = four.snapshotFor("devA");
  while (game(four).phase === "bidding") act(four, { type: "pass" });
  const bidder = actor(game(four)) as number;
  const nestTaken = four.snapshotFor(device(bidder));
  const nestWaiting = four.snapshotFor(device((bidder + 1) % 4));
  act(four, nest);
  const naming = four.snapshotFor(device(bidder));
  act(four, { type: "trump", suit: "bell" });
  const leading = four.snapshotFor(device(bidder));
  act(four, first);
  const following = four.snapshotFor(device(actor(game(four)) as number));
  const otherInPlay = four.snapshotFor(device(bidder));
  while (game(four).trick.length > 0) act(four, first);
  const afterTrick = four.snapshotFor("devC");
  while (game(four).phase === "play") act(four, first);
  const between = four.snapshotFor("devD");

  // The next hand starts the room's way: from `between`, after the pause (applied for seat 0).
  const over = table(4);
  bidOut(over);
  act(over, nest);
  act(over, { type: "trump", suit: "fish" });
  over.state.gameState = { ...game(over), scores: [290, 280] };
  while (game(over).phase === "play") act(over, first);
  const ended = over.snapshotFor("devB");

  // Five players, tucker: the partner call, before and after the card is played.
  const five = table(5, "tucker");
  const winner = bidOut(five);
  act(five, nest);
  act(five, { type: "trump", suit: "mouse" });
  const calling = five.snapshotFor(device(winner));
  const holder = (winner + 2) % 5;
  const called = (game(five).hands[holder] as CardId[]).find((c) => c !== BIRD) as CardId;
  act(five, { type: "partner", card: called });
  const partnerSecret = five.snapshotFor(device(holder));
  const partnerUnknown = five.snapshotFor(device((winner + 1) % 5));
  // Lead the called card's suit until the holder has played it.
  while (game(five).partner === null) {
    act(five, (s, seat) => (seat === holder ? { type: "play", card: playable(s, seat).includes(called) ? called : (playable(s, seat)[0] as CardId) } : first(s, seat)));
  }
  const partnerShown = five.snapshotFor(device((winner + 1) % 5));

  // Six players, friesen, and a person who leaves: a House Cat takes their seat.
  const six = table(6, "friesen");
  six.handle("devC", { t: "act", seat: 2, action: { type: "forfeit" } });
  const tookOver = six.snapshotFor("devA");

  // Everyone leaves: the game ends.
  const empty = table(4);
  for (let seat = 0; seat < 4; seat++) empty.handle(device(seat), { t: "act", seat, action: { type: "forfeit" } });
  const left = empty.snapshotFor("devA");

  return {
    lobby, bidding, watching, bid, nestTaken, nestWaiting, naming, leading, following, otherInPlay, afterTrick, between, ended,
    calling, partnerSecret, partnerUnknown, partnerShown, tookOver, left,
  };
}

function serverSamples(): Sample<ServerMessage>[] {
  const s = snapshots();
  const event = (seq: number, e: Extract<ServerMessage, { t: "event" }>["event"]): ServerMessage => ({ t: "event", seq, event: e });
  const bird = (seq: number, e: Parameters<typeof birdwatch.filterEvent>[0]): ServerMessage => event(seq, { kind: "birdwatch", event: e });
  const trick = [
    { seat: 1, card: mouse(10) },
    { seat: 2, card: mouse(14) },
    { seat: 3, card: fish(5) },
    { seat: 0, card: mouse(6) },
  ];
  const result = { hand: 3, bidder: 1, bid: 85, partner: null, trump: "fish" as const, made: true, taken: [30, 90], change: [30, 90], totals: [145, 210] };
  return [
    { name: "snapshot-lobby", message: s.lobby },
    { name: "snapshot-bidding-your-move", message: s.bidding },
    { name: "snapshot-bidding-watching", message: s.watching },
    { name: "snapshot-bidding-after-bid", message: s.bid },
    { name: "snapshot-nest-bid-winner", message: s.nestTaken },
    { name: "snapshot-nest-waiting", message: s.nestWaiting },
    { name: "snapshot-trump-bid-winner", message: s.naming },
    { name: "snapshot-play-lead", message: s.leading },
    { name: "snapshot-play-follow", message: s.following },
    { name: "snapshot-play-watching", message: s.otherInPlay },
    { name: "snapshot-play-after-trick", message: s.afterTrick },
    { name: "snapshot-between", message: s.between },
    { name: "snapshot-over-target", message: s.ended },
    { name: "snapshot-five-partner-call", message: s.calling },
    { name: "snapshot-five-you-are-partner", message: s.partnerSecret },
    { name: "snapshot-five-partner-hidden", message: s.partnerUnknown },
    { name: "snapshot-five-partner-shown", message: s.partnerShown },
    { name: "snapshot-six-house-cat", message: s.tookOver },
    { name: "snapshot-over-left", message: s.left },
    { name: "event-dealt-own", message: bird(4, { kind: "dealt", hand: 2, dealer: 1, handCounts: [9, 9, 9, 9], hands: { 0: [4, 6, 9, 17, 18, 30, 33, 41, 56] } }) },
    { name: "event-dealt-screen", message: bird(4, { kind: "dealt", hand: 2, dealer: 1, handCounts: [9, 9, 9, 9], hands: {} }) },
    { name: "event-bid", message: bird(5, { kind: "bid", seat: 2, amount: 85 }) },
    { name: "event-passed", message: bird(6, { kind: "passed", seat: 3 }) },
    { name: "event-bidWon", message: bird(7, { kind: "bidWon", seat: 2, amount: 85 }) },
    { name: "event-nest-own", message: bird(8, { kind: "nest", seat: 2, cards: [7, 21, 44, 50, 55] }) },
    { name: "event-nest-other", message: bird(8, { kind: "nest", seat: 2 }) },
    { name: "event-putBack-own", message: bird(9, { kind: "putBack", seat: 2, count: 5, cards: [5, 7, 19, 32, 46] }) },
    { name: "event-putBack-other", message: bird(9, { kind: "putBack", seat: 2, count: 5 }) },
    { name: "event-trump", message: bird(10, { kind: "trump", seat: 2, suit: "feather" }) },
    { name: "event-called", message: bird(11, { kind: "called", seat: 2, card: bell(1) }) },
    { name: "event-turn", message: bird(12, { kind: "turn", seat: 2 }) },
    { name: "event-played", message: bird(13, { kind: "played", seat: 2, card: BIRD }) },
    { name: "event-partner", message: bird(14, { kind: "partner", seat: 4 }) },
    { name: "event-trick", message: bird(15, { kind: "trick", winner: 3, cards: trick, points: 25 }) },
    { name: "event-handOver", message: bird(16, { kind: "handOver", result, putBack: [5, 7, 19, 32, 46] }) },
    { name: "event-gameOver-target", message: bird(17, { kind: "gameOver", winners: [1, 3], scores: [145, 310], reason: "target" }) },
    { name: "event-gameOver-left", message: bird(18, { kind: "gameOver", winners: [], scores: [40, 75], reason: "left" }) },
    { name: "event-houseCat", message: event(19, { kind: "houseCat", seat: 2 }) },
    ...(
      [
        "wrong_phase",
        "bid_too_low",
        "bid_too_high",
        "bad_bid",
        "bad_card",
        "not_your_card",
        "wrong_count",
        "duplicate_card",
        "own_card",
        "must_follow",
        "not_your_turn",
        "bad_action",
        "game_over",
        "not_allowed",
        "not_enough_players",
        "game_off",
      ] as const
    ).map((code): Sample<ServerMessage> => ({ name: `error-${code}`, message: { t: "error", code } })),
  ];
}

const clientSamples: Sample<ClientMessage>[] = [
  { name: "setOptions", message: { t: "setOptions", options: { rules: "tucker" } } },
  { name: "swapSeats", message: { t: "swapSeats", seats: [1, 2] } },
  { name: "act-bid", message: { t: "act", seat: 1, action: { type: "bid", amount: 85 } } },
  { name: "act-pass", message: { t: "act", seat: 1, action: { type: "pass" } } },
  { name: "act-nest", message: { t: "act", seat: 1, action: { type: "nest", discard: [5, 7, 19, 32, 46] } } },
  { name: "act-trump", message: { t: "act", seat: 1, action: { type: "trump", suit: "bell" } } },
  { name: "act-partner", message: { t: "act", seat: 1, action: { type: "partner", card: 56 } } },
  { name: "act-play", message: { t: "act", seat: 1, action: { type: "play", card: 13 }, id: "0f8fad5b-d9cb-469f-a165-70867728950e" } },
  { name: "act-forfeit", message: { t: "act", seat: 1, action: { type: "forfeit" } } },
];

test("Birdwatch's server samples match the committed file, and are real", () => {
  const samples = serverSamples();
  check("birdwatch-server-messages.json", samples);
  const snaps = samples.flatMap((s) => (s.message.t === "snapshot" ? [{ name: s.name, snap: s.message }] : []));
  for (const { name, snap } of snaps) {
    const { room } = snap;
    expect(room.gameId, name).toBe("birdwatch");
    expect(room.game, name).toBeNull();
    expect(room.options, name).toBeDefined();
    if (!room.birdwatch) continue;
    // One device, one person: never more than its own hand.
    expect(Object.keys(room.birdwatch.hands).length, name).toBeLessThanOrEqual(1);
    expect(JSON.stringify(room.birdwatch), name).not.toMatch(/"(holder|seed|rngCalls|nest)":/);
  }
  const by = (name: string) => viewIn(snaps.find((s) => s.name === name)?.snap as Snapshot);
  expect(by("snapshot-bidding-your-move").bidRange).toEqual({ min: 70, max: 120, step: 5 });
  expect(by("snapshot-bidding-watching").bidRange).toBeUndefined();
  expect(by("snapshot-nest-bid-winner").fromNest).toHaveLength(5);
  expect(by("snapshot-nest-waiting").fromNest).toBeUndefined();
  expect(by("snapshot-play-follow").playable?.length).toBeGreaterThan(0);
  expect(by("snapshot-play-watching").playable).toBeUndefined();
  expect(by("snapshot-between").putBack).toHaveLength(5);
  expect(by("snapshot-over-target")).toMatchObject({ status: "over", endReason: "target" });
  expect(by("snapshot-five-partner-call").partnerChoices?.length).toBe(57 - 10);
  expect(by("snapshot-five-you-are-partner")).toMatchObject({ partner: null });
  expect(by("snapshot-five-you-are-partner").youArePartner).toBeDefined();
  expect(by("snapshot-five-partner-hidden").youArePartner).toBeUndefined();
  expect(by("snapshot-five-partner-hidden").partner).toBeNull();
  expect(by("snapshot-five-partner-shown").partner).not.toBeNull();
  expect(by("snapshot-over-left")).toMatchObject({ status: "over", endReason: "left", winners: [] });
  const sixSeats = (snaps.find((s) => s.name === "snapshot-six-house-cat")?.snap as Snapshot).room.seats;
  expect(sixSeats[2]).toMatchObject({ kind: "bot", left: true, person: { name: "Cleo" } });
});

test("Birdwatch's client samples match the committed file, and the room's parser takes each as it is", () => {
  check("birdwatch-client-messages.json", clientSamples);
  for (const { name, message } of clientSamples) {
    const parsed = parseClientMessage(JSON.stringify(message), birdwatch.parseAction, birdwatch.parseAim, birdwatch.parseOptions);
    expect(parsed, name).toEqual(message);
  }
});
