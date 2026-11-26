import { beforeEach, describe, expect, it } from "vitest";

import { parseClientMessage, type ClientMessage, type Person, type ServerMessage } from "../protocol";
import { WORDS } from "../purrtrait/words";

import { RoomCore, SCREEN_GRACE_MS, STALL_END_MS, type Outbound } from "./core";

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
