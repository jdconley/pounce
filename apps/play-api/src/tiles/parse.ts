import { hasKeys, isObj } from "../shape";

import { isTileId, MAX_VALUE, type TileId } from "./pieces";

import type { TilesAction } from "./engine";

/** Every piece in sets of three or more: no legal table has more sets than this. */
const MAX_SETS = 35;
const MAX_PIECES = 106;

/**
 * A tile game action off the wire, or null. It checks the shape and the
 * sizes only: whether a table is a legal play is the engine's to say, with a
 * reason (`checkPlay`). The table is copied, so nothing of the message is kept.
 */
export function parseAction(a: unknown): TilesAction | null {
  if (!isObj(a)) return null;
  switch (a.type) {
    case "draw":
    case "pass":
    case "forfeit":
      return hasKeys(a, ["type"]) ? { type: a.type } : null;
    case "play": {
      if (!hasKeys(a, ["type", "table"])) return null;
      const { table } = a;
      if (!Array.isArray(table) || table.length > MAX_SETS) return null;
      const sets: TileId[][] = [];
      let pieces = 0;
      for (const set of table as unknown[]) {
        if (!Array.isArray(set) || set.length > MAX_VALUE || !set.every(isTileId)) return null;
        pieces += set.length;
        sets.push([...set]);
      }
      return pieces > MAX_PIECES ? null : { type: "play", table: sets };
    }
    default:
      return null;
  }
}
