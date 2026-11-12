import { isYarn, MAX_VALUE, SUITS, tile, type Tile, type TileId } from "./pieces";
import { readSet } from "./sets";

/** Sets made from a rack, and the pieces of it they did not use. */
export type Found = { sets: TileId[][]; rest: TileId[] };

/** What a list of sets is worth: the number every piece stands for, added up. */
export function pointsOf(sets: readonly (readonly TileId[])[]): number {
  return sets.reduce((sum, set) => sum + (readSet(set)?.points ?? 0), 0);
}

/** The rack's number pieces by suit and number: `[suit][value]` holds up to two ids. */
type Grid = TileId[][][];

function gridOf(rack: readonly TileId[]): Grid {
  const grid: Grid = SUITS.map(() => Array.from({ length: MAX_VALUE + 1 }, () => []));
  for (const id of rack) {
    const t = tile(id);
    if (t.kind === "number") ((grid[SUITS.indexOf(t.suit)] as TileId[][])[t.value] as TileId[]).push(id);
  }
  return grid;
}

/**
 * Takes every run of three or more out of `grid`, each as long as it can be.
 * Each suit is swept twice, because the second copy of a number can start a
 * second run.
 */
function takeRuns(grid: Grid): TileId[][] {
  const runs: TileId[][] = [];
  for (const suit of grid) {
    for (let sweep = 0; sweep < 2; sweep++) {
      let stretch: TileId[][] = [];
      // One past 13 has no stack, which closes a stretch that reaches the top.
      for (let value = 1; value <= MAX_VALUE + 1; value++) {
        const here = suit[value];
        if (here !== undefined && here.length > 0) {
          stretch.push(here);
          continue;
        }
        if (stretch.length >= 3) runs.push(stretch.map((ids) => ids.shift() as TileId));
        stretch = [];
      }
    }
  }
  return runs;
}

/** Takes every group of three or four out of `grid`; twice per number, for the second copies. */
function takeGroups(grid: Grid): TileId[][] {
  const groups: TileId[][] = [];
  for (let value = 1; value <= MAX_VALUE; value++) {
    for (let sweep = 0; sweep < 2; sweep++) {
      const stacks = grid.map((suit) => suit[value] as TileId[]).filter((ids) => ids.length > 0);
      if (stacks.length < 3) continue;
      // Two suits held twice and two held once make two groups of three; a group of four would strand a pair.
      const twice = stacks.filter((ids) => ids.length === 2);
      const once = stacks.filter((ids) => ids.length === 1);
      const from = twice.length === 2 && once.length === 2 ? [...twice, once[0] as TileId[]] : stacks;
      groups.push(from.map((ids) => ids.shift() as TileId));
    }
  }
  return groups;
}

/**
 * Sets that can be made from the rack's number pieces alone, greedily: all
 * the runs and then groups from what is left, or the other way round. Neither
 * order is always better, so a caller tries both. Yarn are left in `rest`.
 */
export function findSets(rack: readonly TileId[], first: "runs" | "groups"): Found {
  const grid = gridOf(rack);
  const sets = first === "runs" ? [...takeRuns(grid), ...takeGroups(grid)] : [...takeGroups(grid), ...takeRuns(grid)];
  const used = new Set(sets.flat());
  return { sets, rest: rack.filter((id) => !used.has(id)) };
}

const replaced = (table: TileId[][], at: number, ...sets: TileId[][]): TileId[][] => [
  ...table.slice(0, at),
  ...sets,
  ...table.slice(at + 1),
];

/**
 * The set of three worth the most that `third` makes with two of `others`,
 * or null when it makes none.
 */
function bestSetWith(third: TileId, others: readonly TileId[]): TileId[] | null {
  let best: TileId[] | null = null;
  let bestPoints = 0;
  for (const [i, a] of others.entries()) {
    for (const b of others.slice(i + 1)) {
      for (const candidate of [[a, b, third], [b, a, third], [a, third, b], [b, third, a], [third, a, b], [third, b, a]]) {
        const points = readSet(candidate)?.points ?? 0;
        if (points > bestPoints) {
          best = candidate;
          bestPoints = points;
        }
      }
    }
  }
  return best;
}

/**
 * Spends the Yarn in `found.rest` on pairs of number pieces that need one
 * more: two of a number in different suits, or two of a suit next to each
 * other or one apart. The pair worth the most goes first.
 */
