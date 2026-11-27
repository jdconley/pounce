import { beforeEach, describe, expect, it } from "vitest";

import { purrtrait } from "../games/purrtrait";
import { parseClientMessage, type ClientMessage, type Person, type ServerMessage } from "../protocol";
import { WORDS } from "../purrtrait/words";

import { NEAR_KEY_MS, NEAR_TYPED_MISSES, RoomCore, SCREEN_GRACE_MS, STALL_END_MS, type Outbound } from "./core";

import type { RoomGame } from "../games";
import type { PurrState } from "../purrtrait/engine";
import type { PurrView } from "../purrtrait/view";

/* A Purrtrait room's turn clock: it runs only while a screen is there. */

const T0 = 1_000_000;
const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });

type Room = RoomCore<PurrState>;
let clock = T0;
const rng = () => 0.25;
beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const game = (r: Room) => r.state.gameState as PurrState;
const viewOf = (r: Room, device: string) => r.snapshotFor(device).room.purrtrait as PurrView;
const act = (r: Room, device: string, seat: number, action: unknown) =>
  r.handle(device, { t: "act", seat, action } as ClientMessage);

/** Seats 0 ("a") and 1 ("b") play; "tv" is the screen. */
function started(speed = 1, seats = 2): Room {
  const state = RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait");
  const r = new RoomCore<PurrState>(state, () => clock, rng, undefined, speed, { games: ["cat-tower", "purrtrait"], tv: true, streaks: true });
  r.addScreen("tv");
  r.connect("tv");
  r.connect("a");
  r.connect("b");
  r.handle("a", { t: "claim", seat: 0, person: person(1) });
  r.handle("b", { t: "claim", seat: 1, person: person(2) });
  if (seats > 2) {
    r.connect("c");
    r.handle("a", { t: "configure", seat: 2, kind: "open" });
    r.handle("c", { t: "claim", seat: 2, person: person(3) });
  }
  for (let seat = seats; seat < state.seats.length; seat++) r.handle("a", { t: "configure", seat, kind: "closed" });
  expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
  return r;
}

/** The room as a fresh Durable Object would build it from storage. */
function rebuild(r: Room): Room {
  const state = JSON.parse(JSON.stringify(r.state)) as typeof r.state;
  return new RoomCore<PurrState>(state, () => clock, rng, undefined, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: true });
}

describe("the turn clock", () => {
  it("the first choosing snapshot after Start carries the running clock", () => {
    const state = RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait");
    const r = new RoomCore<PurrState>(state, () => clock, rng, undefined, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: true });
    r.addScreen("tv");
    for (const d of ["tv", "a", "b"]) r.connect(d);
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    r.handle("b", { t: "claim", seat: 1, person: person(2) });
    for (let seat = 2; seat < state.seats.length; seat++) r.handle("a", { t: "configure", seat, kind: "closed" });
    const out = r.handle("a", { t: "start" });
    const firsts = ["tv", "a", "b"].map((d) => out.find((o) => o.to === d && o.message.t === "snapshot")?.message);
    for (const snap of firsts) {
      expect((snap as { room: { purrtrait: PurrView } }).room.purrtrait).toMatchObject({ phase: "choosing", remainingMs: 10_000, paused: false });
    }
  });

  it("choosing times out to the easy word", () => {
    const r = started();
    expect(game(r).phase).toBe("choosing");
    expect(viewOf(r, "tv").remainingMs).toBe(10_000);
    expect(r.nextAlarm()).toBe(T0 + 10_000);
    clock = T0 + 10_000;
    r.tick();
    const s = game(r);
    expect(s.phase).toBe("drawing");
    expect(s.level).toBe("easy");
    expect(viewOf(r, "tv").remainingMs).toBe(60_000);
    expect(r.state.timers.turnEndsAt).toBe(T0 + 70_000);
    // The alarm comes sooner for the TV's next near key.
    expect(r.nextAlarm()).toBe(T0 + NEAR_KEY_MS);
  });

  it("drawing times out to timeUp", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "tricky" });
    expect(game(r).phase).toBe("drawing");
    expect(viewOf(r, "tv").remainingMs).toBe(60_000);
    clock = T0 + 30_000;
    expect(viewOf(r, "tv").remainingMs).toBe(30_000);
    clock = T0 + 60_000;
    const word = WORDS[game(r).word as number]?.word;
    const out = r.tick();
    expect(errorsOf(out)).toEqual([]);
    expect(game(r).phase).toBe("reveal");
    expect(viewOf(r, "tv").last).toMatchObject({ word, guesser: null, points: 0 });
    expect(viewOf(r, "tv").remainingMs).toBeNull();
    // The reveal runs on the room's usual pause, then the next turn begins.
    clock += 6_000;
    r.tick();
    expect(game(r).phase).toBe("choosing");
    expect(viewOf(r, "tv").drawer).toBe(1);
  });

  it("does not move on early", () => {
    const r = started();
    clock = T0 + 9_999;
    r.tick();
    expect(game(r).phase).toBe("choosing");
  });

  it("the screen leaving pauses after the grace and resumes with the same remainingMs", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock = T0 + 20_000;
    r.disconnect("tv");
    // Within the grace the clock runs.
    clock += SCREEN_GRACE_MS - 1;
    r.tick();
    expect(viewOf(r, "a").paused).toBe(false);
    clock += 1;
    const out = r.tick();
    expect(out.some((o) => o.message.t === "snapshot")).toBe(true);
    const left = viewOf(r, "a");
    expect(left.paused).toBe(true);
    expect(left.remainingMs).toBe(60_000 - 20_000 - SCREEN_GRACE_MS);
    expect(r.state.timers.turnEndsAt).toBeNull();
    // Nothing happens however long the screen is away (short of the stall).
    clock += 20 * 60_000;
    r.tick();
    expect(game(r).phase).toBe("drawing");
    expect(viewOf(r, "a").remainingMs).toBe(left.remainingMs);
    clock += 1_000;
    r.connect("tv");
    const back = viewOf(r, "a");
    expect(back.paused).toBe(false);
    expect(back.remainingMs).toBe(left.remainingMs);
    expect(r.state.timers.turnEndsAt).toBe(clock + (left.remainingMs as number));
    clock += left.remainingMs as number;
    r.tick();
    expect(game(r).phase).toBe("reveal");
  });

  it("another seat leaving mid-turn leaves the clock alone", () => {
    const r = started(1, 3);
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock += 5_000;
    expect(errorsOf(act(r, "c", 2, { type: "forfeit" }))).toEqual([]);
    expect(game(r).phase).toBe("drawing");
    expect(viewOf(r, "a").remainingMs).toBe(55_000);
  });

  it("a late alarm never times out a turn whose screen was already gone", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock = T0 + 10_000;
    r.disconnect("tv");
    // The alarm is long overdue (the deadline was T0 + 60 000).
    clock = T0 + 100_000;
    r.tick();
    expect(game(r).phase).toBe("drawing");
    expect(viewOf(r, "a")).toMatchObject({ paused: true, remainingMs: 60_000 - 10_000 - SCREEN_GRACE_MS });
    expect(r.state.timers.pausedAt).toBe(T0 + 10_000 + SCREEN_GRACE_MS);
  });

  it("a deadline that passed before the screen left still times out", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock = T0 + 55_000;
    r.disconnect("tv");
    clock = T0 + 200_000;
    r.tick();
    expect(game(r).phase).toBe("reveal");
  });

  it("the stall counts the whole absence, across turns", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    const pausedAt = clock;
    // The drawer ends the turn; the reveal and the next turn keep the same pause.
    act(r, "a", 0, { type: "giveUp" });
    expect(r.state.timers.pausedAt).toBe(pausedAt);
    clock += 6_000;
    r.tick();
    expect(game(r).phase).toBe("choosing");
    expect(r.state.timers.pausedAt).toBe(pausedAt);
    clock = pausedAt + STALL_END_MS;
    r.tick();
    expect(game(r).phase).toBe("over");
    expect(game(r).endReason).toBe("stalled");
  });

  it("a screen that comes back in a reveal clears the pause", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    act(r, "a", 0, { type: "giveUp" });
    expect(game(r).phase).toBe("reveal");
    expect(r.state.timers.pausedAt).not.toBeNull();
    r.connect("tv");
    expect(r.state.timers.pausedAt).toBeNull();
    clock += 6_000;
    r.tick();
    expect(viewOf(r, "a")).toMatchObject({ phase: "choosing", paused: false, remainingMs: 10_000 });
  });

  it("a room rebuilt from storage keeps its clock, mid-drawing", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock += 15_000;
    const again = rebuild(r);
    expect(viewOf(again, "a")).toMatchObject({ paused: false, remainingMs: 45_000 });
    expect(again.nextAlarm()).toBe(r.nextAlarm());
    clock += 45_000;
    again.tick();
    expect(game(again).phase).toBe("reveal");
  });

  it("a room rebuilt from storage keeps its pause and resumes", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    clock += 20_000;
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    clock += 60_000;
    const again = rebuild(r);
    expect(viewOf(again, "a")).toMatchObject({ paused: true, remainingMs: 30_000 });
    expect(again.nextAlarm()).toBe(r.nextAlarm());
    again.tick();
    expect(game(again).phase).toBe("drawing");
    again.connect("tv");
    expect(viewOf(again, "a")).toMatchObject({ paused: false, remainingMs: 30_000 });
    clock += 30_000;
    again.tick();
    expect(game(again).phase).toBe("reveal");
  });

  it("a screen back inside the grace never pauses", () => {
    const r = started();
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS - 1;
    r.connect("tv");
    r.tick();
    expect(viewOf(r, "a").paused).toBe(false);
    expect(r.state.timers.turnEndsAt).toBe(T0 + 10_000);
  });

  it("a turn that starts with no screen starts paused", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "easy" });
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    act(r, "a", 0, { type: "giveUp" });
    clock += 6_000;
    r.tick();
    expect(game(r).phase).toBe("choosing");
    const v = viewOf(r, "a");
    expect(v.paused).toBe(true);
    expect(v.remainingMs).toBe(10_000);
  });

  it("30 minutes paused ends the game stalled", () => {
    const r = started();
    act(r, "a", 0, { type: "choose", level: "tricky" });
    act(r, "a", 0, { type: "gotIt", seat: 1 });
    expect(game(r).scores).toEqual([2, 2]);
    clock += 6_000;
    r.tick();
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    const pausedAt = clock;
    expect(r.state.timers.pausedAt).toBe(pausedAt);
    expect(r.nextAlarm()).toBeLessThanOrEqual(pausedAt + STALL_END_MS);
    clock = pausedAt + STALL_END_MS - 1;
    r.tick();
    expect(game(r).phase).not.toBe("over");
    clock += 1;
    const out = r.tick();
    expect(errorsOf(out)).toEqual([]);
    expect(game(r).phase).toBe("over");
    expect(game(r).endReason).toBe("stalled");
    expect(r.state.status).toBe("over");
    expect(r.state.timers.turnEndsAt).toBeNull();
    expect(r.state.timers.pausedLeftMs).toBeNull();
    expect(viewOf(r, "a").remainingMs).toBeNull();
    expect(viewOf(r, "a").scores).toEqual([2, 2]);
    expect(viewOf(r, "a").winners).toEqual([0, 1]);
  });

  it("the dev speed shortens the clock and the stall", () => {
    const r = started(10);
    expect(r.state.timers.turnEndsAt).toBe(T0 + 1_000);
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS / 10;
    r.tick();
    expect(r.nextAlarm()).toBe(clock + STALL_END_MS / 10);
  });

  it("Cat Tower rooms never set turnEndsAt", () => {
    const state = RoomCore.create("BCDFG", "a", clock);
    const r = new RoomCore(state, () => clock, rng, undefined, 1, { tv: true, streaks: true });
    r.addScreen("tv");
    r.connect("tv");
    r.connect("a");
    r.connect("b");
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    r.handle("b", { t: "claim", seat: 1, person: person(2) });
    r.handle("a", { t: "configure", seat: 2, kind: "bot" });
    r.handle("a", { t: "configure", seat: 3, kind: "closed" });
    r.handle("a", { t: "configure", seat: 4, kind: "closed" });
    r.handle("a", { t: "configure", seat: 5, kind: "closed" });
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
    expect(r.state.status).toBe("playing");
    r.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    r.tick();
    expect(r.state.timers.turnEndsAt ?? null).toBeNull();
    expect(r.state.timers.pausedLeftMs ?? null).toBeNull();
    expect(JSON.stringify(r.snapshotFor("a"))).not.toContain("remainingMs");
  });
});

