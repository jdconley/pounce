import { beforeEach, describe, expect, it } from "vitest";

import { parseClientMessage } from "../protocol";
import { card } from "../rules/cards";

import { RoomCore, type Outbound } from "./core";

import type { Person, ServerMessage } from "../protocol";
import type { CatTowerState, GameEvent, Seat } from "../rules/engine";

const T0 = 1_000_000;
const FORFEIT = { type: "forfeit" } as const;

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [{ to: o.to, code: o.message.code }] : []));
const game = (room: RoomCore) => room.state.gameState as CatTowerState;

function gameEventsTo(out: Outbound[], to: string): GameEvent[] {
  return out.flatMap((o) =>
    o.to === to && o.message.t === "event" && o.message.event.kind === "game" ? [o.message.event.event] : [],
  );
}

function snapshotTo(out: Outbound[], to: string): Snapshot {
  const hit = out.find((o) => o.to === to && o.message.t === "snapshot");
  if (!hit) throw new Error(`no snapshot for ${to}`);
  return hit.message as Snapshot;
}

/**
 * A started room: `seats[i]` is the device holding seat i, or "bot". A device may hold several
 * seats (pass-and-play). Seat 0 deals, so seat 1 plays first.
 */
function started(seats: string[], streaks = false, players: Record<string, Record<string, string>> = {}): RoomCore {
  const host = seats[0] as string;
  const room = new RoomCore(RoomCore.create("BCDFG", host, clock), () => clock, rng, undefined, 1, { streaks });
  for (const device of new Set(seats)) if (device !== "bot") room.connect(device, players[device] ?? {});
  seats.forEach((device, seat) => {
    if (device === "bot") room.handle(host, { t: "configure", seat, kind: "bot" });
    else if (seat >= 2) room.handle(host, { t: "configure", seat, kind: "open" });
    if (device !== "bot") expect(errorsOf(room.handle(device, { t: "claim", seat, person: person(seat + 1) }))).toEqual([]);
  });
  for (let seat = seats.length; seat < 6; seat++) room.handle(host, { t: "configure", seat, kind: "closed" });
  expect(errorsOf(room.handle(host, { t: "start" }))).toEqual([]);
  return room;
}

/** The seat to act draws from the deck and discards a number card. */
function takeTurn(room: RoomCore, device: string): Outbound[] {
  const seat = game(room).turn;
  room.handle(device, { t: "act", seat, action: { type: "draw", from: "deck" } });
  const hand = game(room).hands[seat] as number[];
  const pick = hand.find((id) => card(id).kind === "number") as number;
  const out = room.handle(device, { t: "act", seat, action: { type: "discard", card: pick } });
  expect(errorsOf(out)).toEqual([]);
  return out;
}

/** Ticks the bot clock until a human seat is up. */
function runBots(room: RoomCore): void {
  for (let i = 0; i < 50 && room.state.timers.botAt !== null; i++) {
    clock = room.state.timers.botAt;
    room.tick();
  }
}

describe("protocol", () => {
  it("parses a forfeit act and nothing more", () => {
    expect(parseClientMessage(JSON.stringify({ t: "act", seat: 1, action: FORFEIT }))).toEqual({
      t: "act",
      seat: 1,
      action: FORFEIT,
    });
    expect(parseClientMessage(JSON.stringify({ t: "act", seat: 1, action: { type: "forfeit", seat: 2 } }))).toEqual({
      error: "bad_message",
    });
  });
});

describe("two players", () => {
  it("a forfeit ends the game and the other player wins; both phones see it", () => {
    const room = started(["a", "b"]);
    // Seat 1 is up; seat 0 forfeits off-turn.
    const out = room.handle("a", { t: "act", seat: 0, action: FORFEIT });
    expect(errorsOf(out)).toEqual([]);
    for (const device of ["a", "b"]) {
      expect(gameEventsTo(out, device)).toEqual([
        { kind: "forfeited", seat: 0 },
        { kind: "gameOver", winners: [1] },
      ]);
      const snap = snapshotTo(out, device);
      expect(snap.room.status).toBe("over");
      expect(snap.room.game?.forfeited).toEqual([true, false]);
      expect(snap.room.game?.winners).toEqual([1]);
    }
    expect(room.state.status).toBe("over");
    expect(room.state.timers.botAt).toBeNull();
    expect(room.state.timers.nextRoundAt).toBeNull();
  });

  it("against a bot: the bot wins, and stops playing", () => {
    const room = started(["a", "bot"]);
    expect(game(room).turn).toBe(1);
    const out = room.handle("a", { t: "act", seat: 0, action: FORFEIT });
    expect(errorsOf(out)).toEqual([]);
    expect(room.state.status).toBe("over");
    expect(game(room).winners).toEqual([1]);
    expect(room.state.timers.botAt).toBeNull();
  });
});

