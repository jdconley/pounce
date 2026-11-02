import { beforeEach, describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { card } from "../rules/cards";

import { RoomCore, type CatTowerModule, type Outbound } from "./core";

import type { Person, RoomEvent, ServerMessage } from "../protocol";
import type { CatTowerState, GameEvent, Seat } from "../rules/engine";
import type { Group } from "../rules/groups";

const SEC = 1000;
const MIN = 60_000;
const DAY = 24 * 60 * MIN;
const T0 = 1_000_000;

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Sequenced = { seq: number; event: RoomEvent };

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

function errorsOf(out: Outbound[]): { to: string; code: string }[] {
  return out.flatMap((o) =>
    o.message.t === "error" ? [{ to: o.to, code: o.message.code }] : [],
  );
}

/** The sequenced events addressed to one device, in order. */
function eventsTo(out: Outbound[], to: string): Sequenced[] {
  return out.flatMap((o) =>
    o.to === to && o.message.t === "event" ? [{ seq: o.message.seq, event: o.message.event }] : [],
  );
}

function gameEventsTo(out: Outbound[], to: string): GameEvent[] {
  return eventsTo(out, to).flatMap(({ event }) => (event.kind === "game" ? [event.event] : []));
}

function snapshotTo(out: Outbound[], to: string): Snapshot {
  const hit = out.find((o) => o.to === to && o.message.t === "snapshot");
  if (!hit) throw new Error(`no snapshot for ${to}`);
  return hit.message as Snapshot;
}

/**
 * A started room. Each name in `humans` is a connected device holding the next
 * seat; `bots` bot seats follow. Seat 0 is the dealer, so seat 1 plays first.
 */
function startedRoom(humans: string[], bots = 0, game?: CatTowerModule, speed?: number): RoomCore {
  const state = RoomCore.create("BCDFG", humans[0] as string, clock);
  const room = new RoomCore(state, () => clock, rng, game, speed);
  humans.forEach((id, seat) => {
    room.connect(id);
    room.handle(id, { t: "claim", seat, person: person(seat + 1) });
  });
  for (let i = 0; i < bots; i++) {
    room.handle(humans[0] as string, { t: "configure", seat: humans.length + i, kind: "bot" });
  }
  const out = room.handle(humans[0] as string, { t: "start" });
  expect(errorsOf(out)).toEqual([]);
  return room;
}

const game = (room: RoomCore): CatTowerState => room.state.gameState as CatTowerState;

/** Ticks 1.2 s apart until it is `seat`'s turn. Returns every tick's output. */
function tickUntilTurn(room: RoomCore, seat: Seat, limit = 200): Outbound[][] {
  const outs: Outbound[][] = [];
  while (game(room).turn !== seat || game(room).status !== "playing") {
    if (outs.length >= limit) throw new Error("turn never arrived");
    clock = room.state.timers.botAt as number;
    outs.push(room.tick());
  }
  return outs;
}

const numberCard = (hand: number[]): number => hand.find((id) => card(id).kind === "number") as number;

/** Seat 0 is to draw from a deck that cannot be refilled: drawing ends the round. */
function exhaust(room: RoomCore, { lastPhase = false } = {}): void {
  const g = game(room);
  g.deck = [];
  g.discard = [g.discard.at(-1) as number];
  g.turn = 0;
  g.step = "draw";
  if (lastPhase) {
    g.phase[0] = 9;
    g.laid[0] = [{ kind: "set", cards: [1, 2, 3], value: 1 } satisfies Group];
  }
}

describe("act", () => {
  it("rejects a seat the device does not control with not_your_seat", () => {
    const room = startedRoom(["a", "b"]);
    const before = structuredClone(room.state);
    const out = room.handle("a", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(out).toHaveLength(1);
    expect(errorsOf(room.handle("stranger", { t: "act", seat: 0, action: { type: "draw", from: "deck" } }))).toEqual([
      { to: "stranger", code: "not_your_seat" },
    ]);
    expect(room.state).toEqual(before);
  });

  it("rejects a seated device that acts while not playing with not_playing", () => {
    const room = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(
      errorsOf(room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } })),
    ).toEqual([{ to: "a", code: "not_playing" }]);
  });

  it("applies a valid action and sends each device its own filtered events with increasing seq", () => {
    clock = T0 + DAY;
    const room = startedRoom(["a", "b"]);
    const seqBefore = room.state.seq;
    expect(game(room).turn).toBe(1);
    clock += 30 * SEC;

    const out = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });

    const forB = eventsTo(out, "b");
    const forA = eventsTo(out, "a");
    expect(forB).toHaveLength(1);
    expect(forA).toHaveLength(1);
    expect(forB[0]!.seq).toBe(seqBefore + 1);
    expect(forA[0]!.seq).toBe(seqBefore + 1);
    expect(room.state.seq).toBe(seqBefore + 1);

    const own = gameEventsTo(out, "b")[0] as Extract<GameEvent, { kind: "drew" }>;
    const other = gameEventsTo(out, "a")[0] as Extract<GameEvent, { kind: "drew" }>;
    expect(own).toMatchObject({ kind: "drew", seat: 1, from: "deck" });
    expect(typeof own.card).toBe("number");
    expect(other).toEqual({ kind: "drew", seat: 1, from: "deck" });
    expect(Object.hasOwn(other, "card")).toBe(false);

    expect(game(room).step).toBe("play");
    expect(room.state.lastActivity).toBe(clock);
    expect(room.state.timers.cleanupAt).toBe(clock + 7 * DAY);
  });

  it("gives every event of a multi-event action its own seq", () => {
    const room = startedRoom(["a", "b"]);
    const seqBefore = room.state.seq;
    room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    const hand = game(room).hands[1] as number[];
    const out = room.handle("b", {
      t: "act",
      seat: 1,
      action: { type: "discard", card: numberCard(hand) },
    });
    const seqs = eventsTo(out, "a").map((e) => e.seq);
    expect(gameEventsTo(out, "a").map((e) => e.kind)).toEqual(["discarded", "turn"]);
    expect(seqs).toEqual([seqBefore + 2, seqBefore + 3]);
    expect(room.state.seq).toBe(seqBefore + 3);
  });

  it("sends nothing to disconnected devices but still advances seq", () => {
    const room = startedRoom(["a", "b"]);
    room.disconnect("a");
    const seq = room.state.seq;
    const out = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    expect(out.map((o) => [o.to, o.message.t])).toEqual([
      ["b", "event"],
      ["b", "snapshot"],
    ]);
    expect(room.state.seq).toBe(seq + 1);
  });

  it("filters by every seat a device controls", () => {
    const room = new RoomCore(RoomCore.create("BCDFG", "a", clock), () => clock, rng);
    room.connect("a");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "claim", seat: 1, person: person(2) });
    room.handle("a", { t: "start" });
    const out = room.handle("a", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    const drew = gameEventsTo(out, "a")[0] as Extract<GameEvent, { kind: "drew" }>;
    expect(typeof drew.card).toBe("number");
  });

  it("returns an engine error to the sender only and changes nothing", () => {
    const room = startedRoom(["a", "b"]);
    const before = structuredClone(room.state);
    const out = room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(out).toEqual([{ to: "a", message: { t: "error", code: "not_your_turn" } }]);
    expect(room.state).toEqual(before);
  });

  it("marks an away device awake when it plays, with presence events and no push", () => {
    const room = startedRoom(["a", "b"]);
    room.handle("b", { t: "presence", state: "background" });
    expect(room.state.devices["b"]!.presence).toBe("away");
    clock += 30 * SEC;
    const seq = room.state.seq;

    const out = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });

    expect(room.state.devices["b"]).toEqual({ presence: "awake", since: clock, connected: true });
    expect(eventsTo(out, "a").map((e) => [e.seq, e.event.kind])).toEqual([
      [seq + 1, "game"],
      [seq + 2, "presence"],
    ]);
    expect(eventsTo(out, "a")[1]!.event).toEqual({ kind: "presence", seat: 1, presence: "awake" });
    expect(eventsTo(out, "b")).toHaveLength(2);
    expect(room.drainPushIntents()).toEqual([]);
    expect((room.snapshotFor("a") as Snapshot).room.seats[1]!.presence).toBe("awake");
  });

  it("Review Focus 2: a repeated draw is bad_step and the other device is not_your_turn", () => {
    const room = startedRoom(["a", "b"]);
    const first = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    expect(eventsTo(first, "a")).toHaveLength(1);
    const applied = structuredClone(room.state);

    // The same draw arrives again (a double-tap, or a second socket of the device).
    const second = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    expect(second).toEqual([{ to: "b", message: { t: "error", code: "bad_step" } }]);
    // The other device races in during b's turn.
    const racer = room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(racer).toEqual([{ to: "a", message: { t: "error", code: "not_your_turn" } }]);

    expect(room.state).toEqual(applied);
    expect((game(room).hands[1] as number[]).length).toBe(11);
  });

  it("Review Focus 1: a device that drops after drawing reconnects mid-turn and can discard", () => {
    const room = startedRoom(["a", "b"]);
    const drawn = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    const drewCard = (gameEventsTo(drawn, "b")[0] as Extract<GameEvent, { kind: "drew" }>).card as number;

    const dropped = room.disconnect("b");
    expect(eventsTo(dropped, "a").map((e) => e.event)).toEqual([
      { kind: "presence", seat: 1, presence: "away" },
    ]);

    const back = room.connect("b");
    const view = snapshotTo(back, "b").room.game;
    expect(view?.turn).toBe(1);
    expect(view?.step).toBe("play");
    expect(view?.hands[1]).toHaveLength(11);
    expect(view?.hands[1]).toContain(drewCard);
    expect(Object.keys(view?.hands ?? {})).toEqual(["1"]);

    const out = room.handle("b", {
      t: "act",
      seat: 1,
      action: { type: "discard", card: numberCard(view?.hands[1] as number[]) },
    });
    expect(errorsOf(out)).toEqual([]);
    expect(game(room).turn).toBe(0);
    expect(game(room).step).toBe("draw");
  });
});