describe("room-only actions", () => {
  const wire = (r: Room, action: unknown) =>
    parseClientMessage(JSON.stringify({ t: "act", seat: 0, action }), r.parseAction, r.parseAim, r.parseOptions);

  it("a client's timeUp or nextTurn is not_allowed, not bad_message", () => {
    const r = started();
    for (const action of [{ type: "timeUp" }, { type: "nextTurn" }]) {
      const msg = wire(r, action);
      expect(msg).toMatchObject({ t: "act" });
      const out = r.handle("a", msg as ClientMessage);
      expect(out).toEqual([{ to: "a", message: { t: "error", code: "not_allowed" } as ServerMessage }]);
    }
    expect(game(r).phase).toBe("choosing");
  });

  it("junk is still bad_message", () => {
    const r = started();
    expect(wire(r, { type: "nope" })).toEqual({ error: "bad_message" });
  });
});

/* Live ink (design §6): relayed to the screen and the drawer's device only, kept in memory only. */

type Op = (string | number)[];
const ink = (r: Room, device: string, seat: number, turn: string, ops: Op[]) =>
  r.handle(device, { t: "ink", seat, turn, ops } as ClientMessage);
const turnOf = (r: Room) => viewOf(r, "tv").turn;
const inkTo = (out: Outbound[]) => out.filter((o) => o.message.t === "ink").map((o) => o.to);
const only = (out: Outbound[], t: ServerMessage["t"]) => out.filter((o) => o.message.t === t);
const dot = (id: number): Op => ["s", id, 0, 1, 100, 100, 1, 1];
const player = (n: number) => `player-${n}`;

/**
 * Seat 0 is player 1's, on "a" and on the family iPad "a2" (both speak for player 1); seat 1 is "b"'s.
 * "tv" is the screen and "w" a phone that only watches.
 */
function family(): Room {
  const state = RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait");
  const r = new RoomCore<PurrState>(state, () => clock, rng, undefined, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: false });
  r.addScreen("tv");
  r.connect("tv");
  r.connect("a", { [person(1).id]: player(1) });
  r.connect("a2", { [person(1).id]: player(1) });
  r.connect("b");
  r.connect("w");
  r.handle("a", { t: "claim", seat: 0, person: person(1) });
  r.handle("b", { t: "claim", seat: 1, person: person(2) });
  expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
  expect(game(r).drawer).toBe(0);
  return r;
}

/** Seat 0 has picked, from "a": the turn is "a"'s to draw. */
function drawing(): Room {
  const r = family();
  expect(errorsOf(act(r, "a", 0, { type: "choose", level: "easy" }))).toEqual([]);
  expect(game(r).phase).toBe("drawing");
  return r;
}

/** A small seeded rng for the property tests. */
function mulberry(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 2 ** 32;
  };
}

