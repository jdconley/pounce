/**
 * Cat Nap's puzzle maker, server only. From the day's seeded `Rng` and level it places a
 * solution, grows one patch around each of its cats, and keeps the quilt only when the logic
 * solver (`logic.ts`) solves it at the day's grade. Deterministic for a seed.
 */
import { grade as gradeOf, otherSolution, type Grade } from "./logic";

import type { DayLevel } from "../days";
import type { Quilt } from "./rules";
import type { Rng } from "../../rules/rng";

/** The whole puzzle, solution included. Never sent to a client (`publicPuzzle` strips it). */
export type NapPuzzle = Quilt & { solution: number[]; level: DayLevel; grade: Grade };

/** The quilt grows from 5 by 5 on Monday to 8 by 8 on Saturday, and 9 by 9 on Sunday. */
export const SIZES: Record<DayLevel, number> = { 1: 5, 2: 6, 3: 7, 4: 7, 5: 8, 6: 8, 7: 9 };

/** The logic each day needs, as [easiest, hardest] grade accepted: deeper later in the week. */
export const GRADES: Record<DayLevel, readonly [Grade, Grade]> = {
  1: [1, 2],
  2: [2, 2],
  3: [2, 3],
  4: [3, 3],
  5: [3, 4],
  6: [4, 4],
  7: [3, 3],
};

/** Quilts tried for the day's grade before settling for any quilt logic can solve. */
export const TRIES = 600;
/** Quilts grown around one solution before placing a new one. */
const PER_SOLUTION = 12;
/** Past this, something is wrong with the maker: no seed has come close in testing. */
export const GIVE_UP = 20_000;

export type MakeOptions = { band?: readonly [Grade, Grade]; tries?: number; giveUp?: number };

export function makeNap(rng: Rng, level: DayLevel, opts: MakeOptions = {}): NapPuzzle {
  const n = SIZES[level];
  const [lo, hi] = opts.band ?? GRADES[level];
  const tries = opts.tries ?? TRIES;
  const giveUp = opts.giveUp ?? GIVE_UP;
  let fallback: NapPuzzle | null = null;
  let solution: number[] = [];
  for (let t = 0; t < giveUp; t++) {
    if (t % PER_SOLUTION === 0) solution = placeCats(n, rng);
    const patches = repair(n, growPatches(n, solution, rng), solution, rng);
    const graded = patches && gradeOf({ n, patches });
    if (!graded) continue;
    const found = graded.grade < lo ? harden(n, patches, solution, graded.grade, hi, lo, rng) : { patches, grade: graded.grade };
    const puzzle: NapPuzzle = { n, patches: canonical(found.patches), solution, level, grade: found.grade };
    if (found.grade >= lo && found.grade <= hi) return puzzle;
    fallback ??= puzzle;
    if (t + 1 >= tries) return fallback;
  }
  throw new Error(`cat-nap: no quilt for level ${level} in ${giveUp} tries`);
}

/** A column per row, no two cats in one column and none touching, by shuffled search. */
export function placeCats(n: number, rng: Rng): number[] {
  const cols: number[] = [];
  const used = new Set<number>();
  const go = (r: number): boolean => {
    if (r === n) return true;
    const order = Array.from({ length: n }, (_, i) => i);
    for (let i = n - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [order[i], order[j]] = [order[j]!, order[i]!];
    }
    for (const c of order) {
      if (used.has(c) || (r > 0 && Math.abs(cols[r - 1]! - c) <= 1)) continue;
      cols.push(c);
      used.add(c);
      if (go(r + 1)) return true;
      cols.pop();
      used.delete(c);
    }
    return false;
  };
  go(0);
  return cols;
}

/**
 * One patch around each cat, grown a cell at a time into a neighbouring free cell (sharing a
 * side) until the quilt is full, so every patch is in one piece. Each patch grows at its own
 * random pace, so some stay small and some sprawl. Patch r holds row r's cat until `canonical`
 * renumbers them.
 */
export function growPatches(n: number, solution: number[], rng: Rng): number[] {
  const size = n * n;
  const owner = new Int16Array(size).fill(-1);
  solution.forEach((c, r) => (owner[r * n + c] = r));
  const pace = solution.map(() => 0.1 + rng() * rng());
  let free = size - n;
  while (free > 0) {
    const edges: number[][] = solution.map(() => []);
    for (let c = 0; c < size; c++) {
      if (owner[c] !== -1) continue;
      for (const d of sides(n, c)) {
        const o = owner[d]!;
        if (o !== -1 && !edges[o]!.includes(c)) edges[o]!.push(c);
      }
    }
    const open = pace.flatMap((_, o) => (edges[o]!.length ? [o] : []));
    let pick = rng() * open.reduce((sum, o) => sum + pace[o]!, 0);
    let p = open.at(-1)!;
    for (const o of open) {
      pick -= pace[o]!;
      if (pick < 0) {
        p = o;
        break;
      }
    }
    const cells = edges[p]!;
    owner[cells[Math.floor(rng() * cells.length)]!] = p;
    free--;
  }
  return Array.from(owner);
}