describe("three or more players", () => {
  it("the forfeiter is out, the rest play on and see the seat as forfeited", () => {
    const room = started(["a", "b", "c"]);
    expect(game(room).turn).toBe(1);
    const out = room.handle("b", { t: "act", seat: 1, action: FORFEIT });
    expect(errorsOf(out)).toEqual([]);
    for (const device of ["a", "c"]) {
      expect(gameEventsTo(out, device)).toEqual([
        { kind: "forfeited", seat: 1 },
        { kind: "turn", seat: 2 },
      ]);
      expect(snapshotTo(out, device).room.game?.forfeited).toEqual([false, true, false]);
      expect(snapshotTo(out, device).room.status).toBe("playing");
    }
    expect(snapshotTo(out, "b").room.game?.hands).toEqual({ 1: [] });
    expect(room.allOut(room.controlledSeats("b"))).toBe(true);
    expect(room.allOut(room.controlledSeats("a"))).toBe(false);

    // The turn goes round without seat 1.
    takeTurn(room, "c");
    expect(game(room).turn).toBe(0);
    takeTurn(room, "a");
    expect(game(room).turn).toBe(2);
  });

  it("a forfeited seat's player can't act there again", () => {
    const room = started(["a", "b", "c"]);
    room.handle("a", { t: "act", seat: 0, action: FORFEIT });
    expect(errorsOf(room.handle("a", { t: "act", seat: 0, action: FORFEIT }))).toEqual([{ to: "a", code: "forfeited" }]);
    expect(errorsOf(room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } }))).toEqual([
      { to: "a", code: "not_your_turn" },
    ]);
  });

  it("when only one player is left, that player wins", () => {
    const room = started(["a", "b", "bot"]);
    room.handle("b", { t: "act", seat: 1, action: FORFEIT });
    expect(room.state.status).toBe("playing");
    const out = room.handle("a", { t: "act", seat: 0, action: FORFEIT });
    expect(gameEventsTo(out, "b")).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "gameOver", winners: [2] },
    ]);
    expect(room.state.status).toBe("over");
  });

  it("forfeiting on your turn hands the move to the bot after you, which plays on", () => {
    const room = started(["a", "b", "bot", "bot"]);
    expect(game(room).turn).toBe(1);
    room.handle("b", { t: "act", seat: 1, action: FORFEIT });
    expect(game(room).turn).toBe(2);
    expect(room.state.timers.botAt).not.toBeNull();
    runBots(room);
    expect(game(room).turn).toBe(0);
    takeTurn(room, "a");
    expect(game(room).turn).toBe(2);
  });
});

describe("pass-and-play", () => {
  it("forfeits only the seat sent; the phone plays on with its other seat", () => {
    const room = started(["phone", "phone", "c"]);
    expect(game(room).turn).toBe(1);
    // Seat 1's hand is up on the phone.
    room.handle("phone", { t: "act", seat: 1, action: FORFEIT });
    expect(game(room).forfeited).toEqual([false, true, false]);
    expect(room.state.status).toBe("playing");
    expect(room.allOut(room.controlledSeats("phone"))).toBe(false);
    expect(game(room).turn).toBe(2);
    takeTurn(room, "c");
    expect(game(room).turn).toBe(0);
    // Then seat 0 forfeits too: c is the last one in.
    room.handle("phone", { t: "act", seat: 0, action: FORFEIT });
    expect(room.state.status).toBe("over");
    expect(game(room).winners).toEqual([2]);
  });

  it("two seats on one phone against nobody else: the other seat wins", () => {
    const room = started(["phone", "phone"]);
    room.handle("phone", { t: "act", seat: 1, action: FORFEIT });
    expect(room.state.status).toBe("over");
    expect(game(room).winners).toEqual([0]);
  });
});

describe("invalid forfeits", () => {
  it("not for someone else's seat, nor a bot's", () => {
    const room = started(["a", "b", "bot"]);
    expect(errorsOf(room.handle("a", { t: "act", seat: 1, action: FORFEIT }))).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(errorsOf(room.handle("a", { t: "act", seat: 2, action: FORFEIT }))).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(errorsOf(room.handle("a", { t: "act", seat: 9, action: FORFEIT }))).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(game(room).forfeited).toBeUndefined();
  });

  it("not from a device with no seat", () => {
    const room = started(["a", "b"]);
    room.connect("watcher");
    expect(errorsOf(room.handle("watcher", { t: "act", seat: 0, action: FORFEIT }))).toEqual([
      { to: "watcher", code: "not_your_seat" },
    ]);
  });

  it("not in the lobby", () => {
    const room = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    room.connect("a");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(errorsOf(room.handle("a", { t: "act", seat: 0, action: FORFEIT }))).toEqual([{ to: "a", code: "not_playing" }]);
  });

  it("not once the game is over", () => {
    const room = started(["a", "b"]);
    room.handle("a", { t: "act", seat: 0, action: FORFEIT });
    expect(errorsOf(room.handle("b", { t: "act", seat: 1, action: FORFEIT }))).toEqual([{ to: "b", code: "not_playing" }]);
    expect(game(room).winners).toEqual([1]);
  });
});

describe("streaks", () => {
  const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
  const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
  const C = "p_CCCCCCCCCCCCCCCCCCCCCC";
  const players = {
    a: { [person(1).id]: A },
    b: { [person(2).id]: B },
    c: { [person(3).id]: C },
  };

  it("a forfeit is not a turn, and a two-player forfeit reports the table over", () => {
    const room = started(["a", "b"], true, players);
    room.drainStreakIntents();
    room.handle("b", { t: "act", seat: 1, action: FORFEIT });
    const [intent, ...rest] = room.drainStreakIntents();
    expect(rest).toEqual([]);
    expect(intent).toMatchObject({ by: null, holder: null, over: true, out: [B] });
    expect(intent?.turnedAt).toEqual({});
  });

  it("with three, the forfeiter is listed out, even when the move stays put", () => {
    const room = started(["a", "b", "c"], true, players);
    takeTurn(room, "b");
    takeTurn(room, "c");
    room.drainStreakIntents();
    // Seat 0 (A) is up; C forfeits off-turn.
    expect(game(room).turn).toBe(0 as Seat);
    room.handle("c", { t: "act", seat: 2, action: FORFEIT });
    const intents = room.drainStreakIntents();
    expect(intents).toHaveLength(1);
    expect(intents[0]).toMatchObject({ by: null, holder: A, over: false, out: [C] });
    // Later turns keep listing C as out.
    takeTurn(room, "a");
    expect(room.drainStreakIntents().at(-1)).toMatchObject({ by: A, holder: B, out: [C] });
  });

});
