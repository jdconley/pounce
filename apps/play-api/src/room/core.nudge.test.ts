import { describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { card } from "../rules/cards";

import { NUDGE_AFTER_MS, NUDGE_EVERY_MS, RoomCore, type Outbound } from "./core";

import type { Person, ServerMessage } from "../protocol";
import type { CatTowerState } from "../rules/engine";

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
const C = "p_CCCCCCCCCCCCCCCCCCCCCC";
const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });

type Table = { r: RoomCore; clock: { now: number }; device: (seat: number) => string };

/**
 * Seats 0 and 1 are people on "phone" and "tablet"; then `extra` more: "bot" a House Cat, "shared"
 * a second person on the phone, "third" a person on "pad", "plain" a person on "pad" with no player.
 */
function table(opts: { nudge?: boolean; extra?: ("bot" | "shared" | "third" | "plain")[]; speed?: number } = {}): Table {
  const clock = { now: T0 };
  const r = new RoomCore(RoomCore.create("BCDFG", "phone", T0), () => clock.now, () => 0.25, catTower, opts.speed ?? 1, {
    streaks: true,
    nudge: opts.nudge ?? true,
  });
  const extra = opts.extra ?? [];
  r.connect("phone", { [person(1).id]: A, ...(extra.includes("shared") ? { [person(3).id]: C } : {}) });
  r.connect("tablet", { [person(2).id]: B });
  if (extra.includes("third")) r.connect("pad", { [person(3).id]: C });
  if (extra.includes("plain")) r.connect("pad");
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  const devices = ["phone", "tablet"];
  extra.forEach((kind, i) => {
    const seat = 2 + i;
    if (kind === "bot") {
      r.handle("phone", { t: "configure", seat, kind: "bot" });
      devices.push("bot");
    } else {
      const device = kind === "shared" ? "phone" : "pad";
      r.handle("phone", { t: "configure", seat, kind: "open" });
      r.handle(device, { t: "claim", seat, person: person(3) });
      devices.push(device);
    }
  });
  for (let seat = 2 + extra.length; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  r.handle("phone", { t: "start" });
  return { r, clock, device: (seat) => devices[seat] as string };
}

const game = (r: RoomCore) => r.state.gameState as CatTowerState;
const turn = (r: RoomCore) => game(r).turn;

/** The seat's person draws and discards a number card. */
function play(t: Table): void {
  const seat = turn(t.r);
  t.r.handle(t.device(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
  const pick = (game(t.r).hands[seat] as number[]).find((id) => card(id).kind === "number") as number;
  t.r.handle(t.device(seat), { t: "act", seat, action: { type: "discard", card: pick } });
}

/** Plays until `seat` holds the move. */
function until(t: Table, seat: number): void {
  for (let i = 0; i < 12 && turn(t.r) !== seat; i++) {
    if (t.device(turn(t.r)) === "bot") {
      t.r.state.timers.botAt = t.clock.now;
      t.r.tick();
    } else {
      play(t);
    }
  }
  expect(turn(t.r)).toBe(seat);
}

const errors = (out: Outbound[]) => out.flatMap(({ message }) => (message.t === "error" ? [message.code] : []));
const sent = (out: Outbound[], t: ServerMessage["t"]) => out.filter(({ message }) => message.t === t);
const view = (r: RoomCore, device: string) => r.snapshotFor(device).room.nudge;

/** The other person of seats 0 and 1, and their device. */
const other = (seat: number) => (seat === 0 ? 1 : 0);

describe("nudge: who may nudge whom", () => {
  it("the device without the move sees the seat it may nudge, with the wait; the mover's sees none", () => {
    const t = table();
    const target = turn(t.r);
    const sender = t.device(other(target));
    expect(view(t.r, sender)).toEqual({ seat: target, sent: false, wait: NUDGE_AFTER_MS });
    expect(view(t.r, t.device(target))).toBeUndefined();
    t.clock.now += 30_000;
    expect(view(t.r, sender)).toEqual({ seat: target, sent: false, wait: NUDGE_AFTER_MS - 30_000 });
  });

  it("is refused before the turn is two minutes old, and goes once it is", () => {
    const t = table();
    const target = turn(t.r);
    const sender = t.device(other(target));
    t.clock.now += NUDGE_AFTER_MS - 1;
    expect(errors(t.r.handle(sender, { t: "nudge", seat: target }))).toEqual(["too_soon"]);
    t.clock.now += 1;
    const out = t.r.handle(sender, { t: "nudge", seat: target });
    expect(errors(out)).toEqual([]);
    expect(sent(out, "nudgeSent")).toEqual([{ to: sender, message: { t: "nudgeSent", seat: target } }]);
    expect(view(t.r, sender)).toEqual({ seat: target, sent: true, wait: 0 });
  });

  it("only the seat on the move, only a person, never one of the sender's own seats", () => {
    const t = table({ extra: ["bot"] });
    const target = turn(t.r);
    t.clock.now += NUDGE_AFTER_MS;
    const sender = t.device(other(target));
    expect(errors(t.r.handle(sender, { t: "nudge", seat: other(target) }))).toEqual(["bad_seat"]);
    expect(errors(t.r.handle(sender, { t: "nudge", seat: 2 }))).toEqual(["bad_seat"]);
    expect(errors(t.r.handle(sender, { t: "nudge", seat: 9 }))).toEqual(["bad_seat"]);
    expect(errors(t.r.handle("stranger", { t: "nudge", seat: target }))).toEqual(["not_seated"]);
  });

  it("someone not on the move is not their turn", () => {
    const t = table({ extra: ["third"] });
    until(t, 1);
    t.clock.now += NUDGE_AFTER_MS;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 2 }))).toEqual(["not_their_turn"]);
  });

  it("a bot's move and a shared phone's own seat offer nobody to nudge", () => {
    const bot = table({ extra: ["bot"] });
    until(bot, 2);
    expect(view(bot.r, "phone")).toBeUndefined();
    expect(view(bot.r, "tablet")).toBeUndefined();
    const shared = table({ extra: ["shared"] });
    until(shared, 2);
    expect(view(shared.r, "phone")).toBeUndefined();
    shared.clock.now += NUDGE_AFTER_MS;
    expect(errors(shared.r.handle("phone", { t: "nudge", seat: 2 }))).toEqual(["bad_seat"]);
    expect(view(shared.r, "tablet")).toMatchObject({ seat: 2, sent: false });
  });

  it("refused outside a round, and with the flag off, which also leaves snapshots as before", () => {
    const lobby = new RoomCore(RoomCore.create("BCDFG", "phone", T0), () => T0, () => 0.25, catTower, 1, { streaks: true, nudge: true });
    lobby.connect("phone");
    expect(errors(lobby.handle("phone", { t: "nudge", seat: 1 }))).toEqual(["not_playing"]);
    const off = table({ nudge: false });
    const target = turn(off.r);
    off.clock.now += NUDGE_AFTER_MS;
    expect(errors(off.r.handle(off.device(other(target)), { t: "nudge", seat: target }))).toEqual(["bad_message"]);
    expect(off.r.snapshotFor(off.device(other(target))).room).not.toHaveProperty("nudge");
  });

  it("a forfeited sender may not nudge", () => {
    const t = table({ extra: ["third"] });
    until(t, 1);
    t.r.handle("pad", { t: "act", seat: 2, action: { type: "forfeit" } });
    t.clock.now += NUDGE_AFTER_MS;
    expect(errors(t.r.handle("pad", { t: "nudge", seat: 1 }))).toEqual(["not_seated"]);
    expect(view(t.r, "pad")).toBeUndefined();
  });
});

