import { beforeEach, describe, expect, it } from "vitest";

import { actor, plainAction, type BirdAction, type BirdEvent, type BirdState } from "../birdwatch/engine";
import { parseClientMessage } from "../protocol";

import { RETIRE_AFTER_MS, RoomCore, type Outbound, type RoomFeatures } from "./core";

import type { BirdView } from "../birdwatch/view";
import type { Person, RoomEvent, ServerMessage } from "../protocol";
import type { TilesState } from "../tiles/engine";

/* A Birdwatch room: options in the lobby, swapping seats, and a House Cat taking a seat whose person leaves. */

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
const ON = ["cat-tower", "tiles", "birdwatch"] as const;

const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Room = RoomCore<BirdState>;

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const game = (r: Room) => r.state.gameState as BirdState;
const deviceOf = (seat: number) => (seat === 0 ? "phone" : "tablet");
const act = (r: Room, seat: number, action: BirdAction, device = deviceOf(seat)) => r.handle(device, { t: "act", seat, action });
const eventsTo = (out: Outbound[], to: string): RoomEvent[] =>
  out.flatMap((o) => (o.to === to && o.message.t === "event" ? [o.message.event] : []));
const birdEventsTo = (out: Outbound[], to: string): BirdEvent[] =>
  eventsTo(out, to).flatMap((e) => (e.kind === "birdwatch" ? [e.event] : []));
const viewOf = (r: Room, device: string) => r.snapshotFor(device).room.birdwatch as BirdView;

function lobby(features: RoomFeatures = { streaks: true }): Room {
  const state = RoomCore.create<BirdState>("BCDFG", "phone", clock, undefined, undefined, "birdwatch");
  const r = new RoomCore<BirdState>(state, () => clock, rng, undefined, 1, { games: ON, ...features });
  r.connect("phone", { [person(1).id]: A });
  r.connect("tablet", { [person(2).id]: B });
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  return r;
}

