import { describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { parseClientMessage } from "../protocol";
import { card } from "../rules/cards";

import { CLEANUP_AFTER_MS, GAME_CLEANUP_AFTER_MS, RETIRE_AFTER_MS, RETIRE_WARNING_MS, RoomCore, type Outbound } from "./core";

import type { Person, ServerMessage } from "../protocol";
import type { CatTowerState, GameEvent } from "../rules/engine";

const T0 = 1_000_000;
const DAY = 24 * 60 * 60_000;
const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });
const playerOf = (seat: number) => `p_${String.fromCharCode(65 + seat).repeat(22)}`;

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Table = { r: RoomCore; clock: { now: number }; seats: string[] };

/**
 * A started table: `seats[i]` is the device holding seat i, or "bot". A device may hold several
 * seats (a shared phone). Every person has a player unless `players` is false. Seat 0 deals, so
 * seat 1 plays first.
 */
function table(seats: string[], opts: { players?: boolean; speed?: number } = {}): Table {
  const clock = { now: T0 };
  const host = seats[0] as string;
  const r = new RoomCore(RoomCore.create("BCDFG", host, T0), () => clock.now, () => 0.25, catTower, opts.speed ?? 1, { streaks: true });
  for (const device of new Set(seats)) {
    if (device === "bot") continue;
    const mine = seats.flatMap((d, seat) => (d === device && opts.players !== false ? [[person(seat + 1).id, playerOf(seat)]] : []));
    r.connect(device, Object.fromEntries(mine) as Record<string, string>);
  }
  seats.forEach((device, seat) => {
    if (device === "bot") r.handle(host, { t: "configure", seat, kind: "bot" });
    else {
      if (seat >= 2) r.handle(host, { t: "configure", seat, kind: "open" });
      r.handle(device, { t: "claim", seat, person: person(seat + 1) });
    }
  });
  for (let seat = seats.length; seat < 6; seat++) r.handle(host, { t: "configure", seat, kind: "closed" });
  expect(errors(r.handle(host, { t: "start" }))).toEqual([]);
  r.drainStreakIntents();
  return { r, clock, seats };
}

const game = (r: RoomCore) => r.state.gameState as CatTowerState;
const turn = (t: Table) => game(t.r).turn;
const errors = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const retire = (t: Table, device: string, seat: number) => t.r.handle(device, { t: "retire", seat });
const snapshot = (t: Table, device: string) => t.r.snapshotFor(device) as Snapshot;
const gameEvents = (out: Outbound[], to: string): GameEvent[] =>
  out.flatMap((o) => (o.to === to && o.message.t === "event" && o.message.event.kind === "game" ? [o.message.event.event] : []));

/** The seat holding the move draws and discards a number card. */
function play(t: Table): void {
  const seat = turn(t);
  const device = t.seats[seat] as string;
  t.r.handle(device, { t: "act", seat, action: { type: "draw", from: "deck" } });
  const pick = (game(t.r).hands[seat] as number[]).find((id) => card(id).kind === "number") as number;
  expect(errors(t.r.handle(device, { t: "act", seat, action: { type: "discard", card: pick } }))).toEqual([]);
}

const SIX = ["d0", "d1", "d2", "d3", "d4", "d5"];