export function addYarnSets(found: Found): Found {
  const sets = [...found.sets];
  let rest = [...found.rest];
  for (;;) {
    const yarn = rest.find(isYarn);
    if (yarn === undefined) break;
    const set = bestSetWith(yarn, rest.filter((id) => !isYarn(id)));
    if (set === null) break;
    sets.push(set);
    rest = rest.filter((id) => !set.includes(id));
  }
  return { sets, rest };
}

/** The pieces of `pieces` that could sit in a set of three with `spare`: its number, or its suit within two. */
function near(spare: TileId, pieces: readonly TileId[]): TileId[] {
  const numbers = pieces.filter((id) => !isYarn(id));
  const t = tile(spare);
  if (t.kind === "yarn") return numbers;
  return numbers.filter((id) => {
    const other = tile(id) as Extract<Tile, { kind: "number" }>;
    return other.value === t.value || (other.suit === t.suit && Math.abs(other.value - t.value) <= 2);
  });
}

/**
 * Makes new sets from two of `pieces` and one piece the table can spare: the
 * end of a run of four or more, or any piece of a group of four (a Yarn
 * included; it stays on the table, in the new set). Returns the new table and
 * the pieces left over. `table` is not modified.
 */
export function borrowFromTable(table: readonly (readonly TileId[])[], pieces: readonly TileId[]): { table: TileId[][]; rest: TileId[] } {
  let now = table.map((set) => [...set]);
  let rest = [...pieces];
  for (let made = true; made; ) {
    made = false;
    search: for (const [at, set] of now.entries()) {
      for (const spare of set) {
        const without = set.filter((id) => id !== spare);
        if (readSet(without) === null) continue;
        const built = bestSetWith(spare, near(spare, rest));
        if (built === null) continue;
        now = [...replaced(now, at, without), built];
        rest = rest.filter((id) => !built.includes(id));
        made = true;
        break search;
      }
    }
  }
  return { table: now, rest };
}

/**
 * Puts as many of `pieces` as it can onto `table`, one at a time, and returns
 * the new table with the pieces that found no home. A piece goes on the end
 * of a set that stays valid with it, or splits a long run in two around its
 * twin (3-4-5-6-7 plus a 5 makes 3-4-5 and 5-6-7), or takes the place of a
 * Yarn that then moves to the end of another set. `table` is not modified.
 */
export function placeOnTable(table: readonly (readonly TileId[])[], pieces: readonly TileId[]): { table: TileId[][]; rest: TileId[] } {
  let now = table.map((set) => [...set]);
  let rest = [...pieces];
  for (let placed = true; placed; ) {
    placed = false;
    for (const id of rest) {
      const next = placeOne(now, id);
      if (next === null) continue;
      now = next;
      rest = rest.filter((other) => other !== id);
      placed = true;
      break;
    }
  }
  return { table: now, rest };
}

function placeOne(table: TileId[][], id: TileId): TileId[][] | null {
  return onAnEnd(table, id) ?? bySplitting(table, id) ?? bySwappingYarn(table, id);
}

function onAnEnd(table: TileId[][], id: TileId): TileId[][] | null {
  for (const [at, set] of table.entries()) {
    for (const longer of [[...set, id], [id, ...set]]) {
      if (readSet(longer) !== null) return replaced(table, at, longer);
    }
  }
  return null;
}

function bySplitting(table: TileId[][], id: TileId): TileId[][] | null {
  for (const [at, set] of table.entries()) {
    for (let cut = 3; cut <= set.length - 2; cut++) {
      const low = set.slice(0, cut);
      const high = [id, ...set.slice(cut)];
      if (readSet(low) !== null && readSet(high) !== null) return replaced(table, at, low, high);
    }
  }
  return null;
}

function bySwappingYarn(table: TileId[][], id: TileId): TileId[][] | null {
  for (const [at, set] of table.entries()) {
    for (const [i, yarn] of set.entries()) {
      if (!isYarn(yarn)) continue;
      const swapped = set.map((other, j) => (j === i ? id : other));
      if (readSet(swapped) === null) continue;
      // The Yarn has to stay on the table: it needs another set to join.
      const rehomed = onAnEnd(replaced(table, at), yarn);
      if (rehomed !== null) return [...rehomed.slice(0, at), swapped, ...rehomed.slice(at)];
    }
  }
  return null;
}
