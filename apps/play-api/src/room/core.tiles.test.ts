import { beforeEach, describe, expect, it } from "vitest";

import { fish } from "../../tests/tiles-helpers";
import { catTower } from "../games/cat-tower";
import { tiles } from "../games/tiles";

import { RETIRE_AFTER_MS, RoomCore, type Outbound, type RoomFeatures, type RoomState } from "./core";

import type { RoomGame } from "../games";
import type { Person, RoomEvent, ServerMessage } from "../protocol";
import type { CatTowerState } from "../rules/engine";
import type { TilesAction, TilesEvent, TilesState } from "../tiles/engine";

/* A room of the tile game, driven the way the Cat Tower suites drive theirs. */

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});
const P1 = person(1).id;
const P2 = person(2).id;

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Room = RoomCore<TilesState>;

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const game = (r: Room) => r.state.gameState as TilesState;
const deviceOf = (seat: number) => (seat === 0 ? "phone" : "tablet");
const act = (r: Room, seat: number, action: TilesAction, device = deviceOf(seat)) => r.handle(device, { t: "act", seat, action });

function eventsTo(out: Outbound[], to: string): RoomEvent[] {
  return out.flatMap((o) => (o.to === to && o.message.t === "event" ? [o.message.event] : []));
}

function tilesEventsTo(out: Outbound[], to: string): TilesEvent[] {
  return eventsTo(out, to).flatMap((event) => (event.kind === "tiles" ? [event.event] : []));
}

function snapshotTo(out: Outbound[], to: string): Snapshot {
  const hit = out.find((o) => o.to === to && o.message.t === "snapshot");
  if (!hit) throw new Error(`no snapshot for ${to}`);
  return hit.message as Snapshot;
}

function lobby(features: RoomFeatures = { streaks: true }, module?: RoomGame<TilesState>): Room {
  const state = RoomCore.create<TilesState>("BCDFG", "phone", clock, undefined, undefined, "tiles");
  return new RoomCore<TilesState>(state, () => clock, rng, module, 1, features);
}

/** Seat 0 is person 1 (player A) on the phone, seat 1 person 2 (player B) on the tablet, then `bots` bots. */
function started(features: RoomFeatures = { streaks: true }, bots = 0, module?: RoomGame<TilesState>): Room {
  const r = lobby(features, module);
  r.connect("phone", { [P1]: A });
  r.connect("tablet", { [P2]: B });
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  for (let seat = 2; seat < 2 + bots; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
  return r;
}

describe("a tile game lobby", () => {
  it("has the game's four seats, two of them open", () => {
    const state = RoomCore.create("BCDFG", "phone", clock, undefined, undefined, "tiles");
    expect(state.game).toBe("tiles");
    expect(state.seats.map((s) => s.kind)).toEqual(["open", "open", "closed", "closed"]);
    expect(state.gameState).toBeNull();
  });

  it("a Cat Tower lobby still has six, and says so when no game is named", () => {
    const state = RoomCore.create("BCDFG", "phone", clock);
    expect(state.game).toBe("cat-tower");
    expect(state.seats).toHaveLength(6);
  });

  it("has no fifth seat to claim", () => {
    const r = lobby();
    r.connect("phone");
    expect(errorsOf(r.handle("phone", { t: "claim", seat: 4, person: person(1) }))).toEqual(["bad_seat"]);
  });

  it("says which game it is before there is anything to see of it", () => {
    const r = lobby();
    r.connect("phone");
    const { room } = r.snapshotFor("phone");
    expect(room.game).toBeNull();
    expect(room.gameId).toBe("tiles");
    expect("tiles" in room).toBe(false);
    expect(r.actor()).toBeNull();
    expect(r.outSeats()).toEqual([]);
  });

  it("needs two players, like the game", () => {
    const r = lobby();
    r.connect("phone");
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("phone", { t: "configure", seat: 1, kind: "closed" });
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual(["not_enough_players"]);
  });

  it("seats four at most: two people and two House Cats", () => {
    const r = started({ streaks: false }, 2);
    expect(game(r).seats).toBe(4);
    expect(game(r).racks.map((rack) => rack.length)).toEqual([14, 14, 14, 14]);
  });
});

describe("a tile game's snapshots", () => {
  it("carry the game's view under its own key, never under Cat Tower's", () => {
    const r = started();
    const { room } = r.snapshotFor("phone");
    expect(room.status).toBe("playing");
    expect(room.game).toBeNull();
    expect(room.gameId).toBe("tiles");
    expect(room.tiles).toMatchObject({ status: "playing", table: [], poolCount: 78, rackCounts: [14, 14] });
    expect(Object.keys(room.tiles?.racks ?? {})).toEqual(["0"]);
    expect(room.tiles?.racks[0]).toEqual(game(r).racks[0]);
  });

  it("show each device only its own rack, and a device with no seat none", () => {
    const r = started();
    r.connect("watcher");
    expect(Object.keys(r.snapshotFor("tablet").room.tiles?.racks ?? {})).toEqual(["1"]);
    expect(r.snapshotFor("watcher").room.tiles?.racks).toEqual({});
  });

  it("a Cat Tower room's snapshot has neither new key", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng);
    r.connect("phone");
    const { room } = r.snapshotFor("phone");
    expect(Object.keys(room)).toEqual(["code", "name", "status", "youAreHost", "seats", "game"]);
  });
});