describe("ink", () => {
  it("ink goes to the screen and the drawer's other sockets only (random rooms of 2-10 seats, shared phones)", () => {
    for (let seed = 1; seed <= 60; seed++) {
      const rand = mulberry(seed);
      const seats = 2 + Math.floor(rand() * 9);
      // Each seat's phone: a new one, or one already holding a seat (a shared phone).
      const holder: string[] = [];
      for (let i = 0; i < seats; i++) holder.push(i > 0 && rand() < 0.35 ? (holder[Math.floor(rand() * i)] as string) : `d${i}`);
      // Some seats' players are on a second device too (a parent's iPad).
      const extra = Array.from({ length: seats }, (_, i) => (rand() < 0.3 ? `x${i}` : null));
      const maps = new Map<string, Record<string, string>>();
      holder.forEach((d, i) => maps.set(d, { ...maps.get(d), [person(i + 1).id]: player(i + 1) }));
      extra.forEach((d, i) => d && maps.set(d, { [person(i + 1).id]: player(i + 1) }));
      const host = holder[0] as string;
      const state = RoomCore.create<PurrState>("BCDFG", host, clock, undefined, undefined, "purrtrait");
      const r = new RoomCore<PurrState>(state, () => clock, rng, undefined, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: false });
      r.addScreen("tv");
      r.connect("tv");
      r.connect("watcher");
      for (const [d, map] of maps) r.connect(d, map);
      r.handle(host, { t: "claim", seat: 0, person: person(1) });
      for (let i = 1; i < state.seats.length; i++) r.handle(host, { t: "configure", seat: i, kind: i < seats ? "open" : "closed" });
      for (let i = 1; i < seats; i++) expect(errorsOf(r.handle(holder[i] as string, { t: "claim", seat: i, person: person(i + 1) }))).toEqual([]);
      expect(errorsOf(r.handle(host, { t: "start" }))).toEqual([]);

      const drawer = game(r).drawer as number;
      const devices = [...maps.keys(), "watcher"];
      const controllers = devices.filter((d) => r.controlledSeats(d).includes(drawer));
      const chooser = controllers[Math.floor(rand() * controllers.length)] as string;
      expect(errorsOf(act(r, chooser, drawer, { type: "choose", level: "easy" }))).toEqual([]);
      const turn = turnOf(r);
      const out = ink(r, chooser, drawer, turn, [dot(0)]);
      expect(new Set(out.map((o) => o.to)), `seed ${seed}`).toEqual(new Set(["tv", chooser]));
      expect(out.every((o) => o.message.t === "ink")).toBe(true);
      expect(out[0]?.message).toEqual({ t: "ink", seat: drawer, turn, ops: [dot(0)] });
      for (const d of devices) {
        if (d === chooser) continue;
        // Anyone else's well-formed ink is dropped silently, whichever seat it names.
        for (let seat = 0; seat < seats; seat++) expect(ink(r, d, seat, turn, [dot(1)]), `seed ${seed} ${d}`).toEqual([]);
      }
      // None of that took a stroke id: the drawer's next stroke is still 1.
      expect(inkTo(ink(r, chooser, drawer, turn, [dot(1)])).sort()).toEqual([chooser, "tv"].sort());
    }
  });

  it("ink from a guesser, a stale turn, before choose or for another seat is dropped", () => {
    const r = family();
    const turn = turnOf(r);
    expect(ink(r, "a", 0, turn, [dot(0)])).toEqual([]);
    act(r, "a", 0, { type: "choose", level: "easy" });
    expect(ink(r, "b", 1, turn, [dot(0)])).toEqual([]);
    expect(ink(r, "b", 0, turn, [dot(0)])).toEqual([]);
    expect(ink(r, "a", 0, "1:9", [dot(0)])).toEqual([]);
    expect(ink(r, "a", 1, turn, [dot(0)])).toEqual([]);
    expect(ink(r, "a", 7, turn, [dot(0)])).toEqual([]);
    expect(ink(r, "w", 0, turn, [dot(0)])).toEqual([]);
    // The drawer's own is taken, and its first stroke is still stroke 0.
    expect(inkTo(ink(r, "a", 0, turn, [dot(0)]))).toEqual(["tv", "a"]);
  });

  it("a screen's ink is not_allowed, and so is ink at a table of another game", () => {
    const r = drawing();
    expect(errorsOf(ink(r, "tv", 0, turnOf(r), [dot(0)]))).toEqual(["not_allowed"]);
    const state = RoomCore.create("BCDFG", "a", clock);
    const cat = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: false, tv: true });
    cat.connect("a");
    expect(errorsOf(cat.handle("a", { t: "ink", seat: 0, turn: "1:0", ops: [["c"]] } as ClientMessage))).toEqual(["not_allowed"]);
  });

  it("bad ops are bad_message; a full easel is easel_full once per turn", () => {
    const r = drawing();
    const turn = turnOf(r);
    expect(errorsOf(ink(r, "a", 0, turn, [dot(1)]))).toEqual(["bad_message"]);
    expect(errorsOf(ink(r, "a", 0, turn, [["p", 0, 1, 1]]))).toEqual(["bad_message"]);
    for (let id = 0; id < 500; id++) {
      if (id % 25 === 0) clock += 1000;
      expect(errorsOf(ink(r, "a", 0, turn, [["s", id, 0, 0, 0, 0]]))).toEqual([]);
    }
    clock += 1000;
    expect(errorsOf(ink(r, "a", 0, turn, [dot(500)]))).toEqual(["easel_full"]);
    expect(ink(r, "a", 0, turn, [dot(500)])).toEqual([]);
    // A clear makes room.
    expect(inkTo(ink(r, "a", 0, turn, [["c"], dot(500)]))).toEqual(["tv", "a"]);
  });

  it("the 26th message in a second is dropped, and a second later one is taken again", () => {
    const r = drawing();
    const turn = turnOf(r);
    expect(inkTo(ink(r, "a", 0, turn, [dot(0)]))).toEqual(["tv", "a"]);
    for (let i = 1; i < 25; i++) expect(inkTo(ink(r, "a", 0, turn, [["p", 0, 1, 0]]))).toEqual(["tv", "a"]);
    expect(ink(r, "a", 0, turn, [["p", 0, 1, 0]])).toEqual([]);
    clock += 999;
    expect(ink(r, "a", 0, turn, [["p", 0, 1, 0]])).toEqual([]);
    clock += 1;
    expect(inkTo(ink(r, "a", 0, turn, [["p", 0, 1, 0]]))).toEqual(["tv", "a"]);
  });

  it("a screen connecting mid-turn gets inkSync after its snapshot: s,s,u,c,s is one stroke", () => {
    const r = drawing();
    const turn = turnOf(r);
    for (const ops of [[dot(0)], [dot(1)], [["u", 1]], [["c"]], [["s", 2, 3, 2, 30, 30, 2, 2]], [["p", 2, 1, 1]]]) ink(r, "a", 0, turn, ops);
    r.disconnect("tv");
    const out = r.connect("tv");
    const mine = out.filter((o) => o.to === "tv").map((o) => o.message.t);
    expect(mine.slice(-2)).toEqual(["snapshot", "inkSync"]);
    expect(only(out, "inkSync")).toEqual([{ to: "tv", message: { t: "inkSync", turn, ops: [["s", 2, 3, 2, 30, 30, 2, 2, 1, 1]] } }]);
    // The drawer's device too, on a reconnect. Nobody else.
    r.disconnect("a");
    expect(only(r.connect("a", { [person(1).id]: player(1) }), "inkSync")).toHaveLength(1);
    for (const d of ["a2", "b", "w"]) {
      r.disconnect(d);
      expect(only(r.connect(d, d === "a2" ? { [person(1).id]: player(1) } : {}), "inkSync")).toEqual([]);
    }
  });

  it("no inkSync while choosing", () => {
    const r = family();
    r.disconnect("tv");
    expect(only(r.connect("tv"), "inkSync")).toEqual([]);
  });

  it("a new turn drops the ink", () => {
    const r = drawing();
    const turn = turnOf(r);
    ink(r, "a", 0, turn, [dot(0)]);
    act(r, "a", 0, { type: "gotIt", seat: 1 });
    expect(game(r).phase).toBe("reveal");
    // The turn's drawing is over: late ink is dropped, and a screen joining gets none.
    expect(ink(r, "a", 0, turn, [["p", 0, 1, 1]])).toEqual([]);
    r.disconnect("tv");
    expect(only(r.connect("tv"), "inkSync")).toEqual([]);
    clock += 10_000;
    r.tick();
    expect(game(r)).toMatchObject({ phase: "choosing", drawer: 1 });
    expect(r.state.drawerDevice).toBeUndefined();
    act(r, "b", 1, { type: "choose", level: "easy" });
    const next = turnOf(r);
    expect(next).not.toBe(turn);
    r.disconnect("tv");
    expect(only(r.connect("tv"), "inkSync")).toEqual([{ to: "tv", message: { t: "inkSync", turn: next, ops: [] } }]);
    // Stroke ids start again at 0.
    expect(inkTo(ink(r, "b", 1, next, [dot(0)]))).toEqual(["tv", "b"]);
  });

  it("a screen that is away gets none", () => {
    const r = drawing();
    r.disconnect("tv");
    expect(inkTo(ink(r, "a", 0, turnOf(r), [dot(0)]))).toEqual(["a"]);
  });

  it("a game whose stream goes to everyone reaches every connected device", () => {
    const base = purrtrait as RoomGame<PurrState>;
    const all = { ...base, stream: { ...(base.stream as NonNullable<typeof base.stream>), audience: "all" as const } };
    const state = RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait");
    const r = new RoomCore<PurrState>(state, () => clock, rng, all, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: false });
    r.addScreen("tv");
    for (const d of ["tv", "a", "b", "w"]) r.connect(d);
    r.connect("gone");
    r.disconnect("gone");
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    r.handle("b", { t: "claim", seat: 1, person: person(2) });
    r.handle("a", { t: "start" });
    act(r, "a", 0, { type: "choose", level: "easy" });
    expect(inkTo(ink(r, "a", 0, turnOf(r), [dot(0)])).sort()).toEqual(["a", "b", "tv", "w"]);
  });

  it("the room's state never holds the ink", () => {
    const r = drawing();
    const turn = turnOf(r);
    ink(r, "a", 0, turn, [["s", 0, 4, 2, 123, 456, 7, 8]]);
    ink(r, "a", 0, turn, [["p", 0, 9, 9], ["u", 0], ["c"]]);
    const saved = JSON.stringify(r.state);
    expect(saved).not.toContain("ops");
    expect(saved).not.toContain("456");
    expect(saved).not.toContain('"s"');
    expect(r.state.drawerDevice).toMatchObject({ deviceId: "a" });
  });
});