describe("round and game end", () => {
  it("schedules the next round 6 s after roundOver and applies it on tick", () => {
    const room = startedRoom(["a", "b"]);
    exhaust(room);
    const out = room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(gameEventsTo(out, "b").map((e) => e.kind)).toEqual(["roundOver"]);
    expect(game(room).status).toBe("roundOver");
    expect(room.state.status).toBe("playing");
    expect(room.state.timers.nextRoundAt).toBe(clock + 6 * SEC);
    expect(room.state.timers.botAt).toBeNull();

    const start = clock;
    clock = start + 6 * SEC - 1;
    expect(room.tick()).toEqual([]);
    expect(game(room).round).toBe(1);

    clock = start + 6 * SEC;
    const seq = room.state.seq;
    const next = room.tick();
    expect(game(room).round).toBe(2);
    expect(game(room).status).toBe("playing");
    expect(gameEventsTo(next, "a").map((e) => e.kind)).toEqual(["roundStarted", "turn"]);
    expect(eventsTo(next, "b").map((e) => e.seq)).toEqual([seq + 1, seq + 2]);
    expect(room.state.timers.nextRoundAt).toBeNull();
  });

  it("retries later instead of spinning when the engine refuses the automatic nextRound", () => {
    const refusing: CatTowerModule = {
      ...catTower,
      apply: (state, seat, action) =>
        action.type === "nextRound"
          ? { ok: false, error: "round_not_over" }
          : catTower.apply(state, seat, action),
    };
    const room = startedRoom(["a", "b"], 0, refusing);
    exhaust(room);
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    clock += 6 * SEC;
    const seq = room.state.seq;
    expect(room.tick()).toEqual([]);
    expect(room.state.seq).toBe(seq);
    expect(room.state.timers.nextRoundAt).toBe(clock + 6 * SEC);
  });

  it("applies act nextRound at once from any seated device and cancels the timer", () => {
    const room = startedRoom(["a", "b"]);
    exhaust(room);
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.state.timers.nextRoundAt).not.toBeNull();

    const out = room.handle("b", { t: "act", seat: 1, action: { type: "nextRound" } });
    expect(gameEventsTo(out, "a").map((e) => e.kind)).toEqual(["roundStarted", "turn"]);
    expect(game(room).round).toBe(2);
    expect(room.state.timers.nextRoundAt).toBeNull();
    expect(room.tick()).toEqual([]);
  });

  describe("a new round sends each connected device a fresh snapshot with its own new hand", () => {
    /** a and b hold seats 0 and 1, seat 2 is a bot; c is connected but seatless; d has gone. */
    function roundOverRoom(): RoomCore {
      const room = startedRoom(["a", "b"], 1);
      room.connect("c");
      room.connect("d");
      room.disconnect("d");
      exhaust(room);
      room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
      expect(game(room).status).toBe("roundOver");
      return room;
    }

    function expectFreshHands(room: RoomCore, out: Outbound[]): void {
      expect(game(room).round).toBe(2);
      const snapshots = out.filter((o) => o.message.t === "snapshot");
      expect(snapshots.map((o) => o.to).sort()).toEqual(["a", "b", "c"]);
      const own: Record<string, string[]> = { a: ["0"], b: ["1"], c: [] };
      for (const [device, seats] of Object.entries(own)) {
        const snap = snapshotTo(out, device);
        // Follows the round's events and carries the seq of the last one.
        expect(snap.seq).toBe(room.state.seq);
        const lastEvent = Math.max(...eventsTo(out, device).map((e) => e.seq));
        expect(snap.seq).toBe(lastEvent);
        const lastEventAt = out.map((o) => o.to === device && o.message.t === "event").lastIndexOf(true);
        expect(out.findIndex((o) => o.message === snap)).toBeGreaterThan(lastEventAt);
        const view = snap.room.game as NonNullable<Snapshot["room"]["game"]>;
        expect(Object.keys(view.hands)).toEqual(seats);
        for (const seat of seats.map(Number)) {
          expect(view.hands[seat]).toEqual(game(room).hands[seat]);
          expect(view.hands[seat]).toHaveLength(10);
        }
        expect(view.round).toBe(2);
        expect(view.deckCount).toBe(game(room).deck.length);
        expect(view.discardTop).toBe(game(room).discard.at(-1));
        expect(view.laid).toEqual([null, null, null]);
      }
    }

    it("after the automatic nextRound on tick", () => {
      const room = roundOverRoom();
      clock = room.state.timers.nextRoundAt as number;
      expectFreshHands(room, room.tick());
    });

    it("after a manual act nextRound", () => {
      const room = roundOverRoom();
      expectFreshHands(room, room.handle("b", { t: "act", seat: 1, action: { type: "nextRound" } }));
    });
  });

  describe("every successful game action ends with each connected device's own snapshot", () => {
    /**
     * For each device: its events come first, then exactly one snapshot, last,
     * at the seq of its last event (the room's current seq).
     */
    function expectTrailingSnapshots(room: RoomCore, out: Outbound[], devices: string[]): void {
      expect(out.filter((o) => o.message.t === "snapshot").map((o) => o.to).sort()).toEqual(
        [...devices].sort(),
      );
      for (const device of devices) {
        const mine = out.filter((o) => o.to === device);
        expect(mine.at(-1)!.message.t).toBe("snapshot");
        expect(mine.slice(0, -1).every((o) => o.message.t === "event")).toBe(true);
        const snap = snapshotTo(out, device);
        expect(snap.seq).toBe(room.state.seq);
        expect(snap.seq).toBe(Math.max(...eventsTo(out, device).map((e) => e.seq)));
      }
    }

    it("after a human act, carrying the truth the events cannot, and no other seat's hand", () => {
      const room = startedRoom(["a", "b"]);
      room.connect("c");
      const out = room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "discard" } });
      expectTrailingSnapshots(room, out, ["a", "b", "c"]);

      const own: Record<string, string[]> = { a: ["0"], b: ["1"], c: [] };
      for (const [device, seats] of Object.entries(own)) {
        const view = snapshotTo(out, device).room.game as NonNullable<Snapshot["room"]["game"]>;
        expect(Object.keys(view.hands)).toEqual(seats);
        expect(view.step).toBe("play");
        expect(view.discardTop).toBe(game(room).discard.at(-1) ?? null);
        expect(view.handCounts[1]).toBe(11);
      }
      const forB = snapshotTo(out, "b").room.game as NonNullable<Snapshot["room"]["game"]>;
      expect(forB.hands[1]).toEqual(game(room).hands[1]);
    });

    it("after the final round, already saying the room is over", () => {
      const room = startedRoom(["a", "b"]);
      exhaust(room, { lastPhase: true });
      const out = room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
      expectTrailingSnapshots(room, out, ["a", "b"]);
      for (const device of ["a", "b"]) {
        const snap = snapshotTo(out, device);
        expect(snap.room.status).toBe("over");
        expect(snap.room.game?.status).toBe("gameOver");
      }
    });

    it("after a bot move", () => {
      const room = startedRoom(["a"], 1);
      clock = room.state.timers.botAt as number;
      const out = room.tick();
      expect(gameEventsTo(out, "a").map((e) => e.kind)).toEqual(["drew"]);
      expectTrailingSnapshots(room, out, ["a"]);
      const view = snapshotTo(out, "a").room.game as NonNullable<Snapshot["room"]["game"]>;
      expect(Object.keys(view.hands)).toEqual(["0"]);
      expect(view.step).toBe("play");
      expect(view.handCounts[1]).toBe(11);
    });
  });

  it("an early nextRound is rejected while the round is still being played", () => {
    const room = startedRoom(["a", "b"]);
    const out = room.handle("a", { t: "act", seat: 0, action: { type: "nextRound" } });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "round_not_over" }]);
  });

  it("closes the room on gameOver: status over, timers cleared, further acts refused", () => {
    const room = startedRoom(["a", "b"]);
    exhaust(room, { lastPhase: true });
    const out = room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(gameEventsTo(out, "b").map((e) => e.kind)).toEqual(["roundOver", "gameOver"]);
    expect(game(room).status).toBe("gameOver");
    expect(room.state.status).toBe("over");
    expect(room.state.timers.botAt).toBeNull();
    expect(room.state.timers.nextRoundAt).toBeNull();

    expect(
      errorsOf(room.handle("a", { t: "act", seat: 0, action: { type: "nextRound" } })),
    ).toEqual([{ to: "a", code: "not_playing" }]);
    expect(room.tick()).toEqual([]);
  });
});

