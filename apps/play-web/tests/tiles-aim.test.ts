import { describe, expect, test } from "vitest";

import { aimTable, tilesShown } from "../src/table/tiles-public";

import type { RoomView } from "@pounce/play-api/protocol";
import type { TilesView } from "@pounce/play-api/tiles/view";

const tiles: TilesView = {
  status: "playing",
  turn: 1,
  turns: 4,
  table: [[0, 1, 2]],
  poolCount: 40,
  rackCounts: [10, 10],
  racks: {},
  opened: [true, true],
  passed: [false, false],
  winners: [],
  scores: [0, 0],
  forfeited: [false, false],
};
const room = (yours: number | null, v: TilesView = tiles): RoomView => ({
  code: "BCDFG",
  name: "Home",
  status: "playing",
  youAreHost: true,
  gameId: "tiles",
  game: null,
  tiles: v,
  seats: [0, 1].map((i) => ({ kind: "human" as const, person: { id: `p${i}`, name: `P${i}`, cat: i }, yours: i === yours, presence: "awake" as const })),
});
const aims = { 1: { table: [[0, 1, 2, 3], [26, 27, 28]] } };

describe("the sets on show", () => {
  test("someone else's aim, with nothing of this device's own", () => {
    expect(aimTable(room(0), aims)).toEqual(aims[1].table);
    expect(tilesShown(room(null), aims)).toEqual(aims[1].table);
  });

  test("never this device's own seat's aim", () => {
    expect(aimTable(room(1), aims)).toBeNull();
    expect(tilesShown(room(1), aims)).toEqual(tiles.table);
  });

  test("a draft here wins; no aim, or the game over, shows the table", () => {
    expect(tilesShown(room(0), aims, [[5, 6, 7]])).toEqual([[5, 6, 7]]);
    expect(tilesShown(room(0), {})).toEqual(tiles.table);
    expect(tilesShown(room(0, { ...tiles, status: "gameOver" }), aims)).toEqual(tiles.table);
  });
});