describe("ink after a rebuild from storage", () => {
  /** "a" drew a stroke; the room is rebuilt with every socket still open (a wake from hibernation). */
  function woken(): { r: Room; turn: string } {
    const before = drawing();
    const turn = turnOf(before);
    ink(before, "a", 0, turn, [dot(0)]);
    return { r: rebuild(before), turn };
  }

  it("a core rebuilt from storage asks the drawer for inkResend once", () => {
    const { r, turn } = woken();
    expect(r.rebuilt()).toEqual([{ to: "a", message: { t: "inkResend", turn } }]);
    // Nothing else asks again: not a tick, not a message, not another phone or the screen coming back.
    expect(only(r.tick(), "inkResend")).toEqual([]);
    expect(only(ink(r, "a", 0, turn, [["p", 0, 1, 1]]), "inkResend")).toEqual([]);
    r.disconnect("tv");
    const back = r.connect("tv");
    expect(only(back, "inkResend")).toEqual([]);
    // With no drawing to give, the screen gets no inkSync.
    expect(only(back, "inkSync")).toEqual([]);
  });

  it("only a batch that starts with a clear takes the place of the lost drawing, and the reply is exempt from the limit", () => {
    const { r, turn } = woken();
    r.rebuilt();
    // Points for a stroke the room no longer knows: dropped, not bad.
    expect(ink(r, "a", 0, turn, [["p", 0, 1, 1]])).toEqual([]);
    // The reply: its first message clears; the ids are the device's own, so they only have to go up.
    expect(inkTo(ink(r, "a", 0, turn, [["c"], ["s", 3, 0, 1, 100, 100]]))).toEqual(["tv", "a"]);
    // However long it takes, up to the message marked last.
    for (let i = 0; i < 40; i++) {
      clock += 50;
      expect(inkTo(ink(r, "a", 0, turn, [["p", 3, 1, 0]]))).toEqual(["tv", "a"]);
    }
    const last = r.handle("a", { t: "ink", seat: 0, turn, ops: [["s", 7, 0, 1, 100, 100]], last: true } as ClientMessage);
    expect(inkTo(last)).toEqual(["tv", "a"]);
    // `last` is the server's: the screen gets the ink as drawn.
    expect(last[0]?.message).toEqual({ t: "ink", seat: 0, turn, ops: [["s", 7, 0, 1, 100, 100]] });
    r.disconnect("tv");
    const sync = only(r.connect("tv"), "inkSync")[0]?.message as { ops: Op[] };
    expect(sync.ops.map((op) => op[1])).toEqual([3, 7]);
    // The exemption is spent: the limit holds again at once.
    for (let i = 0; i < 25; i++) ink(r, "a", 0, turn, [["p", 7, 0, 1]]);
    expect(ink(r, "a", 0, turn, [["p", 7, 0, 1]])).toEqual([]);
  });

  it("a drawer that was away is asked when it connects, each time while the drawing is still lost", () => {
    const { r, turn } = woken();
    r.disconnect("a");
    expect(r.rebuilt()).toEqual([]);
    const map = { [person(1).id]: player(1) };
    expect(only(r.connect("a", map), "inkResend")).toEqual([{ to: "a", message: { t: "inkResend", turn } }]);
    r.disconnect("a");
    expect(only(r.connect("a", map), "inkResend")).toHaveLength(1);
    ink(r, "a", 0, turn, [["c"]]);
    r.disconnect("a");
    const back = r.connect("a", map);
    expect(only(back, "inkResend")).toEqual([]);
    expect(only(back, "inkSync")).toEqual([{ to: "a", message: { t: "inkSync", turn, ops: [] } }]);
    // The iPad is never asked.
    r.disconnect("a2");
    expect(only(r.connect("a2", map), "inkResend")).toEqual([]);
  });

  it("nothing is lost, and nobody asked, in a room rebuilt while choosing or in the lobby", () => {
    const r = rebuild(family());
    expect(r.rebuilt()).toEqual([]);
    act(r, "a", 0, { type: "choose", level: "easy" });
    expect(inkTo(ink(r, "a", 0, turnOf(r), [dot(0)]))).toEqual(["tv", "a"]);
    const lobby = new RoomCore<PurrState>(RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait"), () => clock, rng);
    expect(lobby.rebuilt()).toEqual([]);
  });
});

describe("the drawer's device", () => {
  it("the first choose fixes it: only it sees the word and may draw, say gotIt or give up", () => {
    const r = family();
    // Before the pick, every device that controls the seat sees the choices.
    expect(viewOf(r, "a").choices).toBeDefined();
    expect(viewOf(r, "a2").choices).toBeDefined();
    act(r, "a", 0, { type: "choose", level: "easy" });
    expect(viewOf(r, "a")).toMatchObject({ youDraw: true });
    expect(viewOf(r, "a").word).toBeDefined();
    expect(viewOf(r, "a2").word).toBeUndefined();
    expect(viewOf(r, "a2").youDraw).toBeUndefined();
    expect(ink(r, "a2", 0, turnOf(r), [dot(0)])).toEqual([]);
    expect(errorsOf(act(r, "a2", 0, { type: "gotIt", seat: 1 }))).toEqual(["not_allowed"]);
    expect(errorsOf(act(r, "a2", 0, { type: "giveUp" }))).toEqual(["not_allowed"]);
    expect(game(r).phase).toBe("drawing");
    expect(errorsOf(act(r, "a", 0, { type: "giveUp" }))).toEqual([]);
    expect(game(r).phase).toBe("reveal");
  });

  it("another device of the drawer's player may still leave the game for the seat", () => {
    const r = drawing();
    expect(errorsOf(act(r, "a2", 0, { type: "forfeit" }))).toEqual([]);
    expect(game(r).phase).toBe("over");
  });

  it("a pick the clock made fixes no device: the first to draw does", () => {
    const r = family();
    clock += 10_000;
    r.tick();
    expect(game(r).phase).toBe("drawing");
    expect(r.state.drawerDevice).toBeUndefined();
    expect(viewOf(r, "a").word).toBeDefined();
    expect(viewOf(r, "a2").word).toBeDefined();
    const turn = turnOf(r);
    const seq = r.state.seq;
    const out = ink(r, "a2", 0, turn, [dot(0)]);
    expect(inkTo(out)).toEqual(["tv", "a2"]);
    expect(r.state.drawerDevice).toMatchObject({ deviceId: "a2" });
    // At once, every device gets its snapshot: "a" loses the word, "a2" keeps it.
    expect(r.state.seq).toBe(seq + 1);
    const snap = (d: string) => (only(out, "snapshot").find((o) => o.to === d)?.message as { seq: number; room: { purrtrait: PurrView } }).room.purrtrait;
    expect(snap("a").youDraw).toBeUndefined();
    expect(snap("a").word).toBeUndefined();
    expect(snap("a2")).toMatchObject({ youDraw: true });
    expect(snap("tv").word).toBeUndefined();
    // Later ink from the owner sends no snapshots.
    expect(only(ink(r, "a2", 0, turn, [dot(1)]), "snapshot")).toEqual([]);
    expect(ink(r, "a", 0, turn, [dot(2)])).toEqual([]);
    expect(viewOf(r, "a").word).toBeUndefined();
    // Still the drawer's device after a rebuild: its ink is lost, so it alone is asked for it.
    expect(rebuild(r).rebuilt()).toEqual([{ to: "a2", message: { t: "inkResend", turn } }]);
  });

  it("a new turn clears it", () => {
    const r = drawing();
    act(r, "a", 0, { type: "gotIt", seat: 1 });
    expect(r.state.drawerDevice).toBeDefined();
    clock += 10_000;
    r.tick();
    expect(r.state.drawerDevice).toBeUndefined();
  });
});

describe("kittens (ruling 5)", () => {
  it("a kitten device drawing sees two Easy words and scores 1", () => {
    const r = family();
    r.setKitten("a", true);
    const choices = viewOf(r, "a").choices as { easy: string; tricky: string };
    const level = (word: string) => WORDS.find((w) => w.word === word)?.level;
    expect([level(choices.easy), level(choices.tricky)]).toEqual(["easy", "easy"]);
    expect(choices.easy).not.toBe(choices.tricky);
    // Another device of the same player is no kitten's.
    expect(level((viewOf(r, "a2").choices as { tricky: string }).tricky)).toBe("tricky");
    act(r, "a", 0, { type: "choose", level: "tricky" });
    expect(game(r).level).toBe("easy");
    expect(viewOf(r, "a").word).toBe(choices.tricky);
    act(r, "a", 0, { type: "gotIt", seat: 1 });
    expect(game(r).scores).toEqual([1, 1]);
  });

  it("a device that is no kitten any more picks a Tricky word", () => {
    const r = family();
    r.setKitten("a", true);
    r.setKitten("a", false);
    act(r, "a", 0, { type: "choose", level: "tricky" });
    expect(game(r).level).toBe("tricky");
  });

  it("remembers what it was last told", () => {
    const r = family();
    expect(r.isKitten("a")).toBe(false);
    r.setKitten("a", true);
    expect(r.isKitten("a")).toBe(true);
  });

  it("only a game that changes for kittens wants the age band", () => {
    expect(family().wantsAgeBands()).toBe(true);
    expect(new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng).wantsAgeBands()).toBe(false);
  });
});