describe("acting in a tile game", () => {
  it("a draw goes out as tile game events: the drawer sees the piece, nobody else does", () => {
    const r = started();
    r.connect("watcher");
    const seat = game(r).turn;
    const other = 1 - seat;
    const piece = game(r).pool.at(-1) as number;
    const out = act(r, seat, { type: "draw" });
    expect(errorsOf(out)).toEqual([]);
    expect(tilesEventsTo(out, deviceOf(seat))).toEqual([
      { kind: "drew", seat, tile: piece, poolCount: 77 },
      { kind: "turn", seat: other },
    ]);
    for (const device of [deviceOf(other), "watcher"]) {
      expect(tilesEventsTo(out, device)).toEqual([
        { kind: "drew", seat, poolCount: 77 },
        { kind: "turn", seat: other },
      ]);
    }
    // No Cat Tower event kind is ever used for it.
    expect(eventsTo(out, "phone").some((event) => event.kind === "game")).toBe(false);
    expect(snapshotTo(out, deviceOf(seat)).room.tiles?.rackCounts[seat]).toBe(15);
    expect(game(r).turn).toBe(other);
  });

  it("a play puts the submitted table down for everyone", () => {
    const r = started();
    const seat = game(r).turn;
    const run = [fish(9), fish(10), fish(11)];
    game(r).racks[seat] = [...run, fish(1)];
    const out = act(r, seat, { type: "play", table: [run] });
    expect(errorsOf(out)).toEqual([]);
    expect(tilesEventsTo(out, deviceOf(1 - seat))[0]).toEqual({ kind: "played", seat, table: [run], placed: run, opened: true });
    expect(snapshotTo(out, deviceOf(1 - seat)).room.tiles?.table).toEqual([run]);
  });

  it("the game's own refusals reach the device that asked, and nothing changes", () => {
    const r = started();
    const seat = game(r).turn;
    const before = structuredClone(r.state.gameState);
    expect(errorsOf(act(r, 1 - seat, { type: "draw" }))).toEqual(["not_your_turn"]);
    expect(errorsOf(act(r, seat, { type: "pass" }))).toEqual(["pool_not_empty"]);
    expect(errorsOf(act(r, seat, { type: "play", table: [game(r).pool.slice(0, 3)] }))).toEqual(["not_your_piece"]);
    expect(errorsOf(act(r, seat, { type: "draw" }, deviceOf(1 - seat)))).toEqual(["not_your_seat"]);
    expect(r.state.gameState).toEqual(before);
  });

  it("each room checks actions with its own game's parser", () => {
    const tilesRoom = started();
    const towerRoom = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng);
    expect(tilesRoom.parseAction({ type: "draw" })).toEqual({ type: "draw" });
    expect(tilesRoom.parseAction({ type: "draw", from: "deck" })).toBeNull();
    expect(towerRoom.parseAction({ type: "draw", from: "deck" })).toEqual({ type: "draw", from: "deck" });
    expect(towerRoom.parseAction({ type: "draw" })).toBeNull();
    expect(towerRoom.parseAction({ type: "play", table: [] })).toBeNull();
  });

  it("emptying a rack ends the game and the room with it", () => {
    const r = started();
    const seat = game(r).turn;
    const run = [fish(9), fish(10), fish(11)];
    game(r).racks[seat] = run;
    const out = act(r, seat, { type: "play", table: [run] });
    expect(tilesEventsTo(out, "phone").at(-1)).toMatchObject({ kind: "gameOver", winners: [seat], reason: "out" });
    expect(r.state.status).toBe("over");
    expect(r.state.timers.botAt).toBeNull();
    expect(r.state.timers.nextRoundAt).toBeNull();
    expect(r.actor()).toBeNull();
    expect(snapshotTo(out, "tablet").room).toMatchObject({ status: "over", gameId: "tiles", tiles: { status: "gameOver", winners: [seat] } });
    expect(errorsOf(act(r, 1 - seat, { type: "draw" }))).toEqual(["not_playing"]);
  });

  it("there is no next round to deal: a stray round timer does nothing", () => {
    const r = started();
    const before = structuredClone(r.state.gameState);
    r.state.timers.nextRoundAt = clock;
    expect(r.tick()).toEqual([]);
    expect(r.state.timers.nextRoundAt).toBeNull();
    expect(r.state.gameState).toEqual(before);
  });
});

