/**
 * One Nine Lives board on screen, as plain values: the rules' board, the selection and the notes.
 * Each change is a pure function returning the next view and the move to send, if any. The rules
 * come from the server's own `grid.ts` (light: no maker, solver or grader on this thread).
 */
import { applyMove, applyReveal, clashes, isFull, N, peers, type NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

export type Puzzle = { givens: number[] };
export type BoardState = { cells: number[]; hinted: number[] };

export type View = {
  givens: number[];
  cells: number[];
  hinted: number[];
  clashes: Set<number>;
  selected: number | null;
  /** Pencil marks per cell, a bit per digit (bit d-1). The client's own; never sent. */
  notes: number[];
  notesOn: boolean;
  /** The last cell placed, and a count that changes each time, so its tile pops. */
  placed: { cell: number; count: number } | null;
  /** Changes when a move makes a new clash. */
  clashBump: number;
  /** Changes when "Not quite" appears. */
  notQuiteBump: number;
};

export type Step = { view: View; move?: NineLivesMove };

export const isLocked = (v: View, cell: number): boolean => v.givens[cell] !== 0 || v.hinted.includes(cell);
export const isSolved = (v: View): boolean => isFull(v.cells) && v.clashes.size === 0;
/** Full with a clash: with one solution, that's exactly "full and wrong". */
export const notQuite = (v: View): boolean => isFull(v.cells) && v.clashes.size > 0;
export const countOf = (v: View, digit: number): number => v.cells.filter((d) => d === digit).length;
/**
 * All nine of `digit` are placed and none clashes: its key rests. A clashing one keeps the key
 * awake, or a mistake could lock out the right cell.
 */
export const isDone = (v: View, digit: number): boolean =>
  countOf(v, digit) >= 9 && ![...v.clashes].some((i) => v.cells[i] === digit);
export const hasNote = (v: View, cell: number, digit: number): boolean => (v.notes[cell]! & (1 << (digit - 1))) !== 0;

export function start(puzzle: Puzzle, state?: BoardState): View {
  const cells = state ? [...state.cells] : [...puzzle.givens];
  const v: View = {
    givens: [...puzzle.givens],
    cells,
    hinted: state ? [...state.hinted] : [],
    clashes: new Set(clashes(cells)),
    selected: null,
    notes: new Array<number>(N).fill(0),
    notesOn: false,
    placed: null,
    clashBump: 0,
    notQuiteBump: 0,
  };
  const first = cells.indexOf(0);
  return { ...v, selected: isSolved(v) || first < 0 ? null : first };
}

export function tap(v: View, cell: number): View {
  return isSolved(v) ? v : { ...v, selected: cell };
}

/** Arrow keys: move the selection, wrapping at the edges. */
export function move(v: View, dr: number, dc: number): View {
  if (isSolved(v)) return v;
  const at = v.selected ?? 0;
  const r = (Math.floor(at / 9) + dr + 9) % 9;
  const c = ((at % 9) + dc + 9) % 9;
  return { ...v, selected: r * 9 + c };
}

export const toggleNotes = (v: View): View => ({ ...v, notesOn: !v.notesOn });

/** A number pressed: a note in notes mode, else the cell's digit (the same digit twice clears it). */
export function press(v: View, digit: number): Step {
  const cell = v.selected;
  if (cell === null || isSolved(v) || isLocked(v, cell)) return { view: v };
  if (v.notesOn) {
    if (v.cells[cell] !== 0) return { view: v };
    const notes = [...v.notes];
    notes[cell] = notes[cell]! ^ (1 << (digit - 1));
    return { view: { ...v, notes } };
  }
  return play(v, v.cells[cell] === digit ? { k: "clear", i: cell } : { k: "set", i: cell, d: digit });
}

export function erase(v: View): Step {
  const cell = v.selected;
  if (cell === null || isSolved(v) || isLocked(v, cell)) return { view: v };
  if (v.cells[cell] !== 0) return play(v, { k: "clear", i: cell });
  const notes = [...v.notes];
  notes[cell] = 0;
  return { view: { ...v, notes } };
}

/** The server's hint filled `i` with `d`. */
export function reveal(v: View, r: { i: number; d: number }): View {
  const next = applyReveal({ cells: v.cells, hinted: v.hinted }, r);
  return placed({ ...v, cells: next.cells, hinted: next.hinted, selected: r.i }, r.i, r.d);
}

/** The server's own board (a resumed run, or a correction): it wins. Notes stay. */
export function adopt(v: View, state: BoardState): View {
  return refresh({ ...v, cells: [...state.cells], hinted: [...state.hinted] });
}

function play(v: View, m: NineLivesMove): Step {
  const next = applyMove(v.givens, { cells: v.cells, hinted: v.hinted }, m);
  if (!next) return { view: v };
  const moved = { ...v, cells: next.cells };
  return { view: m.k === "set" ? placed(moved, m.i, m.d) : refresh(moved), move: m };
}

function placed(v: View, cell: number, digit: number): View {
  const notes = [...v.notes];
  notes[cell] = 0;
  // A placed digit can't be a note anywhere it would clash.
  for (const p of peers(cell)) notes[p] = notes[p]! & ~(1 << (digit - 1));
  const out = refresh({ ...v, notes, placed: { cell, count: (v.placed?.count ?? 0) + 1 } });
  const newClash = out.clashes.has(cell) && !v.clashes.has(cell);
  return newClash ? { ...out, clashBump: out.clashBump + 1 } : out;
}

function refresh(v: View): View {
  const out = { ...v, clashes: new Set(clashes(v.cells)) };
  const bump = notQuite(out) && !notQuite(v) ? 1 : 0;
  return { ...out, notQuiteBump: out.notQuiteBump + bump, selected: isSolved(out) ? null : out.selected };
}
