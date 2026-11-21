/**
 * A plain backtracking solver over candidate bitmasks (bit d-1 set: digit d is possible). Server
 * only: it counts solutions for the maker and fills random full grids.
 */
import { shuffle, type Rng } from "../../rules/rng";

import { N, peers, type Cells } from "./grid";

const ALL = 0x1ff;

/** Bit counts for every 9-bit mask. */
export const POP: Uint8Array = Uint8Array.from({ length: 512 }, (_, m) => {
  let n = 0;
  for (let x = m; x; x &= x - 1) n++;
  return n;
});

/** True when no filled cell repeats a peer. */
function consistent(cells: Cells): boolean {
  return cells.every((d, i) => d === 0 || peers(i).every((p) => cells[p] !== d));
}

const BOX_OF = Array.from({ length: N }, (_, i) => Math.floor(i / 27) * 3 + Math.floor((i % 9) / 3));

/**
 * Depth-first search, most constrained cell first, tracking each row's, column's and box's used
 * digits. `order` picks the order digits are tried in (random for `randomSolution`). Calls `found`
 * per solution; stops when it returns true. `cells` must be consistent.
 */
function search(cells: Cells, order: (bits: number) => number[], found: (grid: Cells) => boolean): void {
  const grid = [...cells];
  const row = new Int16Array(9);
  const col = new Int16Array(9);
  const box = new Int16Array(9);
  const mark = (i: number, d: number, on: boolean): void => {
    const b = 1 << (d - 1);
    const r = Math.floor(i / 9);
    const c = i % 9;
    const x = BOX_OF[i]!;
    if (on) {
      row[r]! |= b;
      col[c]! |= b;
      box[x]! |= b;
    } else {
      row[r]! &= ~b;
      col[c]! &= ~b;
      box[x]! &= ~b;
    }
  };
  for (let i = 0; i < N; i++) if (grid[i] !== 0) mark(i, grid[i]!, true);
  const step = (): boolean => {
    let best = -1;
    let bestMask = 0;
    let bestCount = 10;
    for (let i = 0; i < N; i++) {
      if (grid[i] !== 0) continue;
      const m = ALL & ~(row[Math.floor(i / 9)]! | col[i % 9]! | box[BOX_OF[i]!]!);
      const n = POP[m]!;
      if (n < bestCount) {
        best = i;
        bestMask = m;
        bestCount = n;
        if (n <= 1) break;
      }
    }
    if (best < 0) return found(grid);
    for (const d of order(bestMask)) {
      grid[best] = d;
      mark(best, d, true);
      if (step()) return true;
      mark(best, d, false);
    }
    grid[best] = 0;
    return false;
  };
  step();
}

const ascending = (bits: number): number[] => {
  const out: number[] = [];
  for (let d = 1; d <= 9; d++) if (bits & (1 << (d - 1))) out.push(d);
  return out;
};

/** How many solutions `cells` has, counting no further than `limit`. */
export function countSolutions(cells: Cells, limit: number): number {
  if (!consistent(cells)) return 0;
  let n = 0;
  search(cells, ascending, () => ++n >= limit);
  return n;
}

/** The first solution in digit order, or null. */
export function solveOne(cells: Cells): Cells | null {
  if (!consistent(cells)) return null;
  let out: Cells | null = null;
  search(cells, ascending, (grid) => {
    out = [...grid];
    return true;
  });
  return out;
}

/** A random full grid, decided only by `rng`. */
export function randomSolution(rng: Rng): Cells {
  let out: Cells = [];
  search(new Array<number>(N).fill(0), (bits) => shuffle(ascending(bits), rng), (grid) => {
    out = [...grid];
    return true;
  });
  return out;
}
