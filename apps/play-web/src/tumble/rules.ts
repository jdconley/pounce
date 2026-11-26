/**
 * Toy Tumble's timing on this device (spec §4.2, §4.5, §4.6): how fast toys fall, the set-down
 * wait, junk's wait and the tricks that last. The engine (`@pounce/play-api/tumble/*`) owns the
 * box; these are the clocks around it, which the server doesn't check.
 */
import type { Box, Hit } from "@pounce/play-api/tumble/box";
import type { HitWire } from "@pounce/play-api/tumble/wire";

/** A toy falls one row every this many ms at the start of a round. */
export const START_MS = 1000;
/** Never faster than this. */
export const FASTEST_MS = 50;
/** Every 30 s, a row takes 15% less time. */
const STEP_EVERY_MS = 30_000;
const STEP = 0.85;
/** From 2:30, the Zoomies: every 15 s, a row takes 30% less time. */
export const ZOOMIES_AT_MS = 150_000;
const ZOOM_EVERY_MS = 15_000;
const ZOOM = 0.7;
/** Catnip makes toys fall this many times as fast. */
const CATNIP = 4;

/** A toy that can't fall sets down after this wait. */
export const SET_DOWN_MS = 500;
/** Moving or turning restarts the wait, up to this many times per toy. */
export const MAX_RESETS = 15;
/** Soft drop: one row every this many ms (or gravity, if that is faster). */
export const SOFT_MS = 40;
/** Junk waits this long from its ack before it may land. */
export const JUNK_WAIT_MS = 2000;
/** Catnip and Nap last this long from the ack. */
export const TRICK_MS = 10_000;
/** The longest round clock the wire takes. */
export const MAX_ROUND_MS = 600_000;

/** The ms per row `elapsed` ms into the round, with Catnip or not. */
export function gravityMs(elapsed: number, catnip = false): number {
  const t = Math.max(0, elapsed);
  let g: number;
  if (t < ZOOMIES_AT_MS) g = START_MS * STEP ** Math.floor(t / STEP_EVERY_MS);
  else g = START_MS * STEP ** Math.floor((ZOOMIES_AT_MS - 1) / STEP_EVERY_MS) * ZOOM ** (1 + Math.floor((t - ZOOMIES_AT_MS) / ZOOM_EVERY_MS));
  if (catnip) g /= CATNIP;
  return Math.max(FASTEST_MS, g);
}

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
