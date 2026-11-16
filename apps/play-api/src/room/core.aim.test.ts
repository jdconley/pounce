import { beforeEach, describe, expect, it } from "vitest";

import { AIM_PER_SECOND, RoomCore, type Outbound } from "./core";

import type { GameAim, Person, ServerMessage } from "../protocol";
import type { CatTowerState } from "../rules/engine";
import type { Group } from "../rules/groups";
import type { TilesState } from "../tiles/engine";

const T0 = 1_000_000;
let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const aimsTo = (out: Outbound[]) =>
  out.flatMap((o) => (o.message.t === "aim" ? [{ to: o.to, message: o.message as Extract<ServerMessage, { t: "aim" }> }] : []));

/** Seat 0 on "a" and seat 1 on "b", a TV, started; it is seat 0's turn and seat 1 has a laid group. */
function table(tv = true): RoomCore {
  const state = RoomCore.create("BCDFG", "a", clock);
  const room = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv });
  room.connect("a");
  room.connect("b");
  room.handle("a", { t: "claim", seat: 0, person: person(1) });
  room.handle("b", { t: "claim", seat: 1, person: person(2) });
  room.connect("tv", {}, "screen");
  expect(errorsOf(room.handle("a", { t: "start" }))).toEqual([]);
  const g = room.state.gameState as CatTowerState;
  g.turn = 0;
  g.laid[1] = [{ kind: "set", cards: [1, 2, 3], value: 1 } satisfies Group];
  return room;
}

const at: GameAim = { target: { seat: 1, group: 0 } };

describe("aim", () => {
  it("relays the acting seat's aim to everyone else, with no seq", () => {
    const room = table();
    const before = structuredClone(room.state);
    const out = room.handle("a", { t: "aim", seat: 0, aim: at });
    expect(aimsTo(out)).toEqual([
      { to: "b", message: { t: "aim", seat: 0, aim: at } },
      { to: "tv", message: { t: "aim", seat: 0, aim: at } },
    ]);
    expect(out).toHaveLength(2);
    expect(room.state).toEqual(before);
  });

  it("clears with no aim", () => {
    const room = table();
    const out = room.handle("a", { t: "aim", seat: 0 });
    expect(aimsTo(out).map((o) => o.to)).toEqual(["b", "tv"]);
    expect(aimsTo(out)[0]?.message).toEqual({ t: "aim", seat: 0 });
  });

  it("skips a device that has gone", () => {
    const room = table();
    room.disconnect("tv");
    expect(aimsTo(room.handle("a", { t: "aim", seat: 0, aim: at })).map((o) => o.to)).toEqual(["b"]);
  });

  it("drops an aim from a seat that isn't acting", () => {
    const room = table();
    expect(room.handle("b", { t: "aim", seat: 1, aim: { target: { seat: 1, group: 0 } } })).toEqual([]);
  });

  it("drops an aim for a seat the device doesn't control", () => {
    const room = table();
    expect(room.handle("b", { t: "aim", seat: 0, aim: at })).toEqual([]);
  });

  it("drops an aim from a pass-and-play device for its seat that isn't acting", () => {
    const state = RoomCore.create("BCDFG", "a", clock);
    const room = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv: true });
    room.connect("a");
    room.connect("tv", {}, "screen");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "claim", seat: 1, person: person(2) });
    room.handle("a", { t: "start" });
    const g = room.state.gameState as CatTowerState;
    g.turn = 0;
    g.laid[1] = [{ kind: "set", cards: [1, 2, 3], value: 1 } satisfies Group];
    expect(room.handle("a", { t: "aim", seat: 1, aim: at })).toEqual([]);
    expect(aimsTo(room.handle("a", { t: "aim", seat: 0, aim: at })).map((o) => o.to)).toEqual(["tv"]);
  });

  it("drops an aim at a group that isn't there", () => {
    const room = table();
    expect(room.handle("a", { t: "aim", seat: 0, aim: { target: { seat: 1, group: 4 } } })).toEqual([]);
  });

  it("drops the 11th aim in a second, and takes one again a second later", () => {
    const room = table();
    for (let i = 0; i < AIM_PER_SECOND; i++) {
      expect(aimsTo(room.handle("a", { t: "aim", seat: 0, aim: at }))).toHaveLength(2);
    }
    expect(room.handle("a", { t: "aim", seat: 0, aim: at })).toEqual([]);
    clock += 1001;
    expect(aimsTo(room.handle("a", { t: "aim", seat: 0, aim: at }))).toHaveLength(2);
  });

  it("relays one clear over the limit, to undo the last aim, and no more", () => {
    const room = table();
    for (let i = 0; i < AIM_PER_SECOND; i++) room.handle("a", { t: "aim", seat: 0, aim: at });
    expect(aimsTo(room.handle("a", { t: "aim", seat: 0 })).map((o) => o.to)).toEqual(["b", "tv"]);
    expect(room.handle("a", { t: "aim", seat: 0 })).toEqual([]);
    expect(room.handle("a", { t: "aim", seat: 0, aim: at })).toEqual([]);
  });

  it("drops a clear over the limit when the last thing relayed was a clear", () => {
    const room = table();
    for (let i = 0; i < AIM_PER_SECOND - 1; i++) room.handle("a", { t: "aim", seat: 0, aim: at });
    room.handle("a", { t: "aim", seat: 0 });
    expect(room.handle("a", { t: "aim", seat: 0 })).toEqual([]);
  });

  it("answers a screen's aim with not_allowed", () => {
    const room = table();
    const out = room.handle("tv", { t: "aim", seat: 0, aim: at });
    expect(out).toEqual([{ to: "tv", message: { t: "error", code: "not_allowed" } }]);
  });

  it("drops an aim between rounds and in the lobby", () => {
    const room = table();
    (room.state.gameState as CatTowerState).status = "roundOver";
    expect(room.handle("a", { t: "aim", seat: 0, aim: at })).toEqual([]);
    const state = RoomCore.create("BCDFG", "a", clock);
    const lobby = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv: true });
    lobby.connect("a");
    lobby.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(lobby.handle("a", { t: "aim", seat: 0, aim: at })).toEqual([]);
  });

  it("answers bad_message with the TV feature off", () => {
    const room = table(false);
    expect(errorsOf(room.handle("a", { t: "aim", seat: 0, aim: at }))).toEqual(["bad_message"]);
  });

  it("parses the room's game's aim", () => {
    const room = table();
    expect(room.parseAim({ target: { seat: 1, group: 0 } })).toEqual(at);
    expect(room.parseAim({ table: [] })).toBeNull();
  });
});