/** Seat 0 is player A on the phone, seat 1 player B on the tablet, then `bots` House Cats. */
function started(features: RoomFeatures = { streaks: true }, bots = 2): Room {
  const r = lobby(features);
  for (let seat = 2; seat < 2 + bots; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  for (let seat = 2 + bots; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
  return r;
}

/** Plays on (bots by the clock, people with a plain move) until `stop`. */
function until(r: Room, stop: (s: BirdState) => boolean): void {
  for (let i = 0; i < 2000 && !stop(game(r)); i++) {
    const s = game(r);
    const seat = actor(s);
    if (seat === null || r.state.seats[seat]?.kind === "bot") {
      clock = Math.max(clock, (r.state.timers.botAt ?? r.state.timers.nextRoundAt) as number);
      r.tick();
    } else {
      expect(errorsOf(act(r, seat, plainAction(s, seat)))).toEqual([]);
    }
  }
  expect(stop(game(r))).toBe(true);
}

describe("a Birdwatch lobby", () => {
  it("has six seats, four of them open, and the official rules to start with", () => {
    const state = RoomCore.create("BCDFG", "phone", clock, undefined, undefined, "birdwatch");
    expect(state.seats.map((s) => s.kind)).toEqual(["open", "open", "open", "open", "closed", "closed"]);
    expect(state.options).toEqual({ rules: "official" });
  });

  it("Cat Tower and tile game tables have no options, so their snapshots never gain the key", () => {
    for (const g of ["cat-tower", "tiles"] as const) {
      const state = RoomCore.create<TilesState>("BCDFG", "phone", clock, undefined, undefined, g);
      expect("options" in state).toBe(false);
      expect(state.seats.filter((s) => s.kind === "open")).toHaveLength(2);
      const r = new RoomCore<TilesState>(state, () => clock, rng, undefined, 1, { streaks: true, games: ON });
      r.connect("phone");
      expect("options" in r.snapshotFor("phone").room).toBe(false);
      expect(parseClientMessage(JSON.stringify({ t: "setOptions", options: { rules: "tucker" } }), r.parseAction, r.parseAim, r.parseOptions)).toEqual({
        error: "bad_message",
      });
    }
  });

  it("the host picks the rule set; nobody else does, and only in the lobby", () => {
    const r = lobby();
    const set = (device: string, rules: string) => {
      const msg = parseClientMessage(JSON.stringify({ t: "setOptions", options: { rules } }), r.parseAction, r.parseAim, r.parseOptions);
      return "error" in msg ? [msg.error] : errorsOf(r.handle(device, msg));
    };
    expect(set("phone", "tucker")).toEqual([]);
    expect(r.snapshotFor("tablet").room.options).toEqual({ rules: "tucker" });
    expect(set("tablet", "friesen")).toEqual(["not_allowed"]);
    expect(set("phone", "house")).toEqual(["bad_message"]);
    expect(r.handle("phone", { t: "setOptions", options: { rules: "tucker" } })).toEqual([]);
    r.handle("phone", { t: "configure", seat: 2, kind: "bot" });
    r.handle("phone", { t: "configure", seat: 3, kind: "bot" });
    r.handle("phone", { t: "start" });
    expect(set("phone", "official")).toEqual(["not_lobby"]);
    expect(game(r).rules).toBe("tucker");
  });

  it("needs four players at least", () => {
    const r = lobby();
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual(["seats_open"]);
    r.handle("phone", { t: "configure", seat: 2, kind: "bot" });
    r.handle("phone", { t: "configure", seat: 3, kind: "closed" });
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual(["not_enough_players"]);
  });
});

describe("swapping seats", () => {
  it("the host swaps any two seats, and everyone sees it", () => {
    const r = lobby();
    r.handle("phone", { t: "configure", seat: 3, kind: "bot" });
    const out = r.handle("phone", { t: "swapSeats", seats: [1, 3] });
    const seats = (out.find((o) => o.to === "tablet")?.message as Snapshot).room.seats;
    expect(seats.map((s) => s.kind)).toEqual(["human", "bot", "open", "human", "closed", "closed"]);
    expect(seats[3]).toMatchObject({ person: person(2), yours: true });
  });

  it("a move code goes with its seat", () => {
    const r = lobby();
    const code = (r.handle("phone", { t: "moveSeat", seat: 0 })[0]?.message as { code: string }).code;
    r.handle("phone", { t: "swapSeats", seats: [0, 2] });
    expect(r.state.moveCodes[code]?.seat).toBe(2);
    r.handle("phone", { t: "swapSeats", seats: [3, 2] });
    expect(r.state.moveCodes[code]?.seat).toBe(3);
    // A code for neither seat stays where it is.
    r.handle("phone", { t: "swapSeats", seats: [4, 5] });
    expect(r.state.moveCodes[code]?.seat).toBe(3);
  });

  it("only the host, two different seats, and only in the lobby", () => {
    const r = lobby();
    expect(errorsOf(r.handle("tablet", { t: "swapSeats", seats: [0, 1] }))).toEqual(["not_allowed"]);
    expect(errorsOf(r.handle("phone", { t: "swapSeats", seats: [1, 1] }))).toEqual(["bad_seat"]);
    expect(errorsOf(r.handle("phone", { t: "swapSeats", seats: [1, 6] }))).toEqual(["bad_seat"]);
    const s = started();
    expect(errorsOf(s.handle("phone", { t: "swapSeats", seats: [0, 1] }))).toEqual(["not_lobby"]);
  });

  it("the parser takes two seat numbers and nothing else", () => {
    expect(parseClientMessage('{"t":"swapSeats","seats":[0,3]}')).toEqual({ t: "swapSeats", seats: [0, 3] });
    for (const bad of ['{"t":"swapSeats","seats":[0]}', '{"t":"swapSeats","seats":[0,"1"]}', '{"t":"swapSeats","seats":[0,-1]}', '{"t":"swapSeats","seats":[0,1],"x":1}', '{"t":"swapSeats"}']) {
      expect(parseClientMessage(bad), bad).toEqual({ error: "bad_message" });
    }
  });
});

describe("a Birdwatch table on the wire", () => {
  it("says its game, keeps Cat Tower's key empty, and shows each device its own hand", () => {
    const r = started();
    const { room } = r.snapshotFor("phone");
    expect([room.gameId, room.game, room.options]).toEqual(["birdwatch", null, { rules: "official" }]);
    expect(Object.keys(room.birdwatch?.hands ?? {})).toEqual(["0"]);
    expect(room.birdwatch?.hands[0]).toEqual(game(r).hands[0]);
    expect(Object.keys(viewOf(r, "tablet").hands)).toEqual(["1"]);
  });

  it("sends its events under its own kind, each device's copy filtered", () => {
    const r = started();
    until(r, (s) => s.phase === "nest");
    const bidder = actor(game(r)) as number;
    const s = game(r);
    clock = Math.max(clock, r.state.timers.botAt ?? clock);
    const out = r.state.seats[bidder]?.kind === "bot" ? r.tick() : act(r, bidder, plainAction(s, bidder));
    const mine = birdEventsTo(out, deviceOf(bidder === 1 ? 1 : 0));
    const put = mine.find((e) => e.kind === "putBack");
    expect(put).toMatchObject({ kind: "putBack", seat: bidder, count: 5 });
    if (bidder > 1) expect(put && "cards" in put).toBe(false);
  });

  it("the live table counts each seat's side's score", () => {
    const r = started({ streaks: true, live: true });
    until(r, (s) => s.history.length === 1);
    until(r, (s) => s.phase === "bidding" && s.hand === 2 && actor(s) !== null);
    r.drainLiveIntents();
    r.handle("phone", { t: "presence", state: "background" });
    const [start] = r.drainLiveIntents();
    const scores = game(r).scores;
    expect(start?.state.progressKind).toBe("score");
    expect(start?.state.seats.map((s) => s.progress)).toEqual([scores[0], scores[1], scores[0], scores[1]]);
  });

  it("Play again keeps the rule set", () => {
    const r = lobby();
    r.handle("phone", { t: "setOptions", options: { rules: "friesen" } });
    r.handle("phone", { t: "configure", seat: 2, kind: "bot" });
    r.handle("phone", { t: "configure", seat: 3, kind: "bot" });
    r.handle("phone", { t: "start" });
    r.state.status = "over";
    expect(errorsOf(r.handle("phone", { t: "rematch" }))).toEqual([]);
    const intent = r.drainRematch();
    expect(intent).toMatchObject({ game: "birdwatch", options: { rules: "friesen" } });
    const next = RoomCore.rematchState<BirdState>("FGHJK", intent as NonNullable<typeof intent>, clock);
    expect(next.options).toEqual({ rules: "friesen" });
    const dealt = new RoomCore<BirdState>(next, () => clock, rng, undefined, 1, { streaks: true, games: ON });
    dealt.deal();
    expect(game(dealt).rules).toBe("friesen");
  });
});

describe("a House Cat takes the seat of a person who leaves", () => {
  it("on a forfeit: the seat goes to a House Cat, the table is told, and the game plays on", () => {
    const r = started();
    r.drainStreakIntents();
    // A code to move the seat to another phone goes with the person.
    r.handle("tablet", { t: "moveSeat", seat: 1 });
    expect(Object.keys(r.state.moveCodes)).toHaveLength(1);
    const out = act(r, 1, { type: "forfeit" });
    expect(r.state.moveCodes).toEqual({});
    expect(errorsOf(out)).toEqual([]);
    expect(eventsTo(out, "phone")).toEqual([{ kind: "houseCat", seat: 1 }]);
    expect(r.state.seats[1]).toMatchObject({ kind: "bot", botLevel: "house", left: true, person: person(2), playerId: B });
    const seat = r.snapshotFor("tablet").room.seats[1];
    expect(seat).toEqual({ kind: "bot", person: person(2), yours: false, presence: null, left: true });
    expect([r.state.status, game(r).status]).toEqual(["playing", "playing"]);
    // The person is out of this game: their lists, their pairs.
    expect(r.outSeats()).toEqual([false, true, false, false]);
    expect(r.controlledSeats("tablet")).toEqual([]);
    expect(r.heldSeats("tablet")).toEqual([1]);
    expect(r.allOut(r.heldSeats("tablet"))).toBe(true);
    expect(r.outPlayers()).toEqual([B]);
    expect(r.drainStreakIntents()).toEqual([expect.objectContaining({ out: [B], over: false })]);
    expect(errorsOf(act(r, 1, { type: "pass" }))).toEqual(["not_your_seat"]);
  });

  it("on the leaver's own move, even with the nest in hand, the House Cat picks it up", () => {
    const r = started();
    const s = game(r);
    const hands = s.hands.map((h, seat) => (seat === 1 ? [...h, ...s.nest].sort((x, y) => x - y) : h));
    r.state.gameState = { ...s, phase: "nest", turn: 1, high: { seat: 1, amount: 70 }, fromNest: s.nest, nest: [], hands };
    act(r, 1, { type: "forfeit" });
    expect(r.state.timers.botAt).not.toBeNull();
    clock = r.state.timers.botAt as number;
    r.tick();
    expect(game(r).phase).toBe("trump");
    expect(game(r).hands[1]).toHaveLength(9);
  });

  it("a seat retired after three days goes to a House Cat too", () => {
    const r = started();
    until(r, (s) => actor(s) === 1);
    clock += RETIRE_AFTER_MS;
    const out = r.handle("phone", { t: "retire", seat: 1 });
    expect(errorsOf(out)).toEqual([]);
    expect(eventsTo(out, "phone")[0]).toEqual({ kind: "houseCat", seat: 1 });
    expect(r.drainRetireIntents()).toEqual([expect.objectContaining({ kind: "done", playerId: B, seat: 1 })]);
    expect(r.state.timers.botAt).not.toBeNull();
  });

  it("deleting or merging the account that left reaches the seat it left", () => {
    const merged = started();
    act(merged, 1, { type: "forfeit" });
    merged.adopt({ from: B, to: "p_CCCCCCCCCCCCCCCCCCCCCC" });
    expect(merged.state.seats[1]).toMatchObject({ kind: "bot", left: true, playerId: "p_CCCCCCCCCCCCCCCCCCCCCC" });
    const deleted = started();
    act(deleted, 1, { type: "forfeit" });
    deleted.adopt({ from: B, to: null });
    expect(deleted.state.seats[1]?.playerId).toBeUndefined();
    expect(deleted.seatPlayers()).toEqual([A]);
    expect(deleted.outPlayers()).toEqual([]);
  });

  it("the game ends once no person is left", () => {
    const r = started();
    act(r, 1, { type: "forfeit" });
    const out = act(r, 0, { type: "forfeit" });
    expect(birdEventsTo(out, "phone")).toEqual([{ kind: "gameOver", winners: [], scores: [0, 0], reason: "left" }]);
    expect([r.state.status, game(r).endReason, r.state.timers.botAt]).toEqual(["over", "left", null]);
  });

  it("Play again deals a seat a House Cat took as a plain House Cat", () => {
    const r = started();
    act(r, 1, { type: "forfeit" });
    r.state.status = "over";
    r.handle("phone", { t: "rematch" });
    const seats = r.drainRematch()?.seats;
    // The first seat rotates to the end.
    expect(seats?.[0]).toEqual({ kind: "bot", botLevel: "house" });
    expect(seats?.[3]).toMatchObject({ kind: "human", person: person(1) });
  });
});