describe("a House Cat at a tile game", () => {
  /** Ticks until the bot in seat 2 has moved once. */
  function botTurn(r: Room): Outbound[] {
    for (let i = 0; i < 4 && game(r).turn !== 2; i++) expect(errorsOf(act(r, game(r).turn, { type: "draw" }))).toEqual([]);
    expect(game(r).turn).toBe(2);
    expect(r.state.timers.botAt).toBe(clock + 1200);
    clock = r.state.timers.botAt as number;
    return r.tick();
  }

  it("takes its turn on the room's clock, and its events go out like anyone's", () => {
    const r = started({ streaks: false }, 1);
    const out = botTurn(r);
    expect(errorsOf(out)).toEqual([]);
    expect(game(r).turn).not.toBe(2);
    expect(r.state.timers.botAt).toBeNull();
    const events = tilesEventsTo(out, "phone");
    expect(["drew", "played"]).toContain(events[0]?.kind);
    // A bot's draw is as private as a person's.
    expect(events.every((event) => event.kind !== "drew" || !("tile" in event))).toBe(true);
  });

  it("makes the game's plain move when its own is refused", () => {
    const wild: RoomGame<TilesState> = { ...(tiles as RoomGame<TilesState>), botAction: () => ({ type: "play", table: [[0, 1]] }) };
    const r = started({ streaks: false }, 1, wild);
    const before = game(r).racks[2]?.length as number;
    expect(errorsOf(botTurn(r))).toEqual([]);
    expect(game(r).racks[2]).toHaveLength(before + 1);
  });

  it("stalls, and says so, only when even that is refused", () => {
    const stuck: RoomGame<TilesState> = {
      ...(tiles as RoomGame<TilesState>),
      botAction: () => ({ type: "pass" }),
      fallbackAction: () => ({ type: "pass" }),
    };
    const r = started({ streaks: false }, 1, stuck);
    expect(errorsOf(botTurn(r))).toEqual(["bot_stalled"]);
    expect(r.state.timers.botAt).toBeNull();
  });
});