describe("near keys (design §5.2, ruling 12)", () => {
  const PERIOD = 30_000;
  /** A fresh key at every mint: a counter, unlike the suite's fixed rng. */
  const counting = () => {
    let n = 0;
    return () => ((n++ * 7) % 26) / 26 + 0.001;
  };
  const near = (r: Room, device = "tv") => r.snapshotFor(device).room.near;
  const keyOf = (r: Room) => (near(r) as { key: string }).key;
  const toScreen = (out: Outbound[]) => out.filter((o) => o.to === "tv" && o.message.t === "snapshot");

  /** A Purrtrait lobby made by its TV ("tv"), which is connected; "a" sits. */
  function lobby(speed = 1): Room {
    const state = RoomCore.create<PurrState>("BCDFG", "", clock, undefined, undefined, "purrtrait", "tv");
    const r = new RoomCore<PurrState>(state, () => clock, counting(), undefined, speed, { games: ["cat-tower", "purrtrait"], tv: true, streaks: true });
    r.connect("tv");
    r.connect("a");
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    return r;
  }

  it("only the screen's snapshot carries near: the key, the typed code and when it changes", () => {
    const r = lobby();
    const n = near(r);
    expect(n).toEqual({ key: expect.stringMatching(/^[BCDFGHJKLMNPQRTVWXZ2346789]{8}$/), code: `BCDFG${keyOf(r).slice(0, 3)}`, expiresIn: PERIOD });
    expect(near(r, "a")).toBeUndefined();
    expect(near(r, "stranger")).toBeUndefined();
    clock += 10_000;
    expect(near(r)?.expiresIn).toBe(20_000);
    expect(r.nextAlarm()).toBe(T0 + PERIOD);
  });

  it("a new key every 30 s goes to the screen; the current and the previous are good, each for 60 s at most", () => {
    const r = lobby();
    const k0 = keyOf(r);
    clock = T0 + PERIOD;
    const out = r.tick();
    const k1 = keyOf(r);
    expect(k1).not.toBe(k0);
    expect(toScreen(out)).toHaveLength(1);
    expect(out.filter((o) => o.to === "a")).toEqual([]);
    expect(r.nearLive(k0)).toBe(true);
    expect(r.nearLive(k1)).toBe(true);
    expect(r.nearLive(`BCDFG${k0.slice(0, 3)}`)).toBe(true);
    expect(r.nearLive(k1.toLowerCase())).toBe(true);
    clock = T0 + 2 * PERIOD;
    r.tick();
    const k2 = keyOf(r);
    expect(r.nearLive(k0)).toBe(false);
    expect(r.nearLive(`BCDFG${k0.slice(0, 3)}`)).toBe(false);
    expect([r.nearLive(k1), r.nearLive(k2)]).toEqual([true, true]);
    expect(r.nearLive(null)).toBe(false);
    expect(r.nearLive("BCDFG")).toBe(false);
    // Another room's code with the right two... three characters is still wrong.
    expect(r.nearLive(`BCDFH${k2.slice(0, 3)}`)).toBe(false);
  });

  it("a late alarm never stretches a key past 60 s, and never brings an old one back", () => {
    const r = lobby();
    const k0 = keyOf(r);
    clock = T0 + 70_000;
    expect(r.nearLive(k0)).toBe(false);
    r.tick();
    expect(r.nearLive(k0)).toBe(false);
    expect(r.state.nearKeys?.map((k) => k.key)).toEqual([keyOf(r)]);
  });

  it("no screen connected, no new keys and no alarm for them; it mints again as the screen comes back", () => {
    const r = lobby();
    const k0 = keyOf(r);
    r.disconnect("tv");
    clock = T0 + SCREEN_GRACE_MS + 1;
    r.tick();
    expect(r.nextAlarm()).toBeGreaterThan(T0 + 2 * PERIOD);
    clock = T0 + 5 * PERIOD;
    expect(r.tick().filter((o) => o.message.t === "snapshot" && o.to === "tv")).toEqual([]);
    expect(r.nearLive(k0)).toBe(false);
    r.connect("tv");
    expect(keyOf(r)).not.toBe(k0);
    expect(r.nearLive(keyOf(r))).toBe(true);
  });

  it("a phone that connects while a key is overdue (a late alarm) brings the screen its new one", () => {
    const r = lobby();
    const k0 = keyOf(r);
    clock = T0 + PERIOD + 5;
    const out = r.connect("b");
    expect(keyOf(r)).not.toBe(k0);
    expect(toScreen(out)).toHaveLength(1);
    expect(r.connect("c").filter((o) => o.to === "tv")).toEqual([]);
  });

  it("who needs a key: a member never, a stranger always, a screen's ask never", () => {
    const r = lobby();
    const key = keyOf(r);
    expect(r.knows("a", null, false)).toBe("member");
    expect(r.knows("tv", null, true)).toBe("member");
    expect(r.knows("b", null, false)).toBe("not_near");
    expect(r.knows("b", "BCDFG", false)).toBe("not_near");
    expect(r.knows("b", key, false)).toBe("exists");
    expect(r.knows("b", `BCDFG${key.slice(0, 3)}`, false)).toBe("exists");
    // A device that asks to be a screen isn't let in by a key: the room says it is no screen.
    expect(r.knows("b", null, true)).toBe("exists");
    // Once it has been here, it is a member and reconnects with no key.
    r.connect("b");
    expect(r.knows("b", null, false)).toBe("member");
  });

  it("a room built from storage keeps accepting the key the TV shows", () => {
    const r = lobby();
    const key = keyOf(r);
    clock += 5_000;
    const back = rebuild(r);
    expect(back.nearLive(key)).toBe(true);
    expect(back.knows("b", key, false)).toBe("exists");
  });

  it("over: no near, and no key is good", () => {
    const r = started();
    const key = (near(r) as { key: string }).key;
    act(r, "a", 0, { type: "forfeit" });
    expect(r.state.gameState && game(r).phase).toBe("over");
    expect(r.state.status).toBe("over");
    expect(near(r)).toBeUndefined();
    expect(r.nearLive(key)).toBe(false);
    expect(r.knows("z", key, false)).toBe("not_near");
  });

  it("a Cat Tower table has no near keys and asks for none", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "", clock, undefined, undefined, "cat-tower", "tv"), () => clock, rng, undefined, 1, { streaks: false, tv: true });
    r.connect("tv");
    expect(r.snapshotFor("tv").room.near).toBeUndefined();
    expect(r.state.nearKeys).toBeUndefined();
    expect(r.knows("b", null, false)).toBe("exists");
    expect(r.sameRoom()).toBe(false);
  });

  it("an app that can't draw the game is no wrong guess: the room tells it there is no such table", () => {
    const r = lobby();
    expect(r.knows("b", null, false, ["cat-tower", "tiles"])).toBe("exists");
    expect(r.knows("b", null, false, ["cat-tower", "purrtrait"])).toBe("not_near");
  });

  it("wrong guesses before any key are counted too, and nothing is let in", () => {
    const state = RoomCore.create<PurrState>("BCDFG", "", clock, undefined, undefined, "purrtrait", "tv");
    const r = new RoomCore<PurrState>(state, () => clock, counting(), undefined, 1, { games: ["cat-tower", "purrtrait"], tv: true, streaks: true });
    r.noteNearMiss();
    r.noteNearMiss();
    expect(r.state.nearMisses).toEqual({ at: 0, count: 2 });
    expect(r.nearLive("BCDFGHJK")).toBe(false);
  });

  it("30 wrong guesses in one key's time close the typed code until the next key; the QR's key still works", () => {
    const r = lobby();
    const key = keyOf(r);
    const typed = `BCDFG${key.slice(0, 3)}`;
    for (let i = 0; i < NEAR_TYPED_MISSES - 1; i++) r.noteNearMiss();
    expect(r.nearLive(typed)).toBe(true);
    r.noteNearMiss();
    expect(r.nearLive(typed)).toBe(false);
    expect(r.knows("b", typed, false)).toBe("not_near");
    expect(r.nearLive(key)).toBe(true);
    // The next key opens typing again, for the new key and the old.
    clock = T0 + PERIOD;
    r.tick();
    expect(r.nearLive(typed)).toBe(true);
    expect(r.nearLive(`BCDFG${keyOf(r).slice(0, 3)}`)).toBe(true);
    expect(r.state.nearMisses).toBeUndefined();
    // The count survives a rebuild from storage.
    for (let i = 0; i < NEAR_TYPED_MISSES; i++) r.noteNearMiss();
    expect(rebuild(r).nearLive(typed)).toBe(false);
  });

  it("Play again: the old table's devices are members of the new one, with no key", () => {
    const r = started();
    r.connect("watcher");
    act(r, "a", 0, { type: "forfeit" });
    expect(r.state.status).toBe("over");
    r.handle("b", { t: "rematch" });
    const spec = r.drainRematch();
    expect(spec?.members?.sort()).toEqual(["a", "b", "watcher"]);
    const next = new RoomCore<PurrState>(RoomCore.rematchState<PurrState>("CDFGH", spec as NonNullable<typeof spec>, clock), () => clock, counting(), undefined, 1, {
      games: ["cat-tower", "purrtrait"],
      tv: true,
      streaks: true,
    });
    for (const id of ["a", "b", "watcher"]) expect(next.knows(id, null, false)).toBe("member");
    expect(next.knows("tv", null, true)).toBe("member");
    expect(next.knows("stranger", null, false)).toBe("not_near");
    // And again: a member who never came back to the second table is still one at the third.
    next.connect("tv");
    next.connect("a");
    next.connect("b");
    next.deal();
    act(next, "a", next.state.seats.findIndex((s) => s.deviceId === "a"), { type: "forfeit" });
    next.handle("b", { t: "rematch" });
    expect(next.drainRematch()?.members?.sort()).toEqual(["a", "b", "watcher"]);
    // Only a same-room table carries them.
    const tower = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    tower.connect("a");
    expect(tower.state.members).toBeUndefined();
  });

  it("linking a TV swaps the screen: the old one is no member any more, and the table stays shown", () => {
    const r = lobby();
    expect(r.addScreen("tv2").replaced).toEqual(["tv"]);
    expect(r.state.screens).toEqual(["tv2"]);
    expect(r.isScreen("tv")).toBe(false);
    expect(r.state.devices.tv).toBeUndefined();
    expect(r.knows("tv", null, true)).toBe("exists");
    expect(r.knows("tv", null, false)).toBe("not_near");
    // Within the grace the phones still show the TV layout, waiting for the new one.
    expect(r.snapshotFor("a").room.screen).toBe(true);
    expect(r.addScreen("tv2")).toEqual({ replaced: [], out: [] });
    r.connect("tv2");
    expect(near(r, "tv2")).toBeDefined();
    expect(near(r, "tv")).toBeUndefined();
  });

  it("a Cat Tower table keeps every screen it is linked to", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "", clock, undefined, undefined, "cat-tower", "tv"), () => clock, rng, undefined, 1, { streaks: false, tv: true });
    expect(r.addScreen("tv2")).toEqual({ replaced: [], out: [] });
    expect(r.state.screens).toEqual(["tv", "tv2"]);
  });
});