describe("nudge: limits", () => {
  it("once per turn, then ten minutes from the last before the same seat nudges again", () => {
    const t = table();
    until(t, 1);
    t.clock.now += NUDGE_AFTER_MS;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 1 }))).toEqual([]);
    const at = t.clock.now;
    t.clock.now += NUDGE_EVERY_MS;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 1 }))).toEqual(["too_soon"]);
    expect(view(t.r, "phone")).toEqual({ seat: 1, sent: true, wait: 0 });
    // Tablet plays, phone plays: tablet's move again, a minute after the nudge.
    t.clock.now = at + 30_000;
    play(t);
    play(t);
    expect(turn(t.r)).toBe(1);
    t.clock.now = at + 60_000;
    expect(view(t.r, "phone")).toEqual({ seat: 1, sent: false, wait: NUDGE_EVERY_MS - 60_000 });
    t.clock.now = at + NUDGE_EVERY_MS - 1;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 1 }))).toEqual(["too_soon"]);
    t.clock.now = at + NUDGE_EVERY_MS;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 1 }))).toEqual([]);
  });

  it("the wait counts from the start of the turn, not from the draw", () => {
    const t = table();
    const target = turn(t.r);
    t.clock.now += 90_000;
    t.r.handle(t.device(target), { t: "act", seat: target, action: { type: "draw", from: "deck" } });
    expect(view(t.r, t.device(other(target)))?.wait).toBe(NUDGE_AFTER_MS - 90_000);
  });

  it("each sender has their own limit", () => {
    const t = table({ extra: ["third"] });
    until(t, 1);
    t.clock.now += NUDGE_AFTER_MS;
    expect(errors(t.r.handle("phone", { t: "nudge", seat: 1 }))).toEqual([]);
    expect(errors(t.r.handle("pad", { t: "nudge", seat: 1 }))).toEqual([]);
  });

  it("the dev server's speed shortens both", () => {
    const t = table({ speed: 10 });
    const target = turn(t.r);
    expect(view(t.r, t.device(other(target)))?.wait).toBe(NUDGE_AFTER_MS / 10);
  });

  it("a room from before nudges counts the turn from its last activity", () => {
    const t = table();
    const target = turn(t.r);
    delete t.r.state.turnAt;
    t.r.state.lastActivity = T0 + 60_000;
    t.clock.now = T0 + 60_000;
    expect(view(t.r, t.device(other(target)))?.wait).toBe(NUDGE_AFTER_MS);
  });
});

