import { isTileId, MAX_VALUE, tile, type Suit, type Tile, type TileId } from "./pieces";

/**
 * What a set on the table is, and what it is worth. `points` adds up the
 * number every piece stands for, so a Yarn counts as the piece it replaces.
 */
export type SetReading =
  | { kind: "run"; suit: Suit; start: number; end: number; points: number }
  | { kind: "group"; value: number; points: number };

type Natural = Extract<Tile, { kind: "number" }>;

const MIN_SET = 3;
const MAX_GROUP = 4;

/**
 * Reads `tiles` as a set, or returns null when they are not one.
 *
 * A run is three or more pieces of one suit whose numbers climb by one, in
 * the order given: the piece at index `i` stands for `start + i`, which is how
 * a Yarn says which number it is. 1 is only ever low and nothing follows 13.
 *
 * A group is three or four pieces of one number, every suit different. Order
 * does not matter, and a Yarn stands for that number in a suit not yet there.
 *
 * One number piece with two Yarn can be both (5, Yarn, Yarn is a run 5-6-7 and
 * a group of 5s). It is read as whichever is worth more, and as a run when
 * they are worth the same.
 */
export function readSet(tiles: readonly TileId[]): SetReading | null {
  if (tiles.length < MIN_SET || tiles.length > MAX_VALUE) return null;
  if (!tiles.every(isTileId) || new Set(tiles).size !== tiles.length) return null;
  const decoded = tiles.map(tile);
  const run = readRun(decoded);
  const group = readGroup(decoded);
  if (run === null || group === null) return run ?? group;
  return group.points > run.points ? group : run;
}

/*
 * Both readers lean on `readSet`'s checks: there are only two Yarn, so three
 * or more different pieces always include a number piece.
 */

function readRun(decoded: readonly Tile[]): SetReading | null {
  const at = decoded.findIndex((t) => t.kind === "number");
  const anchor = decoded[at] as Natural;
  const start = anchor.value - at;
  const end = start + decoded.length - 1;
  if (start < 1 || end > MAX_VALUE) return null;
  for (const [i, t] of decoded.entries()) {
    if (t.kind === "number" && (t.suit !== anchor.suit || t.value !== start + i)) return null;
  }
  return { kind: "run", suit: anchor.suit, start, end, points: ((start + end) * decoded.length) / 2 };
}

function readGroup(decoded: readonly Tile[]): SetReading | null {
  if (decoded.length > MAX_GROUP) return null;
  const naturals = decoded.filter((t): t is Natural => t.kind === "number");
  const first = naturals[0] as Natural;
  if (naturals.some((t) => t.value !== first.value)) return null;
  if (new Set(naturals.map((t) => t.suit)).size !== naturals.length) return null;
  return { kind: "group", value: first.value, points: first.value * decoded.length };
}

/** True when two sets hold the same pieces in the same order. */
export function sameSet(a: readonly TileId[], b: readonly TileId[]): boolean {
  return a.length === b.length && a.every((id, i) => id === b[i]);
}
