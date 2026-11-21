/**
 * Cat Nap's logic solver: it solves a quilt the way a person does, and grades it by the hardest
 * step it needed. Only the server uses it (the puzzle maker keeps quilts it can solve at the
 * day's grade). A quilt it solves has exactly one solution, since every step is forced.
 *
 * Steps, each tried only when every easier one is stuck:
 * 1. Singles: a row, column or patch with one cell left gets its cat.
 * 2. Confinement: a cell that would rule out every cell left in some row, column or patch can't
 *    hold a cat. (So a patch whose cells left all sit in one row clears the rest of that row.)
 * 3. Groups: k patches whose cells left lie within k rows clear those rows outside them, and the
 *    same for any two kinds of line or patch.
 * 4. Trial: a cat that leads, by steps 1 to 3, to a row, column or patch with no cell left can't
 *    be there.
 */
import { conflict, type Quilt } from "./rules";

export type Grade = 1 | 2 | 3 | 4;

/** The quilt's units: rows 0..n-1, columns n..2n-1, patches 2n..3n-1. */
type Shape = {
  n: number;
  units: number[][];
  unitsOf: number[][];
  /** The cells a cat here rules out. */
  hits: number[][];
};

type Board = { cand: Uint8Array; done: Uint8Array; cats: number[] };

function shapeOf(q: Quilt): Shape {
  const n = q.n;
  const size = n * n;
  const units: number[][] = Array.from({ length: 3 * n }, () => []);
  const unitsOf: number[][] = [];
  const hits: number[][] = [];
  for (let c = 0; c < size; c++) {
    const us = [Math.floor(c / n), n + (c % n), 2 * n + (q.patches[c] as number)];
    for (const u of us) units[u]!.push(c);
    unitsOf.push(us);
    const h: number[] = [];
    for (let d = 0; d < size; d++) if (conflict(q, c, d)) h.push(d);
    hits.push(h);
  }
  return { n, units, unitsOf, hits };
}

const copy = (b: Board): Board => ({ cand: b.cand.slice(), done: b.done.slice(), cats: [...b.cats] });

function place(sh: Shape, b: Board, c: number): void {
  b.cats.push(c);
  b.cand[c] = 0;
  for (const d of sh.hits[c]!) b.cand[d] = 0;
  for (const u of sh.unitsOf[c]!) b.done[u] = 1;
}

const left = (sh: Shape, b: Board, u: number): number[] => sh.units[u]!.filter((c) => b.cand[c] === 1);

/** A row, column or patch with no cat and no cell left. */
function broken(sh: Shape, b: Board): boolean {
  for (let u = 0; u < sh.units.length; u++) if (!b.done[u] && left(sh, b, u).length === 0) return true;
  return false;
}

function singles(sh: Shape, b: Board): boolean {
  for (let u = 0; u < sh.units.length; u++) {
    if (b.done[u]) continue;
    const l = left(sh, b, u);
    if (l.length === 1) {
      place(sh, b, l[0]!);
      return true;
    }
  }
  return false;
}

function confinement(sh: Shape, b: Board): boolean {
  let moved = false;
  for (let u = 0; u < sh.units.length; u++) {
    if (b.done[u]) continue;
    const l = left(sh, b, u);
    if (l.length === 0) continue;
    // The cells every cell left in u rules out.
    for (const d of sh.hits[l[0]!]!) {
      if (b.cand[d] === 1 && l.every((c) => sh.hits[c]!.includes(d))) {
        b.cand[d] = 0;
        moved = true;
      }
    }
  }
  return moved;
}

const KINDS = [0, 1, 2] as const; // rows, columns, patches