describe("retiring a stalled seat", () => {
  it("two players: not before three days, then the other one ends the game by retiring the seat", () => {
    const t = table(["phone", "tablet"]);
    expect(turn(t)).toBe(1);
    expect(snapshot(t, "phone").room.retire).toEqual({ seat: 1, wait: RETIRE_AFTER_MS });
    // The one whose move it is has nobody to retire.
    expect(snapshot(t, "tablet").room.retire).toBeUndefined();

    t.clock.now = T0 + RETIRE_AFTER_MS - 1;
    expect(snapshot(t, "phone").room.retire).toEqual({ seat: 1, wait: 1 });
    expect(errors(retire(t, "phone", 1))).toEqual(["too_soon"]);
    expect(game(t.r).forfeited).toBeUndefined();

    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(snapshot(t, "phone").room.retire).toEqual({ seat: 1, wait: 0 });
    const out = retire(t, "phone", 1);
    expect(errors(out)).toEqual([]);
    expect(gameEvents(out, "tablet")).toEqual([
      { kind: "forfeited", seat: 1 },
      { kind: "gameOver", winners: [0], reason: "forfeit" },
    ]);
    // Ranks: the retired seat is out and last, the one who stayed wins.
    expect(game(t.r)).toMatchObject({ status: "gameOver", winners: [0], forfeited: [false, true], endReason: "forfeit" });
    expect(t.r.state.status).toBe("over");
    expect(snapshot(t, "tablet").room.game).toMatchObject({ forfeited: [false, true], winners: [0] });
    expect(snapshot(t, "phone").room.retire).toBeUndefined();

    // The holder hears who did it; the pairs hear the table is over for them, with no turn counted.
    expect(t.r.drainRetireIntents()).toEqual([
      {
        kind: "done",
        playerId: playerOf(1),
        seat: 1,
        personName: "Cat 2",
        tableName: t.r.state.name,
        code: "BCDFG",
        from: { name: "Cat 1", cat: 1 },
        fromPlayer: playerOf(0),
      },
    ]);
    expect(t.r.drainStreakIntents()).toMatchObject([{ by: null, over: true, out: [playerOf(1)] }]);
  });

  it("only the seat holding the move, never your own, a bot's or a shared phone's other seat", () => {
    const t = table(["phone", "tablet", "phone", "bot", "pad"]);
    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(turn(t)).toBe(1);
    expect(errors(retire(t, "phone", 4))).toEqual(["not_their_turn"]);
    expect(errors(retire(t, "tablet", 1))).toEqual(["bad_seat"]);
    expect(errors(retire(t, "phone", 3))).toEqual(["bad_seat"]);
    expect(errors(retire(t, "phone", 9))).toEqual(["bad_seat"]);
    expect(errors(retire(t, "stranger", 1))).toEqual(["not_seated"]);
    expect(game(t.r).forfeited).toBeUndefined();

    // Seat 2's move on the shared phone: its other seat (0) can't retire it, the pad can.
    play(t);
    expect(turn(t)).toBe(2);
    t.clock.now += RETIRE_AFTER_MS;
    expect(snapshot(t, "phone").room.retire).toBeUndefined();
    expect(errors(retire(t, "phone", 2))).toEqual(["bad_seat"]);
    expect(errors(retire(t, "pad", 2))).toEqual([]);
    expect(game(t.r).forfeited).toEqual([false, false, true, false, false]);
    expect(game(t.r).status).toBe("playing");
  });

  it("someone who forfeited can't retire anyone, and a finished or unstarted table has nothing to retire", () => {
    const t = table(["phone", "tablet", "pad"]);
    t.r.handle("phone", { t: "act", seat: 0, action: { type: "forfeit" } });
    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(snapshot(t, "phone").room.retire).toBeUndefined();
    expect(errors(retire(t, "phone", 1))).toEqual(["not_seated"]);
    expect(errors(retire(t, "pad", 1))).toEqual([]);
    expect(t.r.state.status).toBe("over");
    expect(errors(retire(t, "pad", 1))).toEqual(["not_playing"]);

    const lobby = new RoomCore(RoomCore.create("BCDFG", "phone", T0), () => T0, () => 0.25);
    lobby.connect("phone");
    expect(errors(lobby.handle("phone", { t: "retire", seat: 1 }))).toEqual(["not_playing"]);
  });

  it("six players: one tap retires the seat, the game goes on without it, and the last one left wins", () => {
    const t = table(SIX);
    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(turn(t)).toBe(1);
    // Anyone else still in the game may, with no vote.
    for (const device of ["d0", "d2", "d3", "d4", "d5"]) expect(snapshot(t, device).room.retire).toEqual({ seat: 1, wait: 0 });
    const out = retire(t, "d4", 1);
    expect(errors(out)).toEqual([]);
    expect(gameEvents(out, "d0")).toEqual([
      { kind: "forfeited", seat: 1 },
      { kind: "turn", seat: 2 },
    ]);
    expect(game(t.r)).toMatchObject({ status: "playing", turn: 2, forfeited: [false, true, false, false, false, false] });
    expect(t.r.drainRetireIntents()).toMatchObject([{ kind: "done", playerId: playerOf(1), from: { name: "Cat 5" }, fromPlayer: playerOf(4) }]);
    expect(t.r.drainStreakIntents()).toMatchObject([{ by: null, over: false, out: [playerOf(1)] }]);

    // The new turn starts its own three days.
    expect(snapshot(t, "d0").room.retire).toEqual({ seat: 2, wait: RETIRE_AFTER_MS });
    expect(errors(retire(t, "d0", 2))).toEqual(["too_soon"]);
    // The retired seat can't act, and nobody can retire it twice.
    expect(errors(t.r.handle("d1", { t: "act", seat: 1, action: { type: "forfeit" } }))).toEqual(["forfeited"]);
    expect(snapshot(t, "d1").room.retire).toBeUndefined();

    // A lap of the table passes it over.
    const order: number[] = [];
    for (let i = 0; i < 6; i++) {
      order.push(turn(t));
      play(t);
    }
    expect(order).toEqual([2, 3, 4, 5, 0, 2]);

    // The rest stall one by one: each retired in turn, last places all, until one is left.
    for (const seat of [3, 4, 5, 0]) {
      expect(turn(t)).toBe(seat);
      t.clock.now += RETIRE_AFTER_MS;
      expect(errors(retire(t, "d2", seat))).toEqual([]);
    }
    expect(game(t.r)).toMatchObject({
      status: "gameOver",
      winners: [2],
      endReason: "forfeit",
      forfeited: [true, true, false, true, true, true],
    });
    expect(t.r.state.status).toBe("over");
  });

  it("drawing a card doesn't restart the wait: the turn is the same one", () => {
    const t = table(["phone", "tablet"]);
    t.clock.now = T0 + 2 * DAY;
    t.r.handle("tablet", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(t.r.waitingSince()).toBe(T0);
    expect(errors(retire(t, "phone", 1))).toEqual([]);
  });

  it("a seat with no player is retired with no push, and the dev speed shortens the wait", () => {
    const t = table(["phone", "tablet"], { players: false, speed: 100 });
    t.clock.now = T0 + RETIRE_AFTER_MS / 100;
    t.r.tick();
    expect(errors(retire(t, "phone", 1))).toEqual([]);
    expect(t.r.drainRetireIntents()).toEqual([]);
  });

  it("a retirer with no player of their own is named, with no player for a kitten's consent to check", () => {
    const t = table(["phone", "tablet"]);
    delete t.r.state.seats[0]!.playerId;
    t.clock.now = T0 + RETIRE_AFTER_MS;
    expect(errors(retire(t, "phone", 1))).toEqual([]);
    expect(t.r.drainRetireIntents()).toMatchObject([{ kind: "done", playerId: playerOf(1), from: { name: "Cat 1" }, fromPlayer: null }]);
  });

  it("parses, and refuses a malformed one", () => {
    expect(parseClientMessage('{"t":"retire","seat":1}')).toEqual({ t: "retire", seat: 1 });
    expect(parseClientMessage('{"t":"retire"}')).toEqual({ error: "bad_message" });
    expect(parseClientMessage('{"t":"retire","seat":-1}')).toEqual({ error: "bad_message" });
  });
});

describe("the warning before", () => {
  it("goes once, a day before the seat can be retired, and again for the next stalled turn", () => {
    const t = table(["phone", "tablet"]);
    const warnAt = T0 + RETIRE_AFTER_MS - RETIRE_WARNING_MS;
    expect(t.r.nextAlarm()).toBe(warnAt);
    t.clock.now = warnAt - 1;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toEqual([]);

    t.clock.now = warnAt;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toEqual([
      { kind: "soon", playerId: playerOf(1), seat: 1, personName: "Cat 2", tableName: t.r.state.name, code: "BCDFG" },
    ]);
    expect(t.r.nextAlarm()).toBe(t.r.state.timers.cleanupAt);
    t.clock.now += DAY;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toEqual([]);

    play(t);
    expect(turn(t)).toBe(0);
    expect(t.r.nextAlarm()).toBe(t.clock.now + 2 * DAY);
    t.clock.now += 2 * DAY;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toMatchObject([{ kind: "soon", playerId: playerOf(0), seat: 0 }]);
  });

  it("not when nobody could retire the seat: bots only, one shared phone, or everyone else out", () => {
    for (const seats of [["phone", "bot"], ["phone", "phone"]]) {
      const t = table(seats);
      if (seats[1] === "bot") {
        t.r.state.timers.botAt = t.clock.now;
        t.r.tick();
        t.r.handle("phone", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
      }
      t.clock.now += 5 * DAY;
      t.r.tick();
      expect(t.r.drainRetireIntents()).toEqual([]);
      expect(t.r.state.retireWarned).toBeUndefined();
    }
    // Two people sharing a phone with no players of their own.
    const shared = table(["phone", "phone"], { players: false });
    shared.clock.now += 5 * DAY;
    shared.r.tick();
    expect(shared.r.state.retireWarned).toBeUndefined();
    // A bot and a person who forfeited: nobody left to retire the one on the move.
    const t = table(["phone", "tablet", "bot"]);
    t.r.handle("phone", { t: "act", seat: 0, action: { type: "forfeit" } });
    t.clock.now += 5 * DAY;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toEqual([]);
  });

  it("a seat with no player is marked warned without a push", () => {
    const t = table(["phone", "tablet"], { players: false });
    t.clock.now = T0 + 2 * DAY;
    t.r.tick();
    expect(t.r.drainRetireIntents()).toEqual([]);
    expect(t.r.state.retireWarned).toBeDefined();
  });
});

describe("how long a quiet table lasts", () => {
  it("a game in play outlasts a week away and closes after 30 days with no move", () => {
    const t = table(["phone", "tablet"]);
    expect(t.r.state.timers.cleanupAt).toBe(T0 + GAME_CLEANUP_AFTER_MS);
    t.clock.now = T0 + CLEANUP_AFTER_MS + DAY;
    expect(errors(t.r.tick())).toEqual([]);
    expect(t.r.state.status).toBe("playing");
    expect(t.r.waitingSince()).toBe(T0);
    t.clock.now = T0 + GAME_CLEANUP_AFTER_MS;
    expect(errors(t.r.tick())).toEqual(["room_closed"]);
  });

  it("a game dealt under the old 7-day limit gets the longer one", () => {
    const t = table(["phone", "tablet"]);
    t.r.state.timers.cleanupAt = T0 + CLEANUP_AFTER_MS;
    t.clock.now = T0 + CLEANUP_AFTER_MS;
    expect(errors(t.r.tick())).toEqual([]);
    expect(t.r.state.timers.cleanupAt).toBe(T0 + GAME_CLEANUP_AFTER_MS);
  });

  it("a lobby nobody started still closes after 7 days, and a finished game 7 days after its last move", () => {
    const clock = { now: T0 };
    const lobby = new RoomCore(RoomCore.create("BCDFG", "phone", T0), () => clock.now, () => 0.25);
    lobby.connect("phone");
    lobby.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(lobby.state.timers.cleanupAt).toBe(T0 + CLEANUP_AFTER_MS);
    expect(lobby.waitingSince()).toBeNull();
    clock.now = T0 + CLEANUP_AFTER_MS;
    expect(errors(lobby.tick())).toEqual(["room_closed"]);

    const t = table(["phone", "tablet"]);
    t.clock.now = T0 + RETIRE_AFTER_MS;
    retire(t, "phone", 1);
    expect(t.r.waitingSince()).toBeNull();
    t.clock.now += CLEANUP_AFTER_MS - 1;
    expect(errors(t.r.tick())).toEqual([]);
    t.clock.now += 1;
    expect(errors(t.r.tick())).toEqual(["room_closed"]);
  });
});
