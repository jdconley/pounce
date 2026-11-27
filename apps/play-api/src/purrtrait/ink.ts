import { isInt } from "../shape";

/*
 * Purrtrait's live ink (design §6): the ops a drawer's device sends, checked against the turn's
 * easel, and compacted for a screen that joins mid-turn. Pure. The room keeps the log in memory
 * only (`room/live-relay.ts`); none of this is ever stored.
 */

/**
 * `["s", id, colour, width, x, y, dx, dy, ...]` starts stroke `id` at (x, y), then deltas.
 * `["p", id, dx, dy, ...]` adds points to it. `["u", id]` undoes it. `["c"]` clears the easel.
 */
export type InkOp = ["s", number, number, number, ...number[]] | ["p", number, ...number[]] | ["u", number] | ["c"];

/** The easel's grid, portrait: x 0-767, y 0-1023. */
export const EASEL_WIDTH = 768;
export const EASEL_HEIGHT = 1024;
/** Colours 0-7, and 8, the eraser. */
export const MAX_COLOUR = 8;
export const MAX_WIDTH = 2;
const MAX_DELTA = 768;
/** Far more stroke ids than a turn can use; only a bound on the number. */
const MAX_ID = 1_000_000;
/** An easel holds at most this many strokes and points since its last clear; past that, `easel_full`. */
export const MAX_STROKES = 500;
export const MAX_POINTS = 30_000;
/** Ink messages one device may send in a second. */
export const INK_PER_SECOND = 25;

/**
 * What the room knows of the turn's easel, to check the next batch. `next`: the id the next stroke
 * must have (at least, when `loose`). `ends`: each stroke on the easel (not undone, not cleared)
 * and its last point. `strokes` and `points`: drawn since the last clear.
 * `loose`: the easel stands in for one the room lost, so ids need only go up (the device's own
 * numbering carries on from strokes the room never saw).
 */
export type InkEasel = {
  next: number;
  strokes: number;
  points: number;
  ends: Record<number, [number, number]>;
  loose: boolean;
};

export const freshEasel = (loose = false): InkEasel => ({ next: 0, strokes: 0, points: 0, ends: {}, loose });

/** True when a batch starts with a clear: it can stand in for a lost easel (the reply to `inkResend`). */
export const wipes = (ops: readonly unknown[]): boolean => {
  const first = ops[0];
  return Array.isArray(first) && first[0] === "c";
};

const onGrid = (x: number, y: number): boolean => x >= 0 && x < EASEL_WIDTH && y >= 0 && y < EASEL_HEIGHT;
const isDelta = (v: unknown): v is number => isInt(v, -MAX_DELTA, MAX_DELTA);
const id = (v: unknown): v is number => isInt(v, 0, MAX_ID);

function parseOp(raw: unknown): InkOp | null {
  if (!Array.isArray(raw)) return null;
  const [tag, ...rest] = raw as unknown[];
  switch (tag) {
    case "c":
      return rest.length === 0 ? ["c"] : null;
    case "u":
      return rest.length === 1 && id(rest[0]) ? ["u", rest[0]] : null;
    case "p": {
      const [stroke, ...deltas] = rest;
      if (!id(stroke) || deltas.length === 0 || deltas.length % 2 !== 0 || !deltas.every(isDelta)) return null;
      return ["p", stroke, ...deltas];
    }
    case "s": {
      const [stroke, colour, width, x, y, ...deltas] = rest;
      if (!id(stroke) || !isInt(colour, 0, MAX_COLOUR) || !isInt(width, 0, MAX_WIDTH)) return null;
      if (!isInt(x, 0, EASEL_WIDTH - 1) || !isInt(y, 0, EASEL_HEIGHT - 1)) return null;
      if (deltas.length % 2 !== 0 || !deltas.every(isDelta)) return null;
      return ["s", stroke, colour, width, x, y, ...deltas];
    }
    default:
      return null;
  }
}

/** An `ink` message's `ops`, shape only (spec §6.2): a non-empty list of well-formed ops, or null. */
export function parseOps(raw: unknown): InkOp[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const ops: InkOp[] = [];
  for (const op of raw) {
    const parsed = parseOp(op);
    if (parsed === null) return null;
    ops.push(parsed);
  }
  return ops;
}

/** Walks `deltas` from (x, y); the last point, or null if one leaves the grid. */
function walk(x: number, y: number, deltas: readonly number[]): [number, number] | null {
  for (let i = 0; i < deltas.length; i += 2) {
    x += deltas[i] as number;
    y += deltas[i + 1] as number;
    if (!onGrid(x, y)) return null;
  }
  return [x, y];
}

/**
 * Checks a batch against the easel. Refused, nothing changes: `full` when it is well formed but
 * would take the easel past `MAX_STROKES` or `MAX_POINTS` (`easel_full`), otherwise a bad message.
 * Stroke ids start at 0 and each new one is exactly the next (only higher, on a `loose` easel);
 * `p` and `u` name a stroke on the easel; every point stays on the grid.
 */
export function checkInk(ops: unknown, easel: InkEasel): { ok: true; easel: InkEasel } | { ok: false; full: boolean } {
  const parsed = parseOps(ops);
  if (parsed === null) return { ok: false, full: false };
  let { next, strokes, points } = easel;
  let ends = { ...easel.ends };
  let full = false;
  for (const op of parsed) {
    switch (op[0]) {
      case "c":
        ends = {};
        strokes = 0;
        points = 0;
        break;
      case "u":
        if (!(op[1] in ends)) return { ok: false, full: false };
        delete ends[op[1]];
        break;
      case "p": {
        const [, stroke, ...deltas] = op;
        const end = ends[stroke];
        const last = end && walk(end[0], end[1], deltas);
        if (!last) return { ok: false, full: false };
        ends[stroke] = last;
        points += deltas.length / 2;
        break;
      }
      case "s": {
        const [, stroke, , , x, y, ...deltas] = op;
        if (easel.loose ? stroke < next : stroke !== next) return { ok: false, full: false };
        const last = walk(x as number, y as number, deltas);
        if (!last) return { ok: false, full: false };
        ends[stroke] = last;
        next = stroke + 1;
        strokes += 1;
        points += 1 + deltas.length / 2;
        break;
      }
    }
    if (strokes > MAX_STROKES || points > MAX_POINTS) full = true;
  }
  if (full) return { ok: false, full: true };
  return { ok: true, easel: { next, strokes, points, ends, loose: easel.loose } };
}

/**
 * The smallest drawing that looks the same as `ops`: everything before the last clear goes, undone
 * strokes go, and each stroke's points are folded into its start, in the order the strokes began.
 */
export function compact(ops: readonly InkOp[]): InkOp[] {
  const strokes = new Map<number, number[]>();
  let from = 0;
  ops.forEach((op, i) => {
    if (op[0] === "c") from = i + 1;
  });
  for (const op of ops.slice(from)) {
    if (op[0] === "s") strokes.set(op[1], op.slice(1) as number[]);
    else if (op[0] === "p") strokes.get(op[1])?.push(...(op.slice(2) as number[]));
    // No clear comes after the last one: the rest are undos.
    else strokes.delete((op as ["u", number])[1]);
  }
  return [...strokes.values()].map((rest) => ["s", ...rest] as InkOp);
}
