/**
 * Cat Nap's rules: the quilt, the marks a player makes on it, and the rules a board can visibly
 * break. Small and pure, so the web player imports it as is; the Swift copy
 * (`PounceKit/Daily/CatNap/CatNapRules.swift`) must pass the golden vectors these write
 * (`fixtures/daily/cat-nap/vectors.json`).
 *
 * The puzzle: an N by N quilt of N patches. One sleeping cat in every row, every column and every
 * patch, and no two cats touch, not even at a corner.
 */

/** A cell's mark: 0 empty, 1 "no cat here", 2 a cat. */
export type Mark = 0 | 1 | 2;
/** The quilt: its size and each cell's patch (0..n-1), row by row. */
export type Quilt = { n: number; patches: number[] };
/** A board: every cell's mark, and the cats a hint placed (locked), ascending. */
export type NapState = { cells: Mark[]; hinted: number[] };
/** Mark cells "no cat" (`x`), put a cat on one, or clear them. A drag marks many at once. */
export type NapMove = { k: "mark"; cells: number[]; to: "x" | "cat" | "clear" };
/** The visible rules a board breaks: lines and patches holding two or more cats, and touching cats. */
export type Clashes = { rows: number[]; cols: number[]; patches: number[]; touching: number[]; cells: number[] };

/** The largest quilt is 9 by 9, so a move names at most 81 cells. */
export const MAX_CELLS = 81;

const MARK_OF = { x: 1, cat: 2, clear: 0 } as const;

export function emptyState(q: Quilt): NapState {
  return { cells: Array<Mark>(q.n * q.n).fill(0), hinted: [] };
}

/** The move's exact shape, or null: `{ k: "mark", cells, to }`, nothing more. */
export function parseNapMove(raw: unknown): NapMove | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const keys = Object.keys(raw);
  if (keys.length !== 3) return null;
  const { k, cells, to } = raw as Record<string, unknown>;
  if (k !== "mark" || (to !== "x" && to !== "cat" && to !== "clear")) return null;
  if (!Array.isArray(cells) || cells.length < 1 || cells.length > MAX_CELLS) return null;
  if (!cells.every((c) => Number.isInteger(c) && (c as number) >= 0)) return null;
  if (new Set(cells).size !== cells.length) return null;
  if (to === "cat" && cells.length !== 1) return null;
  return { k, cells: [...(cells as number[])], to };
}

/** The board after a move, or null when it is illegal: a cell off the quilt, or a hinted cat. */
export function applyMark(q: Quilt, s: NapState, m: NapMove): NapState | null {
  const size = q.n * q.n;
  if (m.cells.some((c) => c >= size || s.hinted.includes(c))) return null;
  const cells = [...s.cells];
  for (const c of m.cells) cells[c] = MARK_OF[m.to];
  return { cells, hinted: [...s.hinted] };
}

const touches = (n: number, a: number, b: number): boolean =>
  a !== b && Math.abs(Math.floor(a / n) - Math.floor(b / n)) <= 1 && Math.abs((a % n) - (b % n)) <= 1;

/** Whether cats at `a` and `b` break a rule together: same row, column or patch, or touching. */
export function conflict(q: Quilt, a: number, b: number): boolean {
  const n = q.n;
  if (a === b) return false;
  return (
    Math.floor(a / n) === Math.floor(b / n) ||
    a % n === b % n ||
    q.patches[a] === q.patches[b] ||
    touches(n, a, b)
  );
}

const catsOf = (s: NapState): number[] => s.cells.flatMap((m, i) => (m === 2 ? [i] : []));

export function clashes(q: Quilt, s: NapState): Clashes {
  const n = q.n;
  const cats = catsOf(s);
  const crowded = (key: (c: number) => number): number[] => {
    const count = new Map<number, number>();
    for (const c of cats) count.set(key(c), (count.get(key(c)) ?? 0) + 1);
    return [...count].filter(([, k]) => k > 1).map(([v]) => v).sort((a, b) => a - b);
  };
  const rows = crowded((c) => Math.floor(c / n));
  const cols = crowded((c) => c % n);
  const patches = crowded((c) => q.patches[c] as number);
  const touching = cats.filter((a) => cats.some((b) => touches(n, a, b)));
  const cells = cats.filter(
    (c) =>
      rows.includes(Math.floor(c / n)) || cols.includes(c % n) || patches.includes(q.patches[c] as number) || touching.includes(c),
  );
  return { rows, cols, patches, touching, cells };
}

/** N cats and no broken rule. With one solution, that is the solution. */
export function complete(q: Quilt, s: NapState): boolean {
  return catsOf(s).length === q.n && clashes(q, s).cells.length === 0;
}

/** Cats not in any clash, at most n: progress that gives nothing away. */
export function catsPlaced(q: Quilt, s: NapState): number {
  const bad = clashes(q, s).cells;
  return Math.min(q.n, catsOf(s).filter((c) => !bad.includes(c)).length);
}

/**
 * The cell a hint fills: the first row, top down, whose solution cell is not a cat or is a cat
 * that clashes with another. Null when there is none (the board is solved).
 */
export function hintTarget(q: Quilt, s: NapState, solution: number[]): number | null {
  const cats = catsOf(s);
  for (let r = 0; r < q.n; r++) {
    const cell = r * q.n + (solution[r] as number);
    if (s.cells[cell] !== 2 || cats.some((o) => conflict(q, cell, o))) return cell;
  }
  return null;
}

/** A hint's cat: locked at `cell`, and every unlocked cat that clashes with it cleared. */
export function applyHint(q: Quilt, s: NapState, cell: number): NapState {
  const cells = s.cells.map((m, i) => (m === 2 && conflict(q, cell, i) && !s.hinted.includes(i) ? 0 : m));
  cells[cell] = 2;
  const hinted = s.hinted.includes(cell) ? [...s.hinted] : [...s.hinted, cell].sort((a, b) => a - b);
  return { cells, hinted };
}

/** A tap's move: empty → no cat → cat → empty. Null on a hinted cat. */
export function tapMove(s: NapState, cell: number): NapMove | null {
  if (s.hinted.includes(cell)) return null;
  const to = (["x", "cat", "clear"] as const)[s.cells[cell] as Mark];
  return { k: "mark", cells: [cell], to };
}

/** What a drag from `start` paints: "no cat" from an empty cell, clearing from a "no cat" cell. */
export function dragPaint(s: NapState, start: number): "x" | "clear" | null {
  if (s.hinted.includes(start)) return null;
  const m = s.cells[start];
  return m === 0 ? "x" : m === 1 ? "clear" : null;
}

/**
 * A drag's move: the cells it passed that its paint changes, in the order passed, each once.
 * Painting "no cat" takes empty cells; clearing takes "no cat" cells. Cats are never touched.
 */
export function dragMove(s: NapState, paint: "x" | "clear", passed: number[]): NapMove | null {
  const want: Mark = paint === "x" ? 0 : 1;
  const cells = [...new Set(passed)].filter((c) => s.cells[c] === want && !s.hinted.includes(c));
  return cells.length ? { k: "mark", cells, to: paint } : null;
}