function groups(sh: Shape, b: Board): boolean {
  const n = sh.n;
  for (const a of KINDS) {
    for (const z of KINDS) {
      if (a === z) continue;
      const open = Array.from({ length: n }, (_, i) => i).filter((i) => !b.done[a * n + i]);
      const m = open.length;
      // Which units of kind z each open unit of kind a still reaches.
      const reach = open.map((i) => {
        let mask = 0;
        for (const c of left(sh, b, a * n + i)) mask |= 1 << (sh.unitsOf[c]![z]! - z * n);
        return mask;
      });
      for (let set = 1; set < 1 << m; set++) {
        const k = popcount(set);
        if (k < 2 || k >= m) continue;
        let union = 0;
        let inside = 0;
        for (let j = 0; j < m; j++) {
          if (set & (1 << j)) {
            union |= reach[j]!;
            inside |= 1 << open[j]!;
          }
        }
        if (popcount(union) !== k) continue;
        let moved = false;
        for (let t = 0; t < n; t++) {
          if (!(union & (1 << t))) continue;
          for (const c of left(sh, b, z * n + t)) {
            if (!(inside & (1 << (sh.unitsOf[c]![a]! - a * n)))) {
              b.cand[c] = 0;
              moved = true;
            }
          }
        }
        if (moved) return true;
      }
    }
  }
  return false;
}

function popcount(x: number): number {
  let k = 0;
  for (; x; x &= x - 1) k++;
  return k;
}

/** Steps 1 to `upTo` until stuck. Returns the hardest step used, 0 for none, or -1 on a contradiction. */
function run(sh: Shape, b: Board, upTo: Grade): number {
  let hardest = 0;
  for (;;) {
    if (broken(sh, b)) return -1;
    if (b.cats.length === sh.n) return hardest;
    let used = 0;
    if (singles(sh, b)) used = 1;
    else if (upTo >= 2 && confinement(sh, b)) used = 2;
    else if (upTo >= 3 && groups(sh, b)) used = 3;
    else if (upTo >= 4 && trial(sh, b)) used = 4;
    if (!used) return hardest;
    hardest = Math.max(hardest, used);
  }
}

function trial(sh: Shape, b: Board): boolean {
  for (let c = 0; c < b.cand.length; c++) {
    if (b.cand[c] !== 1) continue;
    const t = copy(b);
    place(sh, t, c);
    if (run(sh, t, 3) === -1) {
      b.cand[c] = 0;
      return true;
    }
  }
  return false;
}

/**
 * Solves by logic. Null when logic gets stuck or finds no solution; otherwise the hardest step it
 * needed and the solution, the column of each row's cat.
 */
export function grade(q: Quilt): { grade: Grade; solution: number[] } | null {
  const sh = shapeOf(q);
  const b: Board = { cand: new Uint8Array(q.n * q.n).fill(1), done: new Uint8Array(3 * q.n), cats: [] };
  const hardest = run(sh, b, 4);
  if (hardest <= 0 || b.cats.length !== q.n) return null;
  const solution = Array<number>(q.n);
  for (const c of b.cats) solution[Math.floor(c / q.n)] = c % q.n;
  return { grade: hardest as Grade, solution };
}

/** How many solutions the quilt has, by search, counting no further than `limit`. */
export function countSolutions(q: Quilt, limit: number): number {
  const n = q.n;
  let found = 0;
  const cols = new Uint8Array(n);
  const pats = new Uint8Array(n);
  const go = (r: number, prev: number): void => {
    if (r === n) {
      found++;
      return;
    }
    for (let c = 0; c < n && found < limit; c++) {
      const p = q.patches[r * n + c] as number;
      if (cols[c] || pats[p] || (prev >= 0 && Math.abs(prev - c) <= 1)) continue;
      cols[c] = pats[p] = 1;
      go(r + 1, c);
      cols[c] = pats[p] = 0;
    }
  };
  go(0, -1);
  return found;
}

/** A solution other than `solution`, by search, or null when it is the only one. */
export function otherSolution(q: Quilt, solution: number[]): number[] | null {
  const n = q.n;
  const cols = new Uint8Array(n);
  const pats = new Uint8Array(n);
  const path: number[] = [];
  const go = (r: number, prev: number): boolean => {
    if (r === n) return path.some((c, i) => c !== solution[i]);
    for (let c = 0; c < n; c++) {
      const p = q.patches[r * n + c] as number;
      if (cols[c] || pats[p] || (prev >= 0 && Math.abs(prev - c) <= 1)) continue;
      cols[c] = pats[p] = 1;
      path.push(c);
      if (go(r + 1, c)) return true;
      path.pop();
      cols[c] = pats[p] = 0;
    }
    return false;
  };
  return go(0, -1) ? path : null;
}
