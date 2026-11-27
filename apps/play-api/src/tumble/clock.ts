/**
 * How fast toys fall (spec §4.2), shared by every client and the House Cats. Not checked by the
 * server: a box's own device runs its own clock.
 */

export const START_MS = 1000;
export const MIN_MS = 50;
/** 15% faster every 30 seconds. */
const STEP_MS = 30_000;
const STEP = 0.85;
/** The Zoomies, from 2:30: 30% faster every 15 seconds. */
export const ZOOMIES_AT = 150_000;
const ZOOMIES_STEP_MS = 15_000;
const ZOOMIES_STEP = 0.7;
/** Catnip makes toys fall 4 times as fast (§4.6). */
const CATNIP = 4;
/** A toy that can't fall sets down this long after, reset by a move or turn up to 15 times. */
export const SET_DOWN_MS = 500;
export const SET_DOWN_RESETS = 15;

/** Ms per row, `elapsed` ms into the round. */
export function gravityMs(elapsed: number, catnip = false): number {
  const t = Math.max(0, elapsed);
  let g = START_MS * STEP ** Math.floor(Math.min(t, ZOOMIES_AT) / STEP_MS);
  if (t >= ZOOMIES_AT) g *= ZOOMIES_STEP ** (1 + Math.floor((t - ZOOMIES_AT) / ZOOMIES_STEP_MS));
  if (catnip) g /= CATNIP;
  return Math.max(MIN_MS, g);
}
