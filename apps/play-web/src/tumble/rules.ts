/**
 * Toy Tumble's timing on this device (spec §4.2, §4.5, §4.6): how fast toys fall, the set-down
 * wait, junk's wait and the tricks that last. The engine (`@pounce/play-api/tumble/*`) owns the
 * box; these are the clocks around it, which the server doesn't check.
 */
import type { Box, Hit } from "@pounce/play-api/tumble/box";
import type { HitWire } from "@pounce/play-api/tumble/wire";

/** How fast toys fall and the set-down wait are the engine's, shared with the app and the House Cats. */
export { gravityMs, SET_DOWN_MS, SET_DOWN_RESETS as MAX_RESETS } from "@pounce/play-api/tumble/clock";

/** Soft drop: one row every this many ms (or gravity, if that is faster). */
export const SOFT_MS = 40;
/** Junk waits this long from its ack before it may land. */
export const JUNK_WAIT_MS = 2000;
/** Catnip and Nap last this long from the ack. */
export const TRICK_MS = 10_000;
/** The longest round clock the wire takes. */
export const MAX_ROUND_MS = 600_000;

const isNums = (v: unknown, n: number, min: number, max: number): v is number[] =>
  Array.isArray(v) && v.length === n && v.every((x) => typeof x === "number" && Number.isInteger(x) && x >= min && x <= max);

/** A trick's hit as the engine takes it, from the wire. Null for junk, `napped` or a payload that doesn't fit. */
export function hitOf(h: HitWire): Hit | null {
  const x = (h.x ?? {}) as Record<string, unknown>;
  switch (h.k) {
    case "hairball":
      return typeof x.gap === "number" ? { k: "hairball", gap: x.gap } : null;
    case "swipe":
      return isNums(x.shifts, 22, -2, 2) ? { k: "swipe", shifts: [...x.shifts] } : null;
    case "swap":
      return isNums(x.cells, 264, 0, 10) && isNums(x.tricks, 264, 0, 8) ? { k: "swap", cells: [...x.cells], tricks: [...x.tricks] } : null;
    case "catnip":
    case "scoop":
    case "settle":
    case "nap":
    case "bath":
      return { k: h.k };
    default:
      return null;
  }
}

/** Junk's rows and gap from the wire, or null. */
export function junkOf(h: HitWire): { id: number; rows: number; gap: number } | null {
  if (h.k !== "junk") return null;
  const x = (h.x ?? {}) as Record<string, unknown>;
  return typeof x.rows === "number" && typeof x.gap === "number" ? { id: h.id, rows: x.rows, gap: x.gap } : null;
}

/** Something to show: a clear, a hit landing, a box going out. The screen plays and forgets them. */
export type Fx =
  | { k: "clear"; seat: number; rows: number }
  | { k: "set"; seat: number }
  | { k: "hit"; from: number; to: number; kind: HitWire["k"] }
  | { k: "out"; seat: number }
  | { k: "pocket"; seat: number };

/** The height of a box's stack: its highest filled row + 1 (0 when empty). */
export function stackHeight(box: Pick<Box, "cells">, width = 12): number {
  for (let i = box.cells.length - 1; i >= 0; i--) if (box.cells[i] !== 0) return Math.floor(i / width) + 1;
  return 0;
}