describe("handle", () => {
  it("answers an unknown message type with bad_message", () => {
    const room = startedRoom(["a", "b"]);
    const out = room.handle("a", { t: "bogus" } as never);
    expect(out).toEqual([{ to: "a", message: { t: "error", code: "bad_message" } }]);
  });

  it("refuses moveSeat once the room is over", () => {
    const room = startedRoom(["a", "b"]);
    room.state.status = "over";
    const out = room.handle("a", { t: "moveSeat", seat: 0 });
    expect(out).toEqual([{ to: "a", message: { t: "error", code: "game_over" } }]);
    expect(room.state.moveCodes).toEqual({});
  });
});

describe("bots", () => {
  it("divides the bot delay and the next-round gap by the dev speed", () => {
    const fast = startedRoom(["a"], 1, undefined, 10);
    expect(fast.state.timers.botAt).toBe(clock + 120);

    const room = startedRoom(["a", "b"], 0, undefined, 10);
    exhaust(room);
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.state.timers.nextRoundAt).toBe(clock + 600);
  });

  it("moves a bot seat on tick once botAt is due, one action per tick", () => {
    const room = startedRoom(["a"], 1);
    expect(game(room).turn).toBe(1);
    expect(room.state.timers.botAt).toBe(clock + 1200);
    expect(room.nextAlarm()).toBe(clock + 1200);

    const start = clock;
    clock = start + 1199;
    expect(room.tick()).toEqual([]);
    expect(room.state.timers.botAt).toBe(start + 1200);

    clock = start + 1200;
    const seq = room.state.seq;
    const draw = room.tick();
    expect(gameEventsTo(draw, "a")).toEqual([{ kind: "drew", seat: 1, from: expect.any(String) }]);
    expect(eventsTo(draw, "a")[0]!.seq).toBe(seq + 1);
    expect(game(room).step).toBe("play");
    expect(game(room).turn).toBe(1);
    expect(room.state.timers.botAt).toBe(clock + 1200);

    // The rest of the bot's turn takes further ticks, then the human is up.
    const rest = tickUntilTurn(room, 0);
    expect(rest.length).toBeGreaterThanOrEqual(1);
    for (const out of rest) {
      const kinds = gameEventsTo(out, "a").map((e) => e.kind);
      expect(kinds.filter((k) => k === "drew")).toEqual([]);
    }
    const last = gameEventsTo(rest.at(-1) as Outbound[], "a").map((e) => e.kind);
    expect(last.slice(-2)).toEqual(["discarded", "turn"]);
    expect(room.state.timers.botAt).toBeNull();
  });

  it("hides the card a bot draws from the deck from the human", () => {
    const room = startedRoom(["a"], 1);
    // Force a deck draw so the privacy rule applies.
    const stub: CatTowerModule = { ...catTower, botAction: () => ({ type: "draw", from: "deck" }) };
    const stubbed = new RoomCore(room.state, () => clock, rng, stub);
    clock = room.state.timers.botAt as number;
    const out = stubbed.tick();
    const drew = gameEventsTo(out, "a")[0] as Extract<GameEvent, { kind: "drew" }>;
    expect(drew).toEqual({ kind: "drew", seat: 1, from: "deck" });
  });

  it("handles everything that is due when the alarm fires late", () => {
    const room = startedRoom(["a", "b"]);
    exhaust(room);
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    room.handle("a", { t: "presence", state: "background" });

    clock += 20 * MIN;
    const out = room.tick();
    expect(game(room).round).toBe(2);
    expect(room.state.devices["a"]!.presence).toBe("asleep");
    expect(gameEventsTo(out, "b").map((e) => e.kind)).toEqual(["roundStarted", "turn"]);
    expect(eventsTo(out, "b").at(-1)!.event).toEqual({ kind: "presence", seat: 0, presence: "asleep" });
    // Both devices are still connected, so both hear every event.
    expect(eventsTo(out, "a").map((e) => e.seq)).toEqual(eventsTo(out, "b").map((e) => e.seq));
  });

  describe("when a bot action is rejected", () => {
    const rejected = (): CatTowerModule => ({
      ...catTower,
      botAction: () => ({ type: "hit", card: 0, target: { seat: 0, group: 0 } }),
    });

    it("falls back to drawing from the deck, then to discarding a number card", () => {
      const room = startedRoom(["a"], 1, rejected());
      clock = room.state.timers.botAt as number;
      const draw = room.tick();
      expect(gameEventsTo(draw, "a")).toEqual([{ kind: "drew", seat: 1, from: "deck" }]);
      expect(game(room).step).toBe("play");

      const hand = [...(game(room).hands[1] as number[])];
      clock = room.state.timers.botAt as number;
      const discard = room.tick();
      expect(gameEventsTo(discard, "a")[0]).toEqual({
        kind: "discarded",
        seat: 1,
        card: hand.find((id) => card(id).kind === "number"),
      });
      expect(game(room).turn).toBe(0);
    });

    it("discards Yarn only when there is nothing else it can play", () => {
      const room = startedRoom(["a"], 1, rejected());
      const g = game(room);
      g.step = "play";
      g.hands[1] = [96, 104];
      clock = room.state.timers.botAt as number;
      const out = room.tick();
      expect(gameEventsTo(out, "a")[0]).toEqual({ kind: "discarded", seat: 1, card: 96 });

      const again = startedRoom(["a"], 1, rejected());
      game(again).step = "play";
      game(again).hands[1] = [96, 104, 7];
      clock = again.state.timers.botAt as number;
      expect(gameEventsTo(again.tick(), "a")[0]).toEqual({ kind: "discarded", seat: 1, card: 7 });
    });

    it("aims a fallback Cucumber at the first other seat that is not already skipped", () => {
      const room = startedRoom(["a"], 2, rejected());
      const g = game(room);
      g.step = "play";
      g.hands[1] = [104, 105];
      g.pendingSkip[0] = true;
      clock = room.state.timers.botAt as number;
      const out = room.tick();
      expect(gameEventsTo(out, "a")[0]).toEqual({
        kind: "discarded",
        seat: 1,
        card: 104,
        skipTarget: 2,
      });
    });

    it("discards a fallback Cucumber without a target when no other seat can be skipped", () => {
      const room = startedRoom(["a"], 1, rejected());
      const g = game(room);
      g.step = "play";
      g.hands[1] = [104, 105];
      g.pendingSkip[0] = true;
      clock = room.state.timers.botAt as number;
      const out = room.tick();
      expect(gameEventsTo(out, "a")[0]).toEqual({ kind: "discarded", seat: 1, card: 104 });
    });

    it("stops the bot clock and reports bot_stalled when even the fallback is rejected", () => {
      const refuseBot: CatTowerModule = {
        ...rejected(),
        apply: (state, seat, action) =>
          seat === 1 ? { ok: false, error: "bad_step" } : catTower.apply(state, seat, action),
      };
      const room = startedRoom(["a"], 1, refuseBot);
      const before = structuredClone(room.state.gameState);
      const seq = room.state.seq;
      clock = room.state.timers.botAt as number;
      expect(room.tick()).toEqual([
        { to: "all", message: { t: "error", code: "bot_stalled" } },
      ]);
      expect(room.state.gameState).toEqual(before);
      expect(room.state.seq).toBe(seq);
      expect(room.state.timers.botAt).toBeNull();
      clock += 10 * SEC;
      expect(room.tick()).toEqual([]);
      expect(room.nextAlarm()).toBe(room.state.timers.cleanupAt);
    });
  });
});

