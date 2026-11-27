/**
 * One Nine Lives board on screen, as plain values: the rules' board, the selection and the notes.
 * Each change is a pure function returning the next view and the move to send, if any. The rules
 * come from the server's own `grid.ts` (light: no maker, solver or grader on this thread).
 *
 * Two sets of rules (docs/daily-protocol.md "## Nine Lives"), fixed per run when it starts:
 *
 * - **Lives** (`state.rules === "lives"`, every run the web starts now): three lives and three
 *   hints. A set shows at once and waits for the server's answer (`pending`); a right digit then
 *   stays and locks, a wrong one comes off the server's board (`wrongAt`), shows red in its cell
 *   (`wrong`) and costs a life. Erase clears a wrong digit here, never on the server. The third
 *   wrong number fills in the solution (`solution`).
 * - **The first rules** (a run an older app started): any digit anywhere, clashes, "Not quite" on
 *   a full grid with a mistake, unlimited hints. `lives` and `hintsLeft` are null.
 */
import { applyMove, applyReveal, clashes, isFull, N, peers, type NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

export type Puzzle = { givens: number[] };

/** A wrong number the server took a life for. */
export type Wrong = { i: number; d: number };

/** The server's public state: the first rules' two fields, and the lives rules' extra ones. */
export type BoardState = {
  cells: number[];
  hinted: number[];
  rules?: "lives";
  lives?: number;
  hintsLeft?: number;
  /** Every wrong number entered, in order. Never in `cells`. */
  wrong?: Wrong[];
  /** The whole solution, once the run ended out of lives. */
  solution?: number[];
};

/** What a moves answer reveals under the lives rules, one per wrong set, then the solution. */
export type MoveReveal = { k: "wrong"; i: number; d: number; lives: number } | { k: "solution"; cells: number[] };

export const LIVES = 3;
export const HINTS = 3;

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
  /** Changes when a move makes a new clash (first rules) or a number is wrong (lives). */
  clashBump: number;
  /** Changes when "Not quite" appears. */
  notQuiteBump: number;
  /** Lives left, or null under the first rules. */
  lives: number | null;
  /** Hints left, or null under the first rules (unlimited). */
  hintsLeft: number | null;
  /** The wrong digit shown in each cell, 0 for none (lives). Not on the server's board. */
  wrong: number[];
  /** Every digit known wrong in each cell, a bit per digit: never sent again (lives). */
  tried: number[];
  /** Cells whose set waits for the server's answer (lives). Locked until it comes. */
  pending: number[];
  /** The solution, once the run ended out of lives: the board fills it in. */
  solution: number[] | null;
  /** The last wrong number: its cell, and a count that changes each time, so its tile shakes. */
  missed: { cell: number; count: number } | null;
};

export type Step = { view: View; move?: NineLivesMove };

export const hasLives = (v: View): boolean => v.lives !== null;
/** Out of lives: the solution is on the board. */
export const isOut = (v: View): boolean => v.solution !== null;
export const isLocked = (v: View, cell: number): boolean =>
  v.givens[cell] !== 0 || v.hinted.includes(cell) || (hasLives(v) && v.cells[cell] !== 0);
export const isSolved = (v: View): boolean => !isOut(v) && isFull(v.cells) && v.clashes.size === 0 && v.pending.length === 0;
/** Over, either way: nothing more goes in. */
const isOver = (v: View): boolean => isSolved(v) || isOut(v);
/** Full with a clash: with one solution, that's exactly "full and wrong" (first rules only). */
export const notQuite = (v: View): boolean => !hasLives(v) && isFull(v.cells) && v.clashes.size > 0;
export const countOf = (v: View, digit: number): number => v.cells.filter((d) => d === digit).length;
/**
 * All nine of `digit` are placed and none clashes: its key rests. A clashing one keeps the key
 * awake, or a mistake could lock out the right cell.
 */
export const isDone = (v: View, digit: number): boolean =>
  countOf(v, digit) >= 9 && ![...v.clashes].some((i) => v.cells[i] === digit);
export const hasNote = (v: View, cell: number, digit: number): boolean => (v.notes[cell]! & (1 << (digit - 1))) !== 0;
/** The hint button has nothing left to give. */
export const hintsSpent = (v: View): boolean => v.hintsLeft === 0;

const bit = (d: number): number => 1 << (d - 1);

/** The lives rules' fields from the server's state; the first rules' when it has none. */
function livesOf(state: BoardState | undefined): Pick<View, "lives" | "hintsLeft" | "wrong" | "tried" | "solution"> {
  const wrong = new Array<number>(N).fill(0);
  const tried = new Array<number>(N).fill(0);
  if (state?.rules !== "lives") return { lives: null, hintsLeft: null, wrong, tried, solution: null };
  for (const w of state.wrong ?? []) {
    tried[w.i] = tried[w.i]! | bit(w.d);
    // The latest wrong number in a cell still open shows there.
    if (state.cells[w.i] === 0) wrong[w.i] = w.d;
  }
  return {
    lives: state.lives ?? LIVES,
    hintsLeft: state.hintsLeft ?? HINTS,
    wrong,
    tried,
    solution: state.solution ? [...state.solution] : null,
  };
}

export function start(puzzle: Puzzle, state?: BoardState): View {
  const cells = state ? [...state.cells] : [...puzzle.givens];
  const lives = livesOf(state);
  const v: View = {
    givens: [...puzzle.givens],
    cells,
    hinted: state ? [...state.hinted] : [],
    clashes: new Set(lives.lives === null ? clashes(cells) : []),
    selected: null,
    notes: new Array<number>(N).fill(0),
    notesOn: false,
    placed: null,
    clashBump: 0,
    notQuiteBump: 0,
    pending: [],
    missed: null,
    ...lives,
  };
  const first = cells.indexOf(0);
  return { ...v, selected: isOver(v) || first < 0 ? null : first };
}