/* The host's seat menu, the host's role, and what a same-room table refuses (design §10.2, rulings 10, 11, 14, 17). */

const FEATURES = { games: ["cat-tower", "purrtrait"] as const, tv: true, streaks: true, live: true, nudge: true };
const players = (n: number) => ({ [person(n).id]: player(n) });

/** A lobby with its TV: "a" (the host), "b" and "c" sit in seats 0 to 2, each a signed-in player. */
function lobby3(game?: RoomGame<PurrState>): Room {
  const state = RoomCore.create<PurrState>("BCDFG", "a", clock, undefined, undefined, "purrtrait");
  const r = new RoomCore<PurrState>(state, () => clock, rng, game, 1, FEATURES);
  r.addScreen("tv");
  r.connect("tv");
  ["a", "b", "c"].forEach((d, i) => r.connect(d, players(i + 1)));
  ["a", "b", "c"].forEach((d, i) => {
    if (i === 2) r.handle("a", { t: "configure", seat: 2, kind: "open" });
    expect(errorsOf(r.handle(d, { t: "claim", seat: i, person: person(i + 1) }))).toEqual([]);
  });
  return r;
}

/** `lobby3`, started: seat 0 ("a") draws first. */
function game3(g?: RoomGame<PurrState>): Room {
  const r = lobby3(g);
  expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
  return r;
}

const remove = (r: Room, device: string, seat: number) => r.handle(device, { t: "remove", seat } as ClientMessage);
const eventsOf = (out: Outbound[], to: string) =>
  out.flatMap((o) => (o.to === to && o.message.t === "event" ? [o.message.event] : [])) as { kind: string; event?: { type: string; reason?: string } }[];

/** Plays the game to its end: each drawer picks Easy and the next seat in guesses it. */
function playOut(r: Room, deviceOf: (seat: number) => string, before?: () => void): void {
  for (let step = 0; step < 500 && game(r).phase !== "over"; step++) {
    const s = game(r);
    const drawer = s.drawer as number;
    if (s.phase === "choosing") act(r, deviceOf(drawer), drawer, { type: "choose", level: "easy" });
    else if (s.phase === "drawing") {
      const guesser = [1, 2, 3, 4, 5, 6, 7, 8, 9].map((k) => (drawer + k) % s.seats).find((g) => !s.out[g]) as number;
      act(r, deviceOf(drawer), drawer, { type: "gotIt", seat: guesser });
    } else {
      before?.();
      clock += 10_000;
      r.tick();
    }
  }
  expect(game(r).phase).toBe("over");
}

