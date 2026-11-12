import { expect } from "vitest";

import { ALL_TILE_IDS, type TileId } from "../src/tiles/pieces";
import { readSet } from "../src/tiles/sets";

import type { ApplyResult, TilesEvent, TilesState } from "../src/tiles/engine";
import type { TilesView } from "../src/tiles/view";

/* Piece ids (see pieces.ts): each suit is 26 ids, numbers 1-13 and then their twins. */
const piece = (suit: number) => (value: number, twin = false): TileId => suit * 26 + (twin ? 13 : 0) + value - 1;
export const fish = piece(0);
export const mouse = piece(1);
export const feather = piece(2);
export const bell = piece(3);
export const YARN = 104;
export const YARN2 = 105;

export function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value)) deepFreeze(v);
  }
  return value;
}

/**
 * A frozen playing state on seat 0's turn. Give the racks (and a table, if
 * any); every other piece goes to the pool in id order, so all 106 pieces are
 * always somewhere. Pass `pool` to choose it instead: the pieces left over
 * are then set aside in `boxed`.
 */
export function makeState(over: Partial<TilesState> & { racks: TileId[][] }): TilesState {
  const seats = over.racks.length;
  const table = over.table ?? [];
  const boxed = over.boxed ?? [];
  const placed = [...over.racks.flat(), ...table.flat(), ...boxed, ...(over.pool ?? [])];
  const held = new Set(placed);
  if (held.size !== placed.length) throw new Error("makeState: a piece is in two places");
  const spare = ALL_TILE_IDS.filter((id) => !held.has(id));
  return deepFreeze({
    seats,
    opened: new Array<boolean>(seats).fill(false),
    turn: 0,
    passed: new Array<boolean>(seats).fill(false),
    turns: 0,
    status: "playing" as const,
    winners: [],
    scores: new Array<number>(seats).fill(0),
    forfeited: new Array<boolean>(seats).fill(false),
    ...over,
    table,
    pool: over.pool ?? spare,
    boxed: over.pool ? [...boxed, ...spare] : boxed,
  });
}

export function ok(result: ApplyResult): { state: TilesState; events: TilesEvent[] } {
  if (!result.ok) throw new Error(`expected ok, got ${result.error}`);
  return result;
}

export function errorOf(result: ApplyResult): string {
  if (result.ok) throw new Error("expected an error, got ok");
  return result.error;
}

/** Every one of the 106 pieces is in exactly one place, and every set on the table is a set. */
export function expectSound(state: TilesState, label = ""): void {
  const everywhere = [...state.pool, ...state.racks.flat(), ...state.table.flat(), ...state.boxed];
  expect([...everywhere].sort((a, b) => a - b), label).toEqual(ALL_TILE_IDS);
  for (const set of state.table) expect(readSet(set), `${label} ${JSON.stringify(set)}`).not.toBeNull();
}

/** The keys of a view or an event that hold piece ids; every other key must be listed as not holding any. */
const ID_KEYS = new Set(["table", "tile", "placed"]);
const PLAIN_KEYS = new Set([
  "status", "turn", "turns", "poolCount", "rackCounts", "opened", "passed", "winners", "scores", "forfeited",
  "endReason", "kind", "seat", "reason", "left",
]);

/**
 * Every piece id a view or an event carries. Throws on a key it does not
 * know, so a new field has to be sorted into "holds pieces" or "does not"
 * before the leak tests can pass.
 */
export function piecesIn(message: TilesView | TilesEvent): TileId[] {
  const ids: TileId[] = [];
  for (const [key, value] of Object.entries(message)) {
    if (key === "racks") ids.push(...Object.values(value as Record<string, TileId[]>).flat());
    else if (ID_KEYS.has(key)) ids.push(...([value].flat(2) as TileId[]));
    else if (!PLAIN_KEYS.has(key)) throw new Error(`unclassified key: ${key}`);
  }
  return ids;
}