describe("streaks, pushes and stalled seats at a tile game", () => {
  it("a draw is a whole turn: the pairs hear who moved and who holds the move now", () => {
    const r = started();
    r.drainStreakIntents();
    const seat = game(r).turn;
    act(r, seat, { type: "draw" });
    expect(r.drainStreakIntents()).toEqual([
      expect.objectContaining({ by: seat === 0 ? A : B, holder: seat === 0 ? B : A, over: false, players: [A, B] }),
    ]);
  });

  it("the next player gets 'your move' when they are away", () => {
    const r = started();
    const seat = game(r).turn;
    r.handle(deviceOf(1 - seat), { t: "presence", state: "background" });
    r.drainPushIntents();
    act(r, seat, { type: "draw" });
    expect(r.drainPushIntents()).toEqual([
      expect.objectContaining({ kind: "your_turn", seat: 1 - seat, code: "BCDFG", from: { name: `Cat ${seat + 1}`, cat: seat + 1 } }),
    ]);
  });

  it("a forfeit is not a turn, ends a two-seat game and takes the room with it", () => {
    const r = started();
    r.drainStreakIntents();
    const seat = game(r).turn;
    const out = act(r, 1 - seat, { type: "forfeit" });
    expect(tilesEventsTo(out, "phone")).toEqual([
      { kind: "forfeited", seat: 1 - seat },
      expect.objectContaining({ kind: "gameOver", winners: [seat], reason: "forfeit" }),
    ]);
    expect(r.state.status).toBe("over");
    expect(r.outSeats()).toEqual(seat === 0 ? [false, true] : [true, false]);
    expect(r.allOut([1 - seat])).toBe(true);
    expect(r.outPlayers()).toEqual([seat === 0 ? B : A]);
    const [report] = r.drainStreakIntents();
    expect(report).toMatchObject({ by: null, over: true });
  });

  it("a seat that has sat on the move for three days can be retired by the others: the game's own forfeit", () => {
    const r = started({ streaks: true }, 1);
    for (let i = 0; i < 3 && game(r).turn !== 1; i++) {
      if (game(r).turn === 2) {
        clock = r.state.timers.botAt as number;
        r.tick();
      } else {
        act(r, 0, { type: "draw" });
      }
    }
    expect(game(r).turn).toBe(1);
    expect(r.snapshotFor("phone").room.retire).toEqual({ seat: 1, wait: RETIRE_AFTER_MS });
    expect(errorsOf(r.handle("phone", { t: "retire", seat: 1 }))).toEqual(["too_soon"]);
    clock += RETIRE_AFTER_MS;
    const out = r.handle("phone", { t: "retire", seat: 1 });
    expect(errorsOf(out)).toEqual([]);
    expect(tilesEventsTo(out, "phone")[0]).toEqual({ kind: "forfeited", seat: 1 });
    expect(game(r).forfeited).toEqual([false, true, false]);
    expect(game(r).status).toBe("playing");
    expect(r.drainRetireIntents()).toEqual([expect.objectContaining({ kind: "done", playerId: B, seat: 1 })]);
  });

  it("a nudge works on whoever holds the move, with the wait counted per turn", () => {
    const r = started({ streaks: true, nudge: true });
    const seat = game(r).turn;
    const nudger = deviceOf(1 - seat);
    expect(r.snapshotFor(nudger).room.nudge).toMatchObject({ seat, sent: false });
    clock += 3 * 60_000;
    const out = r.handle(nudger, { t: "nudge", seat });
    expect(out.map((o) => o.message.t)).toEqual(["nudgeSent", "nudged"]);
    // The move goes on: the nudge was for that turn only.
    act(r, seat, { type: "draw" });
    expect(r.snapshotFor(deviceOf(seat)).room.nudge).toMatchObject({ seat: 1 - seat, sent: false });
  });
});