describe("remove (design §10.2, ruling 10)", () => {
  it("remove in the lobby opens the seat and the device is refused after", () => {
    const r = lobby3();
    const seq = r.state.seq;
    const out = remove(r, "a", 2);
    expect(errorsOf(out)).toEqual([]);
    expect(r.state.seats[2]).toEqual({ kind: "open" });
    expect(r.state.removed).toEqual({ devices: ["c"], players: [player(3)] });
    expect(r.isRemoved("c")).toBe(true);
    // Gone from the room: it hears nothing more, and everyone else sees the open seat.
    expect(r.state.devices.c).toBeUndefined();
    expect(out.some((o) => o.to === "c")).toBe(false);
    expect(r.state.seq).toBeGreaterThan(seq);
    expect(out.filter((o) => o.message.t === "snapshot").map((o) => o.to).sort()).toEqual(["a", "b", "tv"]);
    // It needs no near key to be told it was removed (the room refuses it), and is never counted.
    expect(r.knows("c", null, false)).toBe("member");
    // Its player can't sit again from another device.
    r.connect("c2", players(3));
    expect(errorsOf(r.handle("c2", { t: "claim", seat: 2, person: person(3) }))).toEqual(["removed"]);
    // Somebody else can.
    r.connect("d", players(4));
    expect(errorsOf(r.handle("d", { t: "claim", seat: 2, person: person(4) }))).toEqual([]);
    // Kept in storage: a woken room still knows.
    expect(rebuild(r).isRemoved("c")).toBe(true);
  });

  it("remove in a game skips the seat; Play again keeps it out", () => {
    const r = game3();
    // Seat 1 ("b") is drawing when the host removes it: the turn ends with no points, as if it left.
    act(r, "a", 0, { type: "choose", level: "easy" });
    act(r, "a", 0, { type: "gotIt", seat: 1 });
    clock += 10_000;
    r.tick();
    act(r, "b", 1, { type: "choose", level: "easy" });
    expect(game(r)).toMatchObject({ phase: "drawing", drawer: 1 });
    const out = remove(r, "a", 1);
    expect(errorsOf(out)).toEqual([]);
    expect(eventsOf(out, "tv").find((e) => e.kind === "purrtrait" && e.event?.type === "missed")?.event).toMatchObject({ type: "missed", reason: "left" });
    expect(game(r).out[1]).toBe(true);
    expect(game(r).phase).toBe("reveal");
    expect(r.state.removed).toEqual({ devices: ["b"], players: [player(2)] });
    // From then on the seat is skipped: it never draws, and never guesses.
    const score = game(r).scores[1];
    playOut(r, (seat) => {
      expect(seat).not.toBe(1);
      return ["a", "b", "c"][seat] as string;
    });
    expect(game(r).scores[1]).toBe(score);
    // Play again leaves the removed seat and device out, and carries the list.
    r.handle("c", { t: "rematch" });
    const spec = r.drainRematch() as NonNullable<ReturnType<Room["drainRematch"]>>;
    expect(spec.seats.map((s) => s.deviceId)).toEqual(["c", "a"]);
    expect(spec.members?.sort()).toEqual(["a", "c"]);
    expect(spec.removed).toEqual({ devices: ["b"], players: [player(2)] });
    const next = new RoomCore<PurrState>(RoomCore.rematchState<PurrState>("CDFGH", spec, clock), () => clock, rng, undefined, 1, FEATURES);
    expect(next.state.removed).toEqual(spec.removed);
    expect(next.isRemoved("b")).toBe(true);
    // Not even into a seat opened for them on the new table, from another device.
    next.connect("c", players(3));
    expect(errorsOf(next.handle("c", { t: "configure", seat: 2, kind: "open" }))).toEqual([]);
    next.connect("b2", players(2));
    expect(errorsOf(next.handle("b2", { t: "claim", seat: 2, person: person(2) }))).toEqual(["removed"]);
  });

  it("a removed player back on another device controls nothing, can't deal Play again and isn't carried to it", () => {
    const r = game3();
    expect(errorsOf(remove(r, "a", 2))).toEqual([]);
    // Player 3 comes back mid-game on device "y" (signed in there too).
    r.connect("y", players(3));
    expect(r.controlledSeats("y")).toEqual([]);
    expect(r.heldSeats("y")).toEqual([]);
    expect(r.mayLink("y")).toBe(false);
    expect(r.snapshotFor("y").room.seats.some((s) => s.yours)).toBe(false);
    expect(errorsOf(act(r, "y", 2, { type: "forfeit" }))).toEqual(["not_your_seat"]);
    // The room turns such a device away at its next upgrade; a device that speaks for someone still seated it doesn't.
    expect(r.turnedAway("y", players(3))).toBe(true);
    expect(r.turnedAway("c", {})).toBe(true);
    expect(r.turnedAway("b", players(2))).toBe(false);
    expect(r.turnedAway("y", { ...players(3), ...players(2) })).toBe(false);
    expect(r.turnedAway("w", {})).toBe(false);
    // Nobody removed: nobody turned away.
    expect(game3().turnedAway("y", players(3))).toBe(false);
    act(r, "b", 1, { type: "forfeit" });
    expect(r.state.status).toBe("over");
    expect(errorsOf(r.handle("y", { t: "rematch" }))).toEqual(["not_seated"]);
    expect(r.state.rematch).toBeUndefined();
    r.handle("a", { t: "rematch" });
    const spec = r.drainRematch() as NonNullable<ReturnType<Room["drainRematch"]>>;
    expect(spec.members?.sort()).toEqual(["a", "b"]);
    expect(spec.hostDeviceId).toBe("a");
  });

  it("a guesser's forfeit, and a remove in a game, move seq with the snapshots they send", () => {
    const r = game3();
    // Seat 0 ("a") is choosing; seat 2 leaves as a guesser: no turn ends, so the game says nothing.
    const before = r.state.seq;
    const left = act(r, "c", 2, { type: "forfeit" });
    expect(errorsOf(left)).toEqual([]);
    expect(game(r).out[2]).toBe(true);
    expect(r.state.seq).toBeGreaterThan(before);
    const snapSeq = (out: Outbound[]) => (out.find((o) => o.to === "a" && o.message.t === "snapshot")?.message as { seq: number }).seq;
    expect(snapSeq(left)).toBe(r.state.seq);
    // The host removes a guesser in a game: the same.
    const r2 = game3();
    const mid = r2.state.seq;
    const removed = remove(r2, "a", 2);
    expect(errorsOf(removed)).toEqual([]);
    expect(game(r2).out[2]).toBe(true);
    expect(r2.state.seq).toBeGreaterThan(mid);
    expect(snapSeq(removed)).toBe(r2.state.seq);
  });

  it("Play again keeps the host: a guest's tap doesn't make them host", () => {
    const r = game3();
    playOut(r, (seat) => ["a", "b", "c"][seat] as string);
    r.handle("c", { t: "rematch" });
    const spec = r.drainRematch() as NonNullable<ReturnType<Room["drainRematch"]>>;
    expect(spec.hostDeviceId).toBe("a");
    // At the new table the guest who tapped it still can't remove anyone; the host can.
    const next = new RoomCore<PurrState>(RoomCore.rematchState<PurrState>("CDFGH", spec, clock), () => clock, rng, undefined, 1, FEATURES);
    ["a", "b", "c"].forEach((d, i) => next.connect(d, players(i + 1)));
    expect(errorsOf(remove(next, "c", 0))).toEqual(["not_allowed"]);
    expect(errorsOf(remove(next, "a", 0))).toEqual([]);
  });

  it("Play again hands the host on (ruling 11) when no seat the host holds is dealt again", () => {
    const r = game3();
    playOut(r, (seat) => ["a", "b", "c"][seat] as string);
    // The host's phone is back with nobody signed in: it holds no seat now.
    r.connect("a", {});
    r.handle("c", { t: "rematch" });
    // The next seat after the host's, held by a person: "b", not whoever tapped.
    expect(r.drainRematch()?.hostDeviceId).toBe("b");
    // No seat's own phone holds it any more: the one who tapped, for its person, hosts.
    const r2 = game3();
    playOut(r2, (seat) => ["a", "b", "c"][seat] as string);
    ["a", "b", "c"].forEach((d) => r2.connect(d, {}));
    r2.connect("y", players(3));
    r2.handle("y", { t: "rematch" });
    expect(r2.drainRematch()?.hostDeviceId).toBe("y");
  });

  it("a shared phone whose other person left the game is still let in when one of its people is removed", () => {
    const r = lobby3();
    // "c" seats player 3 and player 4.
    r.connect("c", { ...players(3), ...players(4) });
    r.handle("a", { t: "configure", seat: 3, kind: "open" });
    expect(errorsOf(r.handle("c", { t: "claim", seat: 3, person: person(4) }))).toEqual([]);
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
    expect(errorsOf(act(r, "c", 3, { type: "forfeit" }))).toEqual([]);
    expect(errorsOf(remove(r, "a", 2))).toEqual([]);
    // Player 4's seat is out of the game, not removed: it still keeps the phone at the table.
    expect(r.state.removed).toEqual({ devices: [], players: [player(3)] });
    expect(r.state.devices.c).toBeDefined();
    expect(r.turnedAway("c", { ...players(3), ...players(4) })).toBe(false);
    expect(r.turnedAway("c")).toBe(false);
    expect(r.controlledSeats("c")).toEqual([3]);
    // Without player 4, the phone would be turned away.
    expect(r.turnedAway("c", players(3))).toBe(true);
    act(r, "b", 1, { type: "forfeit" });
    expect(r.state.status).toBe("over");
    r.handle("a", { t: "rematch" });
    expect(r.drainRematch()?.members?.sort()).toEqual(["a", "b", "c"]);
  });

  it("a removed device's seat is matched by its player when it has one", () => {
    const r = lobby3();
    // "c" holds no player of its own for seat 2 any more: the seat is player 3's, wherever they are.
    expect(errorsOf(remove(r, "a", 2))).toEqual([]);
    expect(r.state.removed).toEqual({ devices: ["c"], players: [player(3)] });
    // A guest seat (no player) on the removed device would be its device's.
    r.connect("g");
    r.handle("g", { t: "claim", seat: 2, person: person(7) });
    expect(r.controlledSeats("g")).toEqual([2]);
    // Its guest seat keeps it in, even when it also speaks for the removed player.
    expect(r.turnedAway("g", players(3))).toBe(false);
    r.state.removed = { devices: ["g"], players: [] };
    expect(r.controlledSeats("g")).toEqual([]);
    // A seat whose player is not removed stays theirs, even on a listed device.
    r.state.removed = { devices: ["b"], players: [] };
    expect(r.controlledSeats("b")).toEqual([1]);
  });

  it("Play again with too few people left after a remove is not_enough_players", () => {
    const r = started();
    expect(errorsOf(remove(r, "a", 1))).toEqual([]);
    expect(r.state.status).toBe("over");
    expect(errorsOf(r.handle("a", { t: "rematch" }))).toEqual(["not_enough_players"]);
    expect(r.drainRematch()).toBeNull();
    expect(r.state.rematch).toBeUndefined();
  });

  it("removing a seat that already left lists it, and changes nothing in the game", () => {
    const r = game3();
    act(r, "c", 2, { type: "forfeit" });
    const before = JSON.stringify(game(r));
    expect(errorsOf(remove(r, "a", 2))).toEqual([]);
    expect(JSON.stringify(game(r))).toBe(before);
    expect(r.state.removed).toEqual({ devices: ["c"], players: [player(3)] });
  });

  it("a non-host remove is not_allowed, and so is one at a table of another game", () => {
    const r = lobby3();
    expect(errorsOf(remove(r, "b", 2))).toEqual(["not_allowed"]);
    expect(errorsOf(remove(r, "tv", 2))).toEqual(["not_allowed"]);
    expect(errorsOf(remove(r, "w", 2))).toEqual(["not_allowed"]);
    expect(r.state.removed).toBeUndefined();
    // The host's own seat, an open or closed seat, or none at all: bad_seat.
    expect(errorsOf(remove(r, "a", 0))).toEqual(["bad_seat"]);
    expect(errorsOf(remove(r, "a", 3))).toEqual(["bad_seat"]);
    expect(errorsOf(remove(r, "a", 10))).toEqual(["bad_seat"]);
    const tower = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    tower.connect("a");
    tower.connect("b");
    tower.handle("a", { t: "claim", seat: 0, person: person(1) });
    tower.handle("b", { t: "claim", seat: 1, person: person(2) });
    expect(errorsOf(tower.handle("a", { t: "remove", seat: 1 } as ClientMessage))).toEqual(["not_allowed"]);
    expect(tower.state.seats[1]?.kind).toBe("human");
  });

  it("a device that holds another seat stays; only the removed player is refused", () => {
    const r = lobby3();
    // "b" also seats a second person, on the same phone.
    r.connect("b", { ...players(2), ...players(5) });
    r.handle("a", { t: "configure", seat: 3, kind: "open" });
    expect(errorsOf(r.handle("b", { t: "claim", seat: 3, person: person(5) }))).toEqual([]);
    expect(errorsOf(remove(r, "a", 1))).toEqual([]);
    expect(r.state.removed).toEqual({ devices: [], players: [player(2)] });
    expect(r.isRemoved("b")).toBe(false);
    expect(r.state.seats[3]?.kind).toBe("human");
    expect(errorsOf(r.handle("b", { t: "claim", seat: 1, person: person(2) }))).toEqual(["removed"]);
  });
});

