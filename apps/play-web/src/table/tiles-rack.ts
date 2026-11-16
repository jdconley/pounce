/**
 * The order a player keeps their Tuna Tiles rack in, and how it was last sorted. A phone whose
 * table is on a TV swaps its controller (off turn) for the full table (its turn) every turn, so
 * the order lives here, in memory, by table and seat, not in either view.
 */
import { useState } from "preact/hooks";

import type { TileId } from "@pounce/play-api/tiles/pieces";

export type SortBy = "number" | "toy" | null;
type Kept = { order: TileId[]; by: SortBy };

const kept = new Map<string, Kept>();
/** Tables kept: the newest few, as a phone plays one at a time. */
const KEEP = 8;

/** The rack order for `key` (a table and seat), shared by every view of that rack. */
export function useRackOrder(key: string) {
  const [, redraw] = useState(0);
  const now = kept.get(key) ?? { order: [], by: null };
  const save = (next: Kept) => {
    kept.delete(key);
    kept.set(key, next);
    for (const old of [...kept.keys()].slice(0, Math.max(0, kept.size - KEEP))) kept.delete(old);
    redraw((n) => n + 1);
  };
  return {
    order: now.order,
    setOrder: (order: TileId[]) => save({ ...(kept.get(key) ?? now), order }),
    sortBy: now.by,
    setSortBy: (by: SortBy) => save({ ...(kept.get(key) ?? now), by }),
  };
}

/** The rack as the player keeps it: their order, with pieces new to it on the end. */
export const rackInOrder = (order: readonly TileId[], rack: readonly TileId[]): TileId[] => [...order.filter((id) => rack.includes(id)), ...rack.filter((id) => !order.includes(id))];
