/**
 * Nine Lives' visible rules: what a player may enter and what the board shows. Light and pure, so
 * the web player imports it too. The maker, solver and grader live in their own files, server only.
 *
 * Cells are numbered 0..80 in reading order. A cell holds 0 (empty) or a digit 1..9.
 */

export const N = 81;

/** 81 digits, 0 for an empty cell. */
export type Cells = number[];

export type NineLivesMove = { k: "set"; i: number; d: number } | { k: "clear"; i: number };

/** A wrong number entered under the `"lives"` rules: it cost a life and never reached the board. */
export type Wrong = { i: number; d: number };

/**
 * The run's board: every cell (givens included), and the cells a hint filled, ascending. Under the
 * `"lives"` rules (spec, "Nine Lives: lives and hints") also the lives left and every wrong
 * number entered; a run on the first rules has neither.
 */
export type NineLivesState = { cells: Cells; hinted: number[]; lives?: number; wrong?: Wrong[] };

const range9 = [0, 1, 2, 3, 4, 5, 6, 7, 8];

export const ROWS: readonly (readonly number[])[] = range9.map((r) => range9.map((c) => r * 9 + c));
export const COLS: readonly (readonly number[])[] = range9.map((c) => range9.map((r) => r * 9 + c));
export const BOXES: readonly (readonly number[])[] = range9.map((b) =>
  range9.map((k) => (Math.floor(b / 3) * 3 + Math.floor(k / 3)) * 9 + (b % 3) * 3 + (k % 3)),
);
/** Every unit: rows 0..8, columns 9..17, boxes 18..26. */
export const UNITS: readonly (readonly number[])[] = [...ROWS, ...COLS, ...BOXES];

export const rowOf = (i: number): number => Math.floor(i / 9);
export const colOf = (i: number): number => i % 9;
export const boxOf = (i: number): number => Math.floor(rowOf(i) / 3) * 3 + Math.floor(colOf(i) / 3);

const PEERS: readonly (readonly number[])[] = Array.from({ length: N }, (_, i) => {
  const set = new Set([...ROWS[rowOf(i)]!, ...COLS[colOf(i)]!, ...BOXES[boxOf(i)]!]);
  set.delete(i);
  return [...set].sort((a, b) => a - b);
});

/** The 20 cells that share a row, column or box with `i`. */
export function peers(i: number): readonly number[] {
  return PEERS[i]!;
}

/** Cells whose digit repeats in one of their units, ascending. Givens count too. */
export function clashes(cells: Cells): number[] {
  const out: number[] = [];
  for (let i = 0; i < N; i++) {
    const d = cells[i]!;
    if (d !== 0 && PEERS[i]!.some((p) => cells[p] === d)) out.push(i);
  }
  return out;
}

export function isFull(cells: Cells): boolean {
  return cells.every((d) => d !== 0);
}

/** How many of the cells that started empty now hold a digit. */
export function placed(givens: Cells, cells: Cells): number {
  let n = 0;
  for (let i = 0; i < N; i++) if (givens[i] === 0 && cells[i] !== 0) n++;
  return n;
}

/** `placed` over the number of cells that started empty: 0..1, and spoiler-free. */
export function progressOf(givens: Cells, cells: Cells): number {
  const open = givens.filter((d) => d === 0).length;
  return open === 0 ? 1 : placed(givens, cells) / open;
}

const isInt = (v: unknown, lo: number, hi: number): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;

/** A move in its exact wire shape, or null. */
export function parseMove(raw: unknown): NineLivesMove | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const o = raw as Record<string, unknown>;
  const keys = Object.keys(o).sort().join(",");
  if (o.k === "set" && keys === "d,i,k" && isInt(o.i, 0, N - 1) && isInt(o.d, 1, 9)) {
    return { k: "set", i: o.i, d: o.d };
  }
  if (o.k === "clear" && keys === "i,k" && isInt(o.i, 0, N - 1)) return { k: "clear", i: o.i };
  return null;
}

/** The board after a move, or null when the cell is a given or was filled by a hint. */
export function applyMove(givens: Cells, s: NineLivesState, m: NineLivesMove): NineLivesState | null {
  if (givens[m.i] !== 0 || s.hinted.includes(m.i)) return null;
  const cells = [...s.cells];
  cells[m.i] = m.k === "set" ? m.d : 0;
  return { ...s, cells };
}

/** The board after the server's hint filled cell `i` with `d`. That cell is locked from now on. */
export function applyReveal(s: NineLivesState, r: { i: number; d: number }): NineLivesState {
  const cells = [...s.cells];
  cells[r.i] = r.d;
  const hinted = s.hinted.includes(r.i) ? s.hinted : [...s.hinted, r.i].sort((a, b) => a - b);
  return { ...s, cells, hinted };
}
