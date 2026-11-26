import { beforeEach, describe, expect, it } from "vitest";

import { purrtrait } from "../games/purrtrait";
import { parseClientMessage, type ClientMessage, type Person, type ServerMessage } from "../protocol";
import { WORDS } from "../purrtrait/words";

import { RoomCore, SCREEN_GRACE_MS, STALL_END_MS, type Outbound } from "./core";

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
    expect(r.nextAlarm()).toBe(T0 + 70_000);
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