function sides(n: number, c: number): number[] {
  const r = Math.floor(c / n);
  const k = c % n;
  const out: number[] = [];
  if (r > 0) out.push(c - n);
  if (r < n - 1) out.push(c + n);
  if (k > 0) out.push(c - 1);
  if (k < n - 1) out.push(c + 1);
  return out;
}

/** Cell moves tried to rule out the other solutions before regrowing. */
const REPAIRS = 60;

/**
 * Makes `solution` the quilt's only one, or gives up (null): while another solution exists, one
 * of its cats that isn't a solution cat moves into a neighbouring patch, which leaves that other
 * solution two cats in one patch. A patch never loses its solution cat or falls into two pieces.
 */
export function repair(n: number, patches: number[], solution: number[], rng: Rng): number[] | null {
  const q = { n, patches: [...patches] };
  const anchors = new Set(solution.map((c, r) => r * n + c));
  for (let step = 0; step < REPAIRS; step++) {
    const other = otherSolution(q, solution);
    if (!other) return q.patches;
    const moves = movesFrom(q, other.flatMap((col, r) => (anchors.has(r * n + col) ? [] : [r * n + col])));
    if (!moves.length) return null;
    const [c, to] = moves[Math.floor(rng() * moves.length)]!;
    q.patches[c] = to;
  }
  return null;
}

/** Cell moves tried to make a quilt's logic deeper. */
const HARDEN = 40;

/**
 * Deeper logic for the same solution: random cells move to a neighbouring patch, and a move is
 * kept when the quilt still has one solution and its grade doesn't fall or pass `hi`. Stops at
 * `goal`.
 */
export function harden(
  n: number,
  patches: number[],
  solution: number[],
  start: Grade,
  hi: Grade,
  goal: Grade,
  rng: Rng,
): { patches: number[]; grade: Grade } {
  const anchors = new Set(solution.map((c, r) => r * n + c));
  const free = Array.from({ length: n * n }, (_, i) => i).filter((c) => !anchors.has(c));
  let best = { patches, grade: start };
  for (let step = 0; step < HARDEN && best.grade < goal; step++) {
    const q = { n, patches: best.patches };
    const moves = movesFrom(q, free);
    const [c, to] = moves[Math.floor(rng() * moves.length)]!;
    const next = { n, patches: q.patches.map((p, i) => (i === c ? to : p)) };
    if (otherSolution(next, solution)) continue;
    const graded = gradeOf(next);
    if (graded && graded.grade >= best.grade && graded.grade <= hi) best = { patches: next.patches, grade: graded.grade };
  }
  return best;
}

/** Every move of a cell in `cells` into a neighbouring patch that leaves its own patch whole. */
function movesFrom(q: Quilt, cells: number[]): [number, number][] {
  const moves: [number, number][] = [];
  for (const c of cells) {
    let whole: boolean | null = null;
    for (const d of sides(q.n, c)) {
      const to = q.patches[d]!;
      if (to === q.patches[c] || moves.some(([mc, mt]) => mc === c && mt === to)) continue;
      whole ??= staysWhole(q, c);
      if (whole) moves.push([c, to]);
    }
  }
  return moves;
}

/** Whether the patch holding `c` stays in one piece without it. */
function staysWhole(q: Quilt, c: number): boolean {
  const p = q.patches[c];
  const cells = q.patches.flatMap((x, i) => (x === p && i !== c ? [i] : []));
  const seen = new Set([cells[0]!]);
  const todo = [cells[0]!];
  while (todo.length) {
    for (const d of sides(q.n, todo.pop()!)) {
      if (d !== c && q.patches[d] === p && !seen.has(d)) {
        seen.add(d);
        todo.push(d);
      }
    }
  }
  return seen.size === cells.length;
}

/** Patches numbered in reading order, so the numbers say nothing about where the cats are. */
function canonical(patches: number[]): number[] {
  const rename = new Map<number, number>();
  return patches.map((p) => {
    if (!rename.has(p)) rename.set(p, rename.size);
    return rename.get(p)!;
  });
}