describe("the host's role (ruling 11)", () => {
  const host = (r: Room) => r.state.hostDeviceId;

  it("the host leaving hands the role to the next seated person", () => {
    const r = lobby3();
    expect(errorsOf(r.handle("a", { t: "leave", seat: 0 }))).toEqual([]);
    expect(host(r)).toBe("b");
    expect(r.snapshotFor("b").room.youAreHost).toBe(true);
    expect(r.snapshotFor("a").room.youAreHost).toBe(false);
    // In seat order from the seat that left, round to the start.
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    r.handle("b", { t: "leave", seat: 1 });
    expect(host(r)).toBe("c");
    r.handle("c", { t: "leave", seat: 2 });
    expect(host(r)).toBe("a");
    // Nobody seated: no host, and the next phone to sit is it.
    r.handle("a", { t: "leave", seat: 0 });
    expect(host(r)).toBe("");
    r.handle("c", { t: "claim", seat: 2, person: person(3) });
    expect(host(r)).toBe("c");
  });

  it("in a game, the host's seat leaving hands the role to the next seat still in", () => {
    const r = game3();
    act(r, "b", 1, { type: "forfeit" });
    expect(host(r)).toBe("a");
    expect(errorsOf(act(r, "a", 0, { type: "forfeit" }))).toEqual([]);
    // Seat 1 is out, so seat 2.
    expect(host(r)).toBe("c");
    expect(r.state.status).toBe("over");
  });

  it("a host with another seat still in keeps the role, and other games keep their host", () => {
    const r = lobby3();
    r.connect("a", { ...players(1), ...players(6) });
    r.handle("a", { t: "configure", seat: 3, kind: "open" });
    r.handle("a", { t: "claim", seat: 3, person: person(6) });
    r.handle("a", { t: "leave", seat: 0 });
    expect(host(r)).toBe("a");
    const tower = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    tower.connect("a");
    tower.connect("b");
    tower.handle("a", { t: "claim", seat: 0, person: person(1) });
    tower.handle("b", { t: "claim", seat: 1, person: person(2) });
    tower.handle("a", { t: "leave", seat: 0 });
    expect(tower.state.hostDeviceId).toBe("a");
  });
});

describe("the drawer's second device (review focus 3)", () => {
  it("the drawer's second device gets the guesser view after the pick and its ink is dropped", () => {
    const r = drawing();
    const turn = turnOf(r);
    // The family iPad sees what a guesser sees: no choices, no word, not its turn to draw.
    expect(viewOf(r, "a2")).toEqual(viewOf(r, "w"));
    expect(viewOf(r, "a2").choices).toBeUndefined();
    // The drawer's lines reach the screen and the drawer's own device, never the iPad.
    expect(inkTo(ink(r, "a", 0, turn, [dot(0)]))).toEqual(["tv", "a"]);
    // The iPad's ink is dropped: nothing relayed, nothing kept.
    expect(ink(r, "a2", 0, turn, [dot(1)])).toEqual([]);
    expect(only(r.connect("tv"), "inkSync").map((o) => (o.message as { ops: unknown[] }).ops)).toEqual([[dot(0)]]);
    // Reconnecting, it gets no drawing.
    expect(only(r.connect("a2", { [person(1).id]: player(1) }), "inkSync")).toEqual([]);
  });
});

describe("what a same-room table refuses (ruling 14)", () => {
  it("moveSeat, claimMove, nudge, retire and bot seats are not_allowed", () => {
    const r = lobby3();
    expect(errorsOf(r.handle("b", { t: "moveSeat", seat: 1 }))).toEqual(["not_allowed"]);
    expect(Object.keys(r.state.moveCodes)).toEqual([]);
    expect(errorsOf(r.handle("w", { t: "claimMove", code: "BCDFGH" }))).toEqual(["not_allowed"]);
    r.handle("a", { t: "configure", seat: 3, kind: "open" });
    expect(errorsOf(r.handle("a", { t: "configure", seat: 3, kind: "bot" }))).toEqual(["not_allowed"]);
    expect(r.state.seats[3]?.kind).toBe("open");
    expect(errorsOf(r.handle("a", { t: "configure", seat: 3, kind: "closed" }))).toEqual([]);
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
    // Long after the turn began: still nothing to nudge or retire.
    clock += 4 * 24 * 60 * 60_000;
    expect(errorsOf(r.handle("b", { t: "nudge", seat: 0 }))).toEqual(["not_allowed"]);
    expect(errorsOf(r.handle("b", { t: "retire", seat: 0 }))).toEqual(["not_allowed"]);
    expect(r.snapshotFor("b").room.nudge).toBeUndefined();
    expect(r.snapshotFor("b").room.retire).toBeUndefined();
    expect(game(r).out).toEqual([false, false, false]);
  });

  it("no push, live or invite intent is queued, through a whole game", () => {
    /** Every seat's phone goes to the background between turns, one by one, so a Cat Tower table would push and go live. */
    const away = (r: Room) => () => {
      for (const d of ["a", "b", "c"]) r.handle(d, { t: "presence", state: "background" });
    };
    const drained = (r: Room) => ({
      push: r.drainPushIntents(),
      live: r.drainLiveIntents(),
      nudge: r.drainNudgeIntents(),
      retire: r.drainRetireIntents(),
    });
    const r = game3();
    away(r)();
    playOut(r, (seat) => ["a", "b", "c"][seat] as string, away(r));
    for (const d of ["b", "c"]) r.handle(d, { t: "presence", state: "background" });
    clock += 4 * 24 * 60 * 60_000;
    r.tick();
    expect(drained(r)).toEqual({ push: [], live: [], nudge: [], retire: [] });
    expect(r.state.live).toBeUndefined();
    // The same game at a table that isn't same-room queues both: the filter is what keeps them out.
    const open = game3({ ...(purrtrait as unknown as RoomGame<PurrState>), sameRoom: false });
    away(open)();
    playOut(open, (seat) => ["a", "b", "c"][seat] as string, away(open));
    const control = drained(open);
    expect(control.push.length).toBeGreaterThan(0);
    expect(control.live.length).toBeGreaterThan(0);
  });
});

describe("start (ruling 17)", () => {
  it("start needs the screen (no_screen) and 2 seats filled (not_enough_players); open seats don't hold it up", () => {
    const state = RoomCore.create<PurrState>("BCDFG", "", clock, undefined, undefined, "purrtrait", "tv");
    const r = new RoomCore<PurrState>(state, () => clock, rng, undefined, 1, FEATURES);
    r.connect("a");
    r.connect("b");
    r.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual(["not_enough_players"]);
    r.handle("b", { t: "claim", seat: 1, person: person(2) });
    // A TV-made table whose TV never came: no screen.
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual(["no_screen"]);
    r.connect("tv");
    r.disconnect("tv");
    // Within the grace the table is still shown, after it not.
    clock += SCREEN_GRACE_MS;
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual(["no_screen"]);
    r.connect("tv");
    // An open seat waiting for a phone is dropped at the start.
    r.handle("a", { t: "configure", seat: 2, kind: "open" });
    expect(errorsOf(r.handle("a", { t: "start" }))).toEqual([]);
    expect(game(r).seats).toBe(2);
    expect(r.state.seats).toHaveLength(2);
  });
});
