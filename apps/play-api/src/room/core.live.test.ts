import { beforeEach, describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { CAP_MS, IDLE_MS, POUNCE_LIVE_MS } from "../live/live";
import { card } from "../rules/cards";

import { RoomCore, type CatTowerModule, type LiveIntent, type RoomFeatures } from "./core";

import type { Person } from "../protocol";
import type { CatTowerState } from "../rules/engine";

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });
const P1 = person(1).id;
const P2 = person(2).id;

let clock = T0;
beforeEach(() => {
  clock = T0;
});

const game = (r: RoomCore) => r.state.gameState as CatTowerState;
const ON: RoomFeatures = { streaks: true, live: true };

/** Seat 0 is player A on the phone, seat 1 player B on the tablet, then `bots` bots. */
function started(features: RoomFeatures = ON, bots = 0, module: CatTowerModule = catTower): RoomCore {
  const r = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, () => 0.25, module, 1, features);
  r.connect("phone", { [P1]: A });
  r.connect("tablet", { [P2]: B });
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  for (let seat = 2; seat < 2 + bots; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  for (let seat = 2 + bots; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  r.handle("phone", { t: "start" });
  r.drainLiveIntents();
  return r;
}

const deviceOf = (seat: number) => (seat === 0 ? "phone" : "tablet");
const away = (r: RoomCore, device: string) => r.handle(device, { t: "presence", state: "background" });
const kinds = (list: LiveIntent[]) => list.map((i) => `${i.kind}:${i.deviceId}`);

/** The seat to act draws, then discards a number card. */
function takeTurn(r: RoomCore): number {
  const seat = game(r).turn;
  r.handle(deviceOf(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
  const pick = (game(r).hands[seat] as number[]).find((id) => card(id).kind === "number") as number;
  r.handle(deviceOf(seat), { t: "act", seat, action: { type: "discard", card: pick } });
  return seat;
}

describe("when a live table starts (§11.3)", () => {
  it("you leave while someone else is awake at the table: one start, from your view", () => {
    const r = started();
    away(r, "phone");
    const [start, ...rest] = r.drainLiveIntents();
    expect(rest).toEqual([]);
    expect(start).toMatchObject({ kind: "start", deviceId: "phone", code: "BCDFG", playerId: A });
    expect(start?.state).toMatchObject({
      table: r.state.name,
      seats: [
        { cat: 1, phase: 1, name: "Cat 1", bot: false, me: true },
        { cat: 2, phase: 1, name: "Cat 2", bot: false, me: false },
      ],
      turn: game(r).turn,
      mine: game(r).turn === 0,
      streak: null,
    });
    expect(r.state.live).toEqual({ phone: { startedAt: T0, movedAt: T0 } });
    // The socket closing afterwards, or another background, starts nothing more.
    away(r, "phone");
    r.disconnect("phone");
    expect(r.drainLiveIntents()).toEqual([]);
  });

  it("only leaving the app starts one: a socket closed in the app (Home, another table) or dropped starts nothing", () => {
    const r = started();
    r.disconnect("phone");
    expect(r.drainLiveIntents()).toEqual([]);
  });

  it("not when nobody else is awake, unless you just answered a pounce with Play (used up by the start)", () => {
    const r = started();
    away(r, "tablet");
    r.drainLiveIntents();
    away(r, "phone");
    expect(r.drainLiveIntents()).toEqual([]);

    const p = started();
    away(p, "tablet");
    p.drainLiveIntents();
    p.notePounce(A);
    away(p, "phone");
    expect(kinds(p.drainLiveIntents())).toEqual(["start:phone"]);
    expect(p.state.livePounce).toEqual({});
  });

  it("an hour-old pounce no longer counts", () => {
    const r = started();
    away(r, "tablet");
    r.drainLiveIntents();
    r.notePounce(A);
    clock = T0 + POUNCE_LIVE_MS;
    r.notePounce(B);
    expect(r.state.livePounce).toEqual({ [B]: clock });
    away(r, "phone");
    expect(r.drainLiveIntents()).toEqual([]);
  });

  it("not with the feature off, in the lobby, between rounds, for a device with no seat, or after a restart", () => {
    const off = started({ streaks: true });
    away(off, "phone");
    expect(off.drainLiveIntents()).toEqual([]);
    off.notePounce(A);
    expect(off.state.livePounce).toBeUndefined();

    const lobby = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, () => 0.25, catTower, 1, ON);
    lobby.connect("phone", { [P1]: A });
    lobby.connect("tablet", { [P2]: B });
    away(lobby, "phone");
    expect(lobby.drainLiveIntents()).toEqual([]);

    const between = started();
    game(between).status = "roundOver";
    away(between, "phone");
    expect(between.drainLiveIntents()).toEqual([]);

    const watcher = started();
    watcher.connect("ipad");
    away(watcher, "ipad");
    expect(watcher.drainLiveIntents()).toEqual([]);
  });

  it("names the bots and caps a finished phase at 10", () => {
    const r = started(ON, 1);
    game(r).phase = [9, 3, 10];
    away(r, "phone");
    const [start] = r.drainLiveIntents();
    expect(start?.state.seats).toEqual([
      { cat: 1, phase: 10, name: "Cat 1", bot: false, me: true },
      { cat: 2, phase: 4, name: "Cat 2", bot: false, me: false },
      { cat: 3, phase: 10, bot: true, me: false },
    ]);
  });

  it("a device that dropped its start forgets it", () => {
    const r = started();
    away(r, "phone");
    r.drainLiveIntents();
    r.liveDropped("phone");
    expect(r.state.live).toEqual({});
    r.liveDropped("phone");
    expect(r.state.live).toEqual({});
  });
});

describe("updates (§11.3)", () => {
  it("each turn change updates the live devices; the alert only when the move comes to them", () => {
    const r = started();
    // Get to the tablet's move, then the phone leaves.
    if (game(r).turn === 0) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    clock = T0 + 60_000;
    r.handle("tablet", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    // A draw alone is no new turn.
    expect(r.drainLiveIntents()).toEqual([]);
    const pick = (game(r).hands[1] as number[]).find((id) => card(id).kind === "number") as number;
    r.handle("tablet", { t: "act", seat: 1, action: { type: "discard", card: pick } });
    const [update, ...rest] = r.drainLiveIntents();
    expect(rest).toEqual([]);
    expect(update).toMatchObject({ kind: "update", deviceId: "phone", playerId: A, alert: { to: "Cat 1", from: "Cat 2" } });
    expect(update?.state).toMatchObject({ turn: 0, mine: true });
    expect(r.state.live?.phone).toEqual({ startedAt: T0, movedAt: T0 + 60_000 });
  });

  it("a move that goes elsewhere updates with no alert", () => {
    const r = started(ON, 1);
    for (let i = 0; i < 4 && game(r).turn !== 1; i++) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    takeTurn(r);
    const [update] = r.drainLiveIntents();
    expect(update).toMatchObject({ kind: "update", deviceId: "phone", state: { turn: 2, mine: false } });
    expect(update).not.toHaveProperty("alert");
  });

  it("no ring while the same player is awake at the table on another device (§12.1)", () => {
    const r = started();
    if (game(r).turn === 0) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    // JD's iPad is here, awake, speaking for the same player.
    r.connect("ipad", { [P1]: A });
    r.drainLiveIntents();
    takeTurn(r);
    const [update] = r.drainLiveIntents();
    expect(update).toMatchObject({ kind: "update", deviceId: "phone", state: { turn: 0, mine: true } });
    expect(update).not.toHaveProperty("alert");
  });
});

describe("when it ends (§11.3)", () => {
  it("a newer live table on another table replaced it: the record goes, and a held your move comes back", () => {
    const r = started();
    if (game(r).turn === 1) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    r.liveReplaced("phone");
    const [end] = r.drainLiveIntents();
    expect(end).toMatchObject({ kind: "end", deviceId: "phone", reason: "replaced", state: { mine: true } });
    expect(end?.yourMove).toMatchObject({ playerId: A, seat: 0 });
    expect(r.state.live).toEqual({});
    r.liveReplaced("phone");
    expect(r.drainLiveIntents()).toEqual([]);
  });

  it("with the feature turned off, leftover records end with no push", () => {
    const r = started();
    away(r, "phone");
    r.drainLiveIntents();
    const off = new RoomCore(r.state, () => clock, () => 0.25, catTower, 1, { streaks: true });
    off.connect("phone", { [P1]: A });
    expect(off.drainLiveIntents()).toEqual([]);
    expect(off.state.live).toEqual({});
  });

  it("you come back: a reconnect, presence active, or an act ends that device's", () => {
    for (const back of [
      (r: RoomCore) => r.connect("phone", { [P1]: A }),
      (r: RoomCore) => r.handle("phone", { t: "presence", state: "active" }),
    ]) {
      const r = started();
      away(r, "phone");
      r.drainLiveIntents();
      back(r);
      const [end] = r.drainLiveIntents();
      expect(end).toMatchObject({ kind: "end", deviceId: "phone", reason: "back" });
      expect(r.state.live).toEqual({});
    }
    const r = started();
    if (game(r).turn === 1) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    r.handle("phone", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(kinds(r.drainLiveIntents())).toEqual(["end:phone"]);
  });

  it("the round or the game ends: every live table ends", () => {
    for (const status of ["roundOver", "gameOver"] as const) {
      const ends: CatTowerModule = { ...catTower, apply: (st) => ({ ok: true, state: { ...st, status }, events: [] }) };
      const r = started(ON, 0, ends);
      away(r, "phone");
      r.drainLiveIntents();
      r.handle("tablet", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
      expect(r.drainLiveIntents()).toMatchObject([{ kind: "end", deviceId: "phone", reason: "over", state: { turn: null, mine: false } }]);
      expect(r.state.live).toEqual({});
    }
  });

  it("idle for 30 minutes, or 2 hours since the start; your move comes back as a quiet push", () => {
    const r = started();
    if (game(r).turn === 1) takeTurn(r);
    away(r, "phone");
    r.drainLiveIntents();
    expect(r.nextAlarm()).toBeLessThanOrEqual(T0 + IDLE_MS);
    clock = T0 + IDLE_MS - 1;
    r.expireLive(clock);
    expect(r.drainLiveIntents()).toEqual([]);
    clock = T0 + IDLE_MS;
    r.tick();
    const [end] = r.drainLiveIntents();
    expect(end).toMatchObject({ kind: "end", deviceId: "phone", reason: "idle", state: { mine: true } });
    expect(end?.yourMove).toMatchObject({ kind: "your_turn", playerId: A, seat: 0, personName: "Cat 1", code: "BCDFG" });
    expect(r.state.live).toEqual({});
  });

  it("the cap ends a busy table; their move needs no push", () => {
    const r = started();
    game(r).turn = 1;
    away(r, "phone");
    r.drainLiveIntents();
    // A busy table: the last move a minute before the cap.
    r.state.live = { phone: { startedAt: T0, movedAt: T0 + CAP_MS - 60_000 } };
    expect(r.nextAlarm()).toBeLessThanOrEqual(T0 + CAP_MS);
    clock = T0 + CAP_MS;
    r.expireLive(clock);
    const [end] = r.drainLiveIntents();
    expect(end).toMatchObject({ kind: "end", reason: "cap", state: { mine: false } });
    expect(end).not.toHaveProperty("yourMove");
  });

  it("a closing room ends them all", () => {
    const r = started();
    away(r, "phone");
    r.drainLiveIntents();
    r.state.live = { phone: { startedAt: clock, movedAt: clock + 10 ** 12 } };
    r.state.timers.cleanupAt = clock;
    r.state.lastActivity = clock - 30 * 24 * 60 * 60_000;
    r.tick();
    expect(r.drainLiveIntents()).toMatchObject([{ kind: "end", deviceId: "phone", reason: "over" }]);
  });

  it("nextAlarm counts the live deadlines", () => {
    const r = started();
    away(r, "phone");
    r.state.timers.cleanupAt = T0 + 10 * CAP_MS;
    (r.state.devices.phone as { presence: string }).presence = "asleep";
    expect(r.nextAlarm()).toBe(T0 + IDLE_MS);
  });
});

describe("edges", () => {
  it("a seat with no player: no toggle owner, and the held-back your move goes to its device", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, () => 0.25, catTower, 1, ON);
    r.connect("phone");
    r.connect("tablet");
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
    for (let seat = 2; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
    r.handle("phone", { t: "start" });
    game(r).turn = 0;
    away(r, "phone");
    const [start] = r.drainLiveIntents();
    expect(start).toMatchObject({ kind: "start", playerId: null });
    clock = T0 + IDLE_MS;
    r.expireLive(clock);
    const [end] = r.drainLiveIntents();
    expect(end?.yourMove).toMatchObject({ deviceId: "phone", seat: 0 });
    expect(end?.yourMove).not.toHaveProperty("playerId");
    // Nobody else awake, and no players to have been pounced: nothing starts.
    r.handle("phone", { t: "presence", state: "active" });
    away(r, "tablet");
    r.drainLiveIntents();
    away(r, "phone");
    expect(r.drainLiveIntents()).toEqual([]);
    // Dropping a start nobody made is harmless.
    const fresh = started();
    fresh.liveDropped("phone");
    expect(fresh.state.live).toBeUndefined();
  });

  it("a bot's move that brings the turn to you rings with nobody named", () => {
    const r = started(ON, 1);
    game(r).turn = 2;
    game(r).step = "draw";
    away(r, "phone");
    r.drainLiveIntents();
    for (let i = 0; i < 4 && game(r).turn === 2; i++) {
      r.state.timers.botAt = clock;
      r.tick();
    }
    const updates = r.drainLiveIntents().filter((i) => i.kind === "update");
    expect(updates.at(-1)).toMatchObject({ deviceId: "phone", alert: { to: "Cat 1", from: null }, state: { turn: 0, mine: true } });
  });

  it("a round can end with no live table at all", () => {
    const ends: CatTowerModule = { ...catTower, apply: (st) => ({ ok: true, state: { ...st, status: "roundOver" }, events: [] }) };
    const r = started(ON, 0, ends);
    r.handle("tablet", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    expect(r.drainLiveIntents()).toEqual([]);
  });

  it("a device already asleep that says background starts nothing", () => {
    const r = started();
    (r.state.devices.phone as { presence: string }).presence = "asleep";
    away(r, "phone");
    expect(r.drainLiveIntents()).toEqual([]);
  });
});
