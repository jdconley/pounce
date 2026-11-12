import { OPENING_POINTS, type TilesAction } from "../tiles/engine";
import { isYarn, type TileId } from "../tiles/pieces";
import { addYarnSets, borrowFromTable, findSets, placeOnTable, pointsOf } from "../tiles/solver";

import type { Seat } from "../rules/engine";
import type { Rng } from "../rules/rng";
import type { TilesView } from "../tiles/view";

/** A table to submit, and how many rack pieces it leaves behind. */
type Plan = { table: TileId[][]; left: number };

const ORDERS = ["runs", "groups"] as const;

/**
 * House Cat for the tile game: one action per call, for a seat whose turn it
 * is in a playing game. It reads only the seat's own view. `rng` only breaks
 * ties, so play is deterministic for a given seed.
 *
 * Before opening: lay down sets from the rack once they are worth 30, using
 * a Yarn only when the number pieces fall short. After opening: lay down
 * every set the rack holds, fit single pieces onto the table (the end of a
 * set, a split run, a swapped Yarn) and borrow spare table pieces to finish
 * pairs; then try taking the whole table apart and building it again with
 * the rack mixed in, and keep whichever leaves the fewest pieces. A spare Yarn
 * is kept back until it is the last piece or the pool is empty. With nothing
 * to put down it draws, or passes once the pool is empty.
 *
 * It is greedy throughout: no search over rearrangements, so it misses moves
 * a patient person would find, and it is quick (well under a millisecond).
 */
export function chooseAction(view: TilesView, seat: Seat, rng: Rng): TilesAction {
  const rack = view.racks[seat] as TileId[];
  const opened = view.opened[seat] === true;
  const plans = ORDERS.map((first) =>
    opened ? turnPlan(view.table, rack, view.poolCount === 0, first) : openingPlan(view.table, rack, first),
  );
  const [a, b] = plans as [Plan, Plan];
  let best = a.left === b.left ? (rng() < 0.5 ? a : b) : a.left < b.left ? a : b;
  for (const first of opened ? ORDERS : []) {
    const rebuilt = rebuildPlan(view.table, rack, view.poolCount === 0, first);
    if (rebuilt !== null && rebuilt.left < best.left) best = rebuilt;
  }
  if (best.left < rack.length) return { type: "play", table: best.table };
  return view.poolCount > 0 ? { type: "draw" } : { type: "pass" };
}

/** New sets from the rack beside an untouched table, or nothing when they are worth less than 30. */
function openingPlan(table: TileId[][], rack: TileId[], first: "runs" | "groups"): Plan {
  let found = findSets(rack, first);
  if (pointsOf(found.sets) < OPENING_POINTS) found = addYarnSets(found);
  if (pointsOf(found.sets) < OPENING_POINTS) {
    // Last resort: any Yarn still on the rack goes on the end of a new set.
    const stretched = placeOnTable(found.sets, found.rest.filter(isYarn));
    found = { sets: stretched.table, rest: [] };
  }
  const sets = pointsOf(found.sets) >= OPENING_POINTS ? found.sets : [];
  return { table: [...table, ...sets], left: rack.length - sets.flat().length };
}

function turnPlan(table: TileId[][], rack: TileId[], poolEmpty: boolean, first: "runs" | "groups"): Plan {
  const found = addYarnSets(findSets(rack, first));
  const yarn = found.rest.filter(isYarn);
  let placed = placeOnTable([...table, ...found.sets], found.rest.filter((id) => !isYarn(id)));
  // A piece borrowed from the table can open the way for more single pieces.
  placed = borrowFromTable(placed.table, placed.rest);
  placed = placeOnTable(placed.table, placed.rest);
  let left = placed.rest.length + yarn.length;
  if (yarn.length > 0 && (placed.rest.length === 0 || poolEmpty)) {
    placed = placeOnTable(placed.table, yarn);
    left = left - yarn.length + placed.rest.length;
  }
  return { table: placed.table, left };
}

/** Takes the whole table apart and builds it again with the rack mixed in; null when a table piece is left over. */
function rebuildPlan(table: TileId[][], rack: TileId[], poolEmpty: boolean, first: "runs" | "groups"): Plan | null {
  const onTable = new Set(table.flat());
  const found = findSets([...onTable, ...rack].filter((id) => !isYarn(id)), first);
  const numbers = placeOnTable(found.sets, found.rest);
  const tableYarn = placeOnTable(numbers.table, [...onTable].filter(isYarn));
  if (tableYarn.rest.length > 0 || numbers.rest.some((id) => onTable.has(id))) return null;
  const yarn = rack.filter(isYarn);
  if (yarn.length > 0 && (numbers.rest.length === 0 || poolEmpty)) {
    const spent = placeOnTable(tableYarn.table, yarn);
    return { table: spent.table, left: numbers.rest.length + spent.rest.length };
  }
  return { table: tableYarn.table, left: numbers.rest.length + yarn.length };
}