describe("a tile draft", () => {
  function tilesTable(): RoomCore<TilesState> {
    const state = RoomCore.create<TilesState>("BCDFG", "a", clock, undefined, undefined, "tiles");
    const room = new RoomCore<TilesState>(state, () => clock, rng, undefined, 1, {
      streaks: true,
      tv: true,
      games: ["cat-tower", "tiles"],
    });
    room.connect("a");
    room.connect("b");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("b", { t: "claim", seat: 1, person: person(2) });
    room.connect("tv", {}, "screen");
    expect(errorsOf(room.handle("a", { t: "start" }))).toEqual([]);
    (room.state.gameState as TilesState).turn = 0;
    return room;
  }

  it("relays a tile draft from the seat's own rack and the table", () => {
    const room = tilesTable();
    const g = room.state.gameState as TilesState;
    const own = (g.racks[0] as number[]).slice(0, 3);
    const onTable = (g.racks[1] as number[]).slice(0, 3);
    g.racks[1] = (g.racks[1] as number[]).slice(3);
    g.table = [onTable];
    const aim: GameAim = { table: [onTable, own] };
    const out = room.handle("a", { t: "aim", seat: 0, aim });
    expect(aimsTo(out).map((o) => o.to)).toEqual(["b", "tv"]);
    expect(aimsTo(out)[0]?.message).toEqual({ t: "aim", seat: 0, aim });
  });

  it("drops a tile draft with another seat's piece", () => {
    const room = tilesTable();
    const g = room.state.gameState as TilesState;
    expect(room.handle("a", { t: "aim", seat: 0, aim: { table: [[(g.racks[1] as number[])[0] as number]] } })).toEqual([]);
  });
});