describe("the live table at a tile game", () => {
  it("counts the pieces each seat has left, beside the shelf an older reader expects", () => {
    const r = started({ streaks: true, live: true });
    const seat = game(r).turn;
    act(r, seat, { type: "draw" });
    r.drainLiveIntents();
    r.handle("phone", { t: "presence", state: "background" });
    const [start] = r.drainLiveIntents();
    expect(start).toMatchObject({ kind: "start", deviceId: "phone", code: "BCDFG" });
    expect(start?.state).toEqual({
      table: r.state.name,
      seats: [
        { cat: 1, phase: 1, name: "Cat 1", bot: false, me: true, progress: seat === 0 ? 15 : 14 },
        { cat: 2, phase: 1, name: "Cat 2", bot: false, me: false, progress: seat === 1 ? 15 : 14 },
      ],
      turn: 1 - seat,
      mine: seat === 1,
      streak: null,
      progressKind: "pieces",
    });
  });

  it("ends when the game does", () => {
    const r = started({ streaks: true, live: true });
    r.handle("phone", { t: "presence", state: "background" });
    r.drainLiveIntents();
    act(r, 1, { type: "forfeit" });
    expect(r.drainLiveIntents()).toEqual([expect.objectContaining({ kind: "end", deviceId: "phone", reason: "over" })]);
  });

  it("a Cat Tower table's state has no new key", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng, catTower, 1, { streaks: true, live: true });
    r.connect("phone", { [P1]: A });
    r.connect("tablet", { [P2]: B });
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
    r.handle("phone", { t: "start" });
    r.handle("phone", { t: "presence", state: "background" });
    const [start] = r.drainLiveIntents();
    expect(Object.keys(start?.state ?? {})).toEqual(["table", "seats", "turn", "mine", "streak"]);
    expect(Object.keys(start?.state.seats[0] ?? {})).toEqual(["cat", "phase", "name", "bot", "me"]);
  });
});

describe("play again at a tile game", () => {
  function finished(): Room {
    const r = started();
    act(r, 1, { type: "forfeit" });
    return r;
  }

  it("deals the same game again", () => {
    const r = finished();
    expect(errorsOf(r.handle("phone", { t: "rematch" }))).toEqual([]);
    const intent = r.drainRematch();
    expect(intent).toMatchObject({ game: "tiles", hostDeviceId: "phone" });
    const state = RoomCore.rematchState<TilesState>("CDFGH", intent as NonNullable<typeof intent>, clock);
    expect(state.game).toBe("tiles");
    expect(state.seats.map((s) => s.kind)).toEqual(["human", "human", "closed", "closed"]);
    const next = new RoomCore<TilesState>(state, () => clock, rng);
    next.deal();
    expect(next.state.status).toBe("playing");
    expect((next.state.gameState as TilesState).racks).toHaveLength(2);
    expect(next.snapshotFor("phone").room.gameId).toBe("tiles");
  });

  it("a Cat Tower table's play again says nothing of a game, and deals Cat Tower", () => {
    const r = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng, catTower, 1, { streaks: true });
    r.connect("phone");
    r.connect("tablet");
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
    r.handle("phone", { t: "start" });
    r.handle("tablet", { t: "act", seat: 1, action: { type: "forfeit" } });
    r.handle("phone", { t: "rematch" });
    const intent = r.drainRematch();
    expect(Object.keys(intent ?? {}).sort()).toEqual(["hostDeviceId", "look", "name", "seats"]);
    const state = RoomCore.rematchState("CDFGH", intent as NonNullable<typeof intent>, clock);
    expect(state.game).toBe("cat-tower");
    expect(state.seats).toHaveLength(6);
  });
});

describe("rooms saved before there was a second game", () => {
  it("a room that names no game is Cat Tower", () => {
    const saved = RoomCore.create("BCDFG", "phone", clock) as Partial<RoomState>;
    delete saved.game;
    const r = new RoomCore(saved as RoomState, () => clock, rng);
    expect(r.state.game).toBe("cat-tower");
    r.connect("phone");
    r.connect("tablet");
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
    expect((r.state.gameState as CatTowerState).hands).toHaveLength(2);
    expect(r.snapshotFor("phone").room.game).not.toBeNull();
  });
});