export function tap(v: View, cell: number): View {
  return isOver(v) ? v : { ...v, selected: cell };
}

/** Arrow keys: move the selection, wrapping at the edges. */
export function move(v: View, dr: number, dc: number): View {
  if (isOver(v)) return v;
  const at = v.selected ?? 0;
  const r = (Math.floor(at / 9) + dr + 9) % 9;
  const c = ((at % 9) + dc + 9) % 9;
  return { ...v, selected: r * 9 + c };
}

export const toggleNotes = (v: View): View => ({ ...v, notesOn: !v.notesOn });

/**
 * A number pressed: a note in notes mode, else the cell's digit. First rules: the same digit
 * twice clears it. Lives: a set, shown at once and waiting for the server; a digit already known
 * wrong in that cell shows wrong again, and isn't sent.
 */
export function press(v: View, digit: number): Step {
  const cell = v.selected;
  if (cell === null || isOver(v) || isLocked(v, cell)) return { view: v };
  if (v.notesOn) {
    if (v.cells[cell] !== 0 || v.wrong[cell] !== 0) return { view: v };
    const notes = [...v.notes];
    notes[cell] = notes[cell]! ^ bit(digit);
    return { view: { ...v, notes } };
  }
  if (!hasLives(v)) return play(v, v.cells[cell] === digit ? { k: "clear", i: cell } : { k: "set", i: cell, d: digit });
  if (v.tried[cell]! & bit(digit)) {
    const wrong = [...v.wrong];
    wrong[cell] = digit;
    return { view: { ...v, wrong, missed: { cell, count: (v.missed?.count ?? 0) + 1 }, clashBump: v.clashBump + 1 } };
  }
  const cells = [...v.cells];
  cells[cell] = digit;
  const wrong = [...v.wrong];
  wrong[cell] = 0;
  const m: NineLivesMove = { k: "set", i: cell, d: digit };
  return { view: placed({ ...v, cells, wrong, pending: [...v.pending, cell] }, cell, digit), move: m };
}

/** Erase: a digit (first rules), a wrong digit (lives: here only, never sent), or the notes. */
export function erase(v: View): Step {
  const cell = v.selected;
  if (cell === null || isOver(v) || isLocked(v, cell)) return { view: v };
  if (!hasLives(v) && v.cells[cell] !== 0) return play(v, { k: "clear", i: cell });
  if (v.wrong[cell] !== 0) {
    const wrong = [...v.wrong];
    wrong[cell] = 0;
    return { view: { ...v, wrong } };
  }
  const notes = [...v.notes];
  notes[cell] = 0;
  return { view: { ...v, notes } };
}

/**
 * The server answered the batch that carried `m` (lives). A set it didn't call wrong (`wrongAt`
 * comes first, with the batch's reveals) was right: it stays, locked.
 */
export function answered(v: View, m: NineLivesMove): View {
  if (m.k !== "set" || !v.pending.includes(m.i)) return v;
  return refresh({ ...v, pending: v.pending.filter((i) => i !== m.i) });
}

/** The server called a set wrong: it comes off the board, shows red, and a life goes. */
export function wrongAt(v: View, r: { i: number; d: number; lives: number }): View {
  const cells = [...v.cells];
  if (cells[r.i] === r.d && !v.hinted.includes(r.i)) cells[r.i] = 0;
  const wrong = [...v.wrong];
  wrong[r.i] = r.d;
  const tried = [...v.tried];
  tried[r.i] = tried[r.i]! | bit(r.d);
  return {
    ...v,
    cells,
    wrong,
    tried,
    pending: v.pending.filter((i) => i !== r.i),
    lives: Math.max(0, r.lives),
    missed: { cell: r.i, count: (v.missed?.count ?? 0) + 1 },
    clashBump: v.clashBump + 1,
  };
}

/** Out of lives: the server's solution fills in the board. */
export function revealSolution(v: View, cells: number[]): View {
  return { ...v, solution: [...cells], pending: [], selected: null, lives: 0 };
}

/** The server's hint filled `i` with `d`. */
export function reveal(v: View, r: { i: number; d: number }): View {
  const next = applyReveal({ cells: v.cells, hinted: v.hinted }, r);
  const wrong = [...v.wrong];
  wrong[r.i] = 0;
  const hintsLeft = v.hintsLeft === null ? null : Math.max(0, v.hintsLeft - 1);
  const out = { ...v, cells: next.cells, hinted: next.hinted, selected: r.i, wrong, hintsLeft, pending: v.pending.filter((i) => i !== r.i) };
  return placed(out, r.i, r.d);
}

/** The server's own board (a resumed run, or a correction): it wins. Notes stay. */
export function adopt(v: View, state: BoardState): View {
  return refresh({ ...v, cells: [...state.cells], hinted: [...state.hinted], pending: [], ...livesOf(state) });
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
  for (const p of peers(cell)) notes[p] = notes[p]! & ~bit(digit);
  const out = refresh({ ...v, notes, placed: { cell, count: (v.placed?.count ?? 0) + 1 } });
  const newClash = out.clashes.has(cell) && !v.clashes.has(cell);
  return newClash ? { ...out, clashBump: out.clashBump + 1 } : out;
}

function refresh(v: View): View {
  // Under lives a clash isn't the test (the server is): only a wrong number shows red.
  const out = { ...v, clashes: new Set(hasLives(v) ? [] : clashes(v.cells)) };
  const bump = notQuite(out) && !notQuite(v) ? 1 : 0;
  return { ...out, notQuiteBump: out.notQuiteBump + bump, selected: isOver(out) ? null : out.selected };
}