describe("nudge: delivery", () => {
  it("someone at the table gets it there and no push", () => {
    const t = table();
    const target = turn(t.r);
    t.clock.now += NUDGE_AFTER_MS;
    const from = other(target);
    const out = t.r.handle(t.device(from), { t: "nudge", seat: target });
    expect(sent(out, "nudged")).toEqual([{ to: t.device(target), message: { t: "nudged", seat: target, from } }]);
    expect(t.r.drainNudgeIntents()).toEqual([]);
  });

  it("someone away from the table gets a push for their player, naming the sender", () => {
    const t = table();
    until(t, 1);
    t.r.handle("tablet", { t: "presence", state: "background" });
    t.clock.now += NUDGE_AFTER_MS;
    const out = t.r.handle("phone", { t: "nudge", seat: 1 });
    // The backgrounded app still gets the in-app word, in case it comes back first.
    expect(sent(out, "nudged")).toHaveLength(1);
    expect(t.r.drainNudgeIntents()).toEqual([
      {
        playerId: B,
        seat: 1,
        personName: person(2).name,
        tableName: t.r.state.name,
        code: "BCDFG",
        from: { name: person(1).name, cat: person(1).cat },
        fromPlayer: A,
      },
    ]);
    expect(t.r.drainNudgeIntents()).toEqual([]);
  });

  it("nobody else at the table hears about it", () => {
    const t = table({ extra: ["third"] });
    until(t, 1);
    t.clock.now += NUDGE_AFTER_MS;
    const out = t.r.handle("phone", { t: "nudge", seat: 1 });
    expect(out.map((o) => o.to).sort()).toEqual(["phone", "tablet"]);
  });

  it("a sender with no player is named but approves nothing; a seat with no player gets no push", () => {
    const t = table({ extra: ["plain"] });
    until(t, 1);
    t.r.handle("tablet", { t: "presence", state: "background" });
    t.clock.now += NUDGE_AFTER_MS;
    t.r.handle("pad", { t: "nudge", seat: 1 });
    expect(t.r.drainNudgeIntents()).toMatchObject([{ playerId: B, from: { name: person(3).name }, fromPlayer: null }]);
    until(t, 2);
    t.r.handle("pad", { t: "presence", state: "background" });
    t.clock.now += NUDGE_AFTER_MS;
    expect(errors(t.r.handle("tablet", { t: "nudge", seat: 2 }))).toEqual([]);
    expect(t.r.drainNudgeIntents()).toEqual([]);
  });
});
