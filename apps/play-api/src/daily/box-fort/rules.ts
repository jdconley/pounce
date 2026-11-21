/**
 * Box Fort's rules: the truth for the server, the web player and the golden vectors that the
 * Swift rules (PounceKit `Daily/BoxFort`) must match. Pure functions over plain values.
 *
 * The rug is 8 by 8, row-major: 0 is an empty spot, 1 to 6 a box in a piece's tint, `CLUTTER` a
 * box that was on the rug at the start. Pieces come three at a time and never rotate. After each
 * placement, every full row and column clears at once.
 */
import type { Cell, Piece } from "./pieces";

export const SIZE = 8;
export const CLUTTER = 7;

/** One point for each box placed. */
export const SQUARE_POINTS = 1;
/** Lines cleared by one placement: 10, 30, 60, 100, … */
export const lineBonus = (lines: number): number => (10 * lines * (lines + 1)) / 2;
/** The `combo`th clearing placement in a row: nothing for the first, then 15 more each time. */
export const comboBonus = (combo: number): number => (combo > 1 ? 15 * (combo - 1) : 0);
/** Placing the day's last set. */
export const FULL_FORT = 200;

export type Cleared = { rows: number[]; cols: number[] };

export type BoxFortState = {
  rug: number[];
  /** The current set, from 0. */
  set: number;
  /** How many sets the day has. */
  sets: number;
  /** Which of the current set's three pieces are on the rug. */
  placed: boolean[];
  points: number;
  /** Clearing placements in a row, ending with the last one; 0 after one that cleared nothing. */
  combo: number;
  /** Lines cleared in the whole run. */
  lines: number;
  /** "full": the last set is placed. "stuck": nothing left in the current set fits. */
  over: "full" | "stuck" | null;
};

export type Step = { state: BoxFortState; gained: number; cleared: Cleared; setDone: boolean };

export function fits(rug: readonly number[], cells: readonly Cell[], row: number, col: number): boolean {
  return cells.every(([r, c]) => {
    const y = row + r;
    const x = col + c;
    return y >= 0 && y < SIZE && x >= 0 && x < SIZE && rug[y * SIZE + x] === 0;
  });
}

/** Whether any of `pieces` fits anywhere on `rug`. */
export function anyFits(rug: readonly number[], pieces: readonly Piece[]): boolean {
  for (const p of pieces) {
    for (let row = 0; row < SIZE; row++) {
      for (let col = 0; col < SIZE; col++) {
        if (fits(rug, p.cells, row, col)) return true;
      }
    }
  }
  return false;
}

/**
 * Whether every one of `pieces` can go on `rug`, one after another in some order, lines clearing
 * as they fill (a set is three pieces, so the search is small). Each fitting alone isn't enough:
 * two pieces can want the same gap.
 */
export function setFits(rug: readonly number[], pieces: readonly Piece[]): boolean {
  if (pieces.length === 0) return true;
  return pieces.some((piece, i) => {
    const rest = pieces.filter((_, j) => j !== i);
    for (let row = 0; row < SIZE; row++) {
      for (let col = 0; col < SIZE; col++) {
        const out = place(rug, piece, row, col);
        if (out && setFits(out.rug, rest)) return true;
      }
    }
    return false;
  });
}

/** Puts `piece` down with its top-left at (`row`, `col`), then clears every full line. */
export function place(
  rug: readonly number[],
  piece: Piece,
  row: number,
  col: number,
): { rug: number[]; cleared: Cleared } | null {
  if (!fits(rug, piece.cells, row, col)) return null;
  const next = [...rug];
  for (const [r, c] of piece.cells) next[(row + r) * SIZE + (col + c)] = piece.tint;
  const lines = [...Array(SIZE).keys()];
  const rows = lines.filter((y) => lines.every((x) => next[y * SIZE + x] !== 0));
  const cols = lines.filter((x) => lines.every((y) => next[y * SIZE + x] !== 0));
  for (const y of rows) for (const x of lines) next[y * SIZE + x] = 0;
  for (const x of cols) for (const y of lines) next[y * SIZE + x] = 0;
  return { rug: next, cleared: { rows, cols } };
}

export function start(rug: readonly number[], sets: number): BoxFortState {
  return { rug: [...rug], set: 0, sets, placed: [false, false, false], points: 0, combo: 0, lines: 0, over: null };
}

/**
 * Places the current set's piece in `slot`. Null when the run is over, the slot is placed or not
 * in the set, or the piece doesn't fit there. When it was the set's last piece, `setDone` is true
 * and the caller deals the next set (`deal`). Otherwise the run is stuck when none of the pieces
 * left fit.
 */
export function step(s: BoxFortState, pieces: readonly Piece[], slot: number, row: number, col: number): Step | null {
  if (s.over !== null || s.placed[slot] !== false) return null;
  const piece = pieces[slot] as Piece;
  const out = place(s.rug, piece, row, col);
  if (out === null) return null;
  const lines = out.cleared.rows.length + out.cleared.cols.length;
  const combo = lines > 0 ? s.combo + 1 : 0;
  const gained = piece.cells.length * SQUARE_POINTS + lineBonus(lines) + comboBonus(combo);
  const placed = s.placed.map((p, i) => p || i === slot);
  const setDone = placed.every(Boolean);
  const left = pieces.filter((_, i) => !placed[i]);
  const over = !setDone && !anyFits(out.rug, left) ? "stuck" : null;
  return {
    state: { ...s, rug: out.rug, placed, points: s.points + gained, combo, lines: s.lines + lines, over },
    gained,
    cleared: out.cleared,
    setDone,
  };
}

/** After a set is placed: the next set (stuck if none of it fits), or the full fort when `next` is null. */
export function deal(s: BoxFortState, next: readonly Piece[] | null): BoxFortState {
  if (next === null) return { ...s, points: s.points + FULL_FORT, over: "full" };
  return { ...s, set: s.set + 1, placed: [false, false, false], over: anyFits(s.rug, next) ? null : "stuck" };
}