describe("push intents", () => {
  const away = (room: RoomCore): void => {
    room.handle("a", { t: "presence", state: "background" });
  };

  it("queues a your_turn push when the turn reaches an away human, once per turn", () => {
    const room = startedRoom(["a"], 3);
    away(room);
    expect(room.drainPushIntents()).toEqual([]);

    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toEqual([
      { deviceId: "a", kind: "your_turn", seat: 0, personName: "Cat 1", code: "BCDFG" },
    ]);
    expect(room.drainPushIntents()).toEqual([]);

    // The human drawing and discarding in that turn does not push again...
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.drainPushIntents()).toEqual([]);
    const hand = game(room).hands[0] as number[];
    room.handle("a", { t: "act", seat: 0, action: { type: "discard", card: numberCard(hand) } });
    expect(room.drainPushIntents()).toEqual([]);

    // ...but the next turn does, once the device has backgrounded again.
    away(room);
    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toHaveLength(1);
  });

  it("queues nothing while the human's device is awake", () => {
    const room = startedRoom(["a"], 3);
    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toEqual([]);
    expect(room.state.pushedForTurn).toBeNull();
  });

  it("pushes for an asleep or disconnected device too, and for one that never connected", () => {
    const room = startedRoom(["a"], 3);
    room.disconnect("a");
    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toHaveLength(1);

    const ghost = new RoomCore(RoomCore.create("BCDFG", "g", clock), () => clock, rng);
    ghost.handle("g", { t: "claim", seat: 0, person: person(1) });
    ghost.handle("g", { t: "configure", seat: 1, kind: "bot" });
    ghost.handle("g", { t: "start" });
    // The seat's device has no presence record at all.
    ghost.state.devices = {};
    tickUntilTurn(ghost, 0);
    expect(ghost.drainPushIntents()).toEqual([
      { deviceId: "g", kind: "your_turn", seat: 0, personName: "Cat 1", code: "BCDFG" },
    ]);
  });

  it("pushes on start when the first player is a human who is away", () => {
    const state = RoomCore.create("BCDFG", "a", clock);
    const room = new RoomCore(state, () => clock, rng);
    room.connect("a");
    room.connect("b");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("b", { t: "claim", seat: 1, person: person(2) });
    room.disconnect("b");
    room.handle("a", { t: "start" });
    expect(room.drainPushIntents()).toEqual([
      { deviceId: "b", kind: "your_turn", seat: 1, personName: "Cat 2", code: "BCDFG" },
    ]);
  });

  it("keys the dedupe on the latest turn event, so a new round pushes again", () => {
    const room = startedRoom(["a", "b"]);
    room.disconnect("a");
    room.disconnect("b");
    exhaust(room);
    room.handle("b", { t: "presence", state: "active" });
    room.handle("a", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.state.pushedForTurn).toBeNull();
    room.handle("a", { t: "presence", state: "background" });
    clock += 6 * SEC;
    const seqBefore = room.state.seq;
    room.tick();
    // Round 2 deals with seat 0 first (dealer 1): a is away.
    expect(room.drainPushIntents()).toEqual([
      { deviceId: "a", kind: "your_turn", seat: 0, personName: "Cat 1", code: "BCDFG" },
    ]);
    expect(room.state.pushedForTurn).toBe(`2:0:${seqBefore + 2}`);
    expect(room.state.turnSeq).toBe(seqBefore + 2);
  });
});

describe("presence", () => {
  it("background sets away, active sets awake, and each change is broadcast per seat", () => {
    const room = startedRoom(["a", "b"]);
    const seq = room.state.seq;
    clock += 1000;
    const out = room.handle("a", { t: "presence", state: "background" });
    expect(room.state.devices["a"]).toEqual({ presence: "away", since: clock, connected: true });
    expect(eventsTo(out, "a")).toEqual([
      { seq: seq + 1, event: { kind: "presence", seat: 0, presence: "away" } },
    ]);
    expect(eventsTo(out, "b")).toEqual(eventsTo(out, "a"));

    clock += 1000;
    const back = room.handle("a", { t: "presence", state: "active" });
    expect(room.state.devices["a"]).toEqual({ presence: "awake", since: clock, connected: true });
    expect(eventsTo(back, "b")).toEqual([
      { seq: seq + 2, event: { kind: "presence", seat: 0, presence: "awake" } },
    ]);
  });

  it("broadcasts nothing when the presence did not change", () => {
    const room = startedRoom(["a", "b"]);
    const seq = room.state.seq;
    expect(room.handle("a", { t: "presence", state: "active" })).toEqual([]);
    room.handle("a", { t: "presence", state: "background" });
    const since = room.state.devices["a"]!.since;
    clock += MIN;
    expect(room.handle("a", { t: "presence", state: "background" })).toEqual([]);
    expect(room.state.devices["a"]!.since).toBe(since);
    expect(room.state.seq).toBe(seq + 1);
  });

  it("ignores a presence message from a device that never connected", () => {
    const room = startedRoom(["a", "b"]);
    expect(room.handle("ghost", { t: "presence", state: "background" })).toEqual([]);
    expect(room.state.devices["ghost"]).toBeUndefined();
  });

  it("does not count as activity for the 7-day cleanup", () => {
    const room = startedRoom(["a", "b"]);
    const cleanupAt = room.state.timers.cleanupAt;
    clock += DAY;
    room.handle("a", { t: "presence", state: "background" });
    expect(room.state.timers.cleanupAt).toBe(cleanupAt);
  });

  it("connect and disconnect broadcast one presence event per held seat", () => {
    const state = RoomCore.create("BCDFG", "a", clock);
    const room = new RoomCore(state, () => clock, rng);
    room.connect("a");
    room.connect("watcher");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "claim", seat: 1, person: person(2) });
    const seq = room.state.seq;

    const left = room.disconnect("a");
    expect(eventsTo(left, "watcher")).toEqual([
      { seq: seq + 1, event: { kind: "presence", seat: 0, presence: "away" } },
      { seq: seq + 2, event: { kind: "presence", seat: 1, presence: "away" } },
    ]);
    expect(left.every((o) => o.to === "watcher")).toBe(true);
    // Already away: a second disconnect says nothing more.
    expect(room.disconnect("a")).toEqual([]);

    const joined = room.connect("a");
    expect(eventsTo(joined, "watcher")).toEqual([
      { seq: seq + 3, event: { kind: "presence", seat: 0, presence: "awake" } },
      { seq: seq + 4, event: { kind: "presence", seat: 1, presence: "awake" } },
    ]);
    // The reconnecting device gets a snapshot that already includes those events.
    expect(eventsTo(joined, "a")).toEqual([]);
    expect(snapshotTo(joined, "a").seq).toBe(seq + 4);
    expect(joined.at(-1)!.to).toBe("a");

    // A second socket for an awake device is not a change.
    const twice = room.connect("a");
    expect(twice).toHaveLength(1);
    expect(room.state.seq).toBe(seq + 4);
  });

  it("decays away to asleep after 5 minutes and tells the room", () => {
    const room = startedRoom(["a", "b"]);
    room.handle("a", { t: "presence", state: "background" });
    const since = clock;
    expect(room.nextAlarm()).toBe(since + 5 * MIN);

    clock = since + 5 * MIN - 1;
    expect(room.tick()).toEqual([]);
    expect(room.state.devices["a"]!.presence).toBe("away");

    clock = since + 5 * MIN;
    const seq = room.state.seq;
    const out = room.tick();
    expect(room.state.devices["a"]!.presence).toBe("asleep");
    expect(eventsTo(out, "b")).toEqual([
      { seq: seq + 1, event: { kind: "presence", seat: 0, presence: "asleep" } },
    ]);
    expect(eventsTo(out, "a")).toHaveLength(1);
    expect((room.snapshotFor("b") as Snapshot).room.seats[0]!.presence).toBe("asleep");
    // Asleep devices no longer hold the alarm, and decay does not repeat.
    expect(room.nextAlarm()).toBe(room.state.timers.cleanupAt);
    clock += MIN;
    expect(room.tick()).toEqual([]);
  });

  it("decays a disconnected device without sending to it", () => {
    const room = startedRoom(["a", "b"]);
    room.disconnect("a");
    clock += 5 * MIN;
    const out = room.tick();
    expect(out.map((o) => o.to)).toEqual(["b"]);
    expect(room.state.devices["a"]!.presence).toBe("asleep");
  });

  it("an asleep device that wakes up is announced", () => {
    const room = startedRoom(["a", "b"]);
    room.disconnect("a");
    clock += 5 * MIN;
    room.tick();
    const seq = room.state.seq;
    const out = room.connect("a");
    expect(eventsTo(out, "b")).toEqual([
      { seq: seq + 1, event: { kind: "presence", seat: 0, presence: "awake" } },
    ]);
  });
});

describe("cleanup", () => {
  it("closes an idle room after 7 days: status over and room_closed to everyone", () => {
    const room = startedRoom(["a", "b"]);
    const { cleanupAt } = room.state.timers;
    expect(cleanupAt).toBe(clock + 7 * DAY);

    clock = cleanupAt - 1;
    expect(room.tick().filter((o) => o.to === "all")).toEqual([]);
    expect(room.state.status).toBe("playing");

    clock = cleanupAt;
    const out = room.tick();
    expect(out.at(-1)).toEqual({ to: "all", message: { t: "error", code: "room_closed" } });
    expect(room.state.status).toBe("over");
  });

  it("activity pushes cleanup back", () => {
    const room = startedRoom(["a", "b"]);
    clock += 6 * DAY;
    room.handle("b", { t: "act", seat: 1, action: { type: "draw", from: "deck" } });
    clock += DAY;
    expect(room.tick().filter((o) => o.to === "all")).toEqual([]);
    expect(room.state.status).toBe("playing");
  });
});

describe("nextAlarm", () => {
  it("returns the earliest of botAt, nextRoundAt, cleanupAt and away decay", () => {
    const room = startedRoom(["a", "b"]);
    const { timers } = room.state;
    expect(room.nextAlarm()).toBe(timers.cleanupAt);

    room.handle("a", { t: "presence", state: "background" });
    expect(room.nextAlarm()).toBe(clock + 5 * MIN);

    timers.nextRoundAt = clock + 6 * SEC;
    expect(room.nextAlarm()).toBe(clock + 6 * SEC);

    timers.botAt = clock + 1200;
    expect(room.nextAlarm()).toBe(clock + 1200);

    // The earliest decay wins among several away devices.
    clock += 100;
    timers.botAt = null;
    timers.nextRoundAt = null;
    room.handle("b", { t: "presence", state: "background" });
    expect(room.nextAlarm()).toBe(clock - 100 + 5 * MIN);
  });
});
