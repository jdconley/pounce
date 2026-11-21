/**
 * The logic solver that grades a puzzle by the hardest technique it needs (spec §1, §2). It
 * always uses the easiest technique that makes progress, so the grade is the least a person
 * needs. Server only.
 *
 * Every technique here is sound: it removes a candidate only when no solution can hold it. So when
 * the solver fills the grid, that grid is the one and only solution.
 */
import { BOXES, clashes, COLS, N, peers, ROWS, UNITS, type Cells } from "./grid";
import { POP } from "./solve";

/**
 * 1 singles; 2 locked candidates; 3 pairs; 4 triples, quads, x-wing and xy-wing; 5 swordfish,
 * xyz-wing and coloring (one-digit chains); 6 xy-chains. Grouped so each tier turns up often
 * enough as a puzzle's hardest step to make a daily puzzle quickly.
 */
export type Tier = 1 | 2 | 3 | 4 | 5 | 6;

/** A board being solved: digits, and each empty cell's candidate bits (bit d-1: digit d). */
export type Board = { vals: Uint8Array; cand: Uint16Array };

const ALL = 0x1ff;
const bit = (d: number): number => 1 << (d - 1);
const digitOf = (mask: number): number => 31 - Math.clz32(mask) + 1;

/** The board for `cells`, or null when two filled cells clash. */
export function boardOf(cells: Cells): Board | null {
  if (clashes(cells).length > 0) return null;
  const b: Board = { vals: new Uint8Array(N), cand: new Uint16Array(N).fill(ALL) };
  for (let i = 0; i < N; i++) if (cells[i] !== 0) place(b, i, cells[i]!);
  return b;
}

export function place(b: Board, i: number, d: number): void {
  b.vals[i] = d;
  b.cand[i] = 0;
  for (const p of peers(i)) b.cand[p]! &= ~bit(d);
}

/** Removes `mask` from cell `i`'s candidates; true when that changed anything. */
function drop(b: Board, i: number, mask: number): boolean {
  if ((b.cand[i]! & mask) === 0) return false;
  b.cand[i]! &= ~mask;
  return true;
}

/** Cells of `unit` that still have digit `d` as a candidate. */
function where(b: Board, unit: readonly number[], d: number): number[] {
  return unit.filter((i) => (b.cand[i]! & bit(d)) !== 0);
}

/** SEES[a * 81 + c] is 1 when a and c are peers. */
const SEES = new Uint8Array(N * N);
for (let a = 0; a < N; a++) for (const c of peers(a)) SEES[a * N + c] = 1;
const sees = (a: number, c: number): boolean => SEES[a * N + c] === 1;

/**
 * Calls `fn` with each k-element subset of `items` (the same array, refilled), until it returns
 * true. Returns whether it did.
 */
function someCombo<T>(items: readonly T[], k: number, fn: (set: readonly T[]) => boolean): boolean {
  const set: T[] = new Array<T>(k);
  const pick = (from: number, depth: number): boolean => {
    if (depth === k) return fn(set);
    for (let i = from; i <= items.length - (k - depth); i++) {
      set[depth] = items[i]!;
      if (pick(i + 1, depth + 1)) return true;
    }
    return false;
  };
  return pick(0, 0);
}

// Tier 1 ---------------------------------------------------------------------------------------

/** Fills every cell with one candidate left. */
export function nakedSingles(b: Board): boolean {
  let did = false;
  for (let i = 0; i < N; i++) {
    if (b.vals[i] === 0 && POP[b.cand[i]!] === 1) {
      place(b, i, digitOf(b.cand[i]!));
      did = true;
    }
  }
  return did;
}

/** Fills a digit that has one place left in a unit. */
export function hiddenSingles(b: Board): boolean {
  let did = false;
  for (const unit of UNITS) {
    let once = 0;
    let twice = 0;
    for (const i of unit) {
      twice |= once & b.cand[i]!;
      once |= b.cand[i]!;
    }
    let single = once & ~twice;
    while (single !== 0) {
      const m = single & -single;
      single &= single - 1;
      // An earlier placement in this pass may have taken the digit already.
      const i = unit.find((c) => (b.cand[c]! & m) !== 0);
      if (i !== undefined) {
        place(b, i, digitOf(m));
        did = true;
      }
    }
  }
  return did;
}

// Tier 2 ---------------------------------------------------------------------------------------

/** For each line, its three segments (the three cells it shares with each box it crosses). */
const SEGMENTS: readonly { line: readonly number[]; box: readonly number[]; cells: readonly number[] }[][] = [
  ...ROWS,
  ...COLS,
].map((line) =>
  [0, 1, 2].map((k) => {
    const cells = line.slice(k * 3, k * 3 + 3);
    return { line, box: BOXES.find((x) => x.includes(cells[0]!))!, cells };
  }),
);

/**
 * Pointing: a digit's places in a box all lie in one row or column, so the rest of that line
 * loses it. Claiming: a digit's places in a line all lie in one box, so the rest of the box loses
 * it. (A digit with one place left is a single, found first.)
 */
export function lockedCandidates(b: Board): boolean {
  let did = false;
  const segMask = (cells: readonly number[]): number => b.cand[cells[0]!]! | b.cand[cells[1]!]! | b.cand[cells[2]!]!;
  for (const segs of SEGMENTS) {
    const masks = segs.map((s) => segMask(s.cells));
    for (let k = 0; k < 3; k++) {
      const seg = segs[k]!;
      // Claiming: in this line, only this segment has these digits.
      const claim = masks[k]! & ~(masks[(k + 1) % 3]! | masks[(k + 2) % 3]!);
      if (claim) for (const i of seg.box) if (!seg.cells.includes(i)) did = drop(b, i, claim) || did;
      // Pointing: in this box, only this segment has these digits.
      const rest = seg.box.filter((i) => !seg.cells.includes(i)).reduce((m, i) => m | b.cand[i]!, 0);
      const point = masks[k]! & ~rest;
      if (point) for (const i of seg.line) if (!seg.cells.includes(i)) did = drop(b, i, point) || did;
    }
  }
  return did;
}

// Tiers 3 and 4 --------------------------------------------------------------------------------

/** k cells in a unit whose candidates together are exactly k digits: the unit's others lose them. */
export function nakedSubset(b: Board, k: number): boolean {
  let did = false;
  for (const unit of UNITS) {
    const open = unit.filter((i) => b.vals[i] === 0 && POP[b.cand[i]!]! <= k);
    if (open.length < k) continue;
    someCombo(open, k, (set) => {
      const union = set.reduce((m, i) => m | b.cand[i]!, 0);
      if (POP[union] !== k) return false;
      for (const i of unit) if (b.vals[i] === 0 && !set.includes(i)) did = drop(b, i, union) || did;
      return false;
    });
  }
  return did;
}

/** k digits that fit in only the same k cells of a unit: those cells lose every other digit. */
export function hiddenSubset(b: Board, k: number): boolean {
  let did = false;
  for (const unit of UNITS) {
    // places[d - 1]: the unit positions (bits 0..8) where digit d still fits.
    const places = new Array<number>(9).fill(0);
    unit.forEach((i, at) => {
      for (let m = b.cand[i]!; m !== 0; m &= m - 1) places[31 - Math.clz32(m & -m)]! |= 1 << at;
    });
    const digits = [0, 1, 2, 3, 4, 5, 6, 7, 8].filter((d) => places[d] !== 0 && POP[places[d]!]! <= k);
    if (digits.length < k) continue;
    someCombo(digits, k, (set) => {
      const where = set.reduce((m, d) => m | places[d]!, 0);
      if (POP[where] !== k) return false;
      const keep = set.reduce((m, d) => m | (1 << d), 0);
      unit.forEach((i, at) => {
        if (where & (1 << at)) did = drop(b, i, ALL & ~keep) || did;
      });
      return false;
    });
  }
  return did;
}

// Tier 5 ---------------------------------------------------------------------------------------

/**
 * X-wing (k = 2) and swordfish (k = 3): k lines where a digit fits only within the same k
 * crossing lines, so those crossing lines lose it everywhere else.
 */
export function fish(b: Board, k: number): boolean {
  let did = false;
  for (let d = 1; d <= 9; d++) {
    for (const [base, cover] of [
      [ROWS, COLS],
      [COLS, ROWS],
    ] as const) {
      const lines = base
        .map((line) => ({ line, at: where(b, line, d).map((i) => line.indexOf(i)) }))
        .filter((x) => x.at.length >= 2 && x.at.length <= k);
      someCombo(lines, k, (set) => {
        const covers = new Set(set.flatMap((x) => x.at));
        if (covers.size !== k) return false;
        for (const c of covers) {
          for (const i of cover[c]!) if (!set.some((x) => x.line.includes(i))) did = drop(b, i, bit(d)) || did;
        }
        return false;
      });
    }
  }
  return did;
}

/** Removes `mask` from every open cell that sees all of `cells`. */
function dropSeenByAll(b: Board, cells: number[], mask: number): boolean {
  let did = false;
  for (let i = 0; i < N; i++) {
    if (b.vals[i] === 0 && !cells.includes(i) && cells.every((c) => sees(i, c))) did = drop(b, i, mask) || did;
  }
  return did;
}

/** XY-wing: a pivot {x,y} sees pincers {x,z} and {y,z}; whatever sees both pincers loses z. */
export function xyWing(b: Board): boolean {
  for (let pivot = 0; pivot < N; pivot++) {
    const pm = b.cand[pivot]!;
    if (POP[pm] !== 2) continue;
    const wings = peers(pivot).filter((i) => POP[b.cand[i]!] === 2 && POP[b.cand[i]! & pm] === 1);
    const found = someCombo(wings, 2, ([a, c]) => {
      const z = b.cand[a!]! & b.cand[c!]!;
      return POP[z] === 1 && (z & pm) === 0 && dropSeenByAll(b, [a!, c!], z);
    });
    if (found) return true;
  }
  return false;
}

/** XYZ-wing: a pivot {x,y,z} sees pincers {x,z} and {y,z}; whatever sees all three loses z. */
export function xyzWing(b: Board): boolean {
  for (let pivot = 0; pivot < N; pivot++) {
    const pm = b.cand[pivot]!;
    if (POP[pm] !== 3) continue;
    const wings = peers(pivot).filter((i) => POP[b.cand[i]!] === 2 && (b.cand[i]! & ~pm) === 0);
    const found = someCombo(wings, 2, ([a, c]) => {
      const z = b.cand[a!]! & b.cand[c!]!;
      return POP[z] === 1 && dropSeenByAll(b, [pivot, a!, c!], z);
    });
    if (found) return true;
  }
  return false;
}

// Tier 6 ---------------------------------------------------------------------------------------

/**
 * Simple coloring: for one digit, link the two places of every unit that has exactly two, and
 * color each linked group in two alternating colors (one color is all true, the other all false).
 * Wrap: two cells of one color see each other, so that color is false. Trap: a cell that sees
 * both colors loses the digit.
 */
export function coloring(b: Board): boolean {
  for (let d = 1; d <= 9; d++) {
    const links = new Map<number, number[]>();
    for (const unit of UNITS) {
      const spots = where(b, unit, d);
      if (spots.length !== 2) continue;
      const [x, y] = spots as [number, number];
      links.set(x, [...(links.get(x) ?? []), y]);
      links.set(y, [...(links.get(y) ?? []), x]);
    }
    const color = new Map<number, number>();
    for (const start of links.keys()) {
      if (color.has(start)) continue;
      const group: number[] = [start];
      color.set(start, 0);
      for (let q = 0; q < group.length; q++) {
        const at = group[q]!;
        for (const next of links.get(at)!) {
          if (color.has(next)) continue;
          color.set(next, 1 - color.get(at)!);
          group.push(next);
        }
      }
      if (group.length < 3) continue;
      const side = [0, 1].map((c) => group.filter((i) => color.get(i) === c));
      for (const c of [0, 1]) {
        const cells = side[c]!;
        if (cells.some((x) => cells.some((y) => sees(x, y)))) {
          for (const i of cells) drop(b, i, bit(d));
          return true;
        }
      }
      let did = false;
      for (let i = 0; i < N; i++) {
        if (color.has(i) || (b.cand[i]! & bit(d)) === 0) continue;
        if (side[0]!.some((x) => sees(i, x)) && side[1]!.some((y) => sees(i, y))) {
          b.cand[i]! &= ~bit(d);
          did = true;
        }
      }
      if (did) return true;
    }
  }
  return false;
}

/**
 * XY-chain: a chain of two-candidate cells, each seeing the next and sharing the digit passed on.
 * If the first cell isn't z, the last one is; so whatever sees both ends loses z.
 */
export function xyChain(b: Board): boolean {
  const pairs: number[] = [];
  for (let i = 0; i < N; i++) if (POP[b.cand[i]!] === 2) pairs.push(i);
  for (const start of pairs) {
    for (const z of [b.cand[start]! & -b.cand[start]!, b.cand[start]! & (b.cand[start]! - 1)]) {
      // A state is (cell, the digit that cell must hold when start isn't z).
      const seen = new Set<number>();
      const queue: [number, number][] = [[start, b.cand[start]! & ~z]];
      seen.add(start * 512 + queue[0]![1]);
      for (let q = 0; q < queue.length; q++) {
        const [at, on] = queue[q]!;
        for (const next of pairs) {
          if (next === at || !sees(at, next) || (b.cand[next]! & on) === 0) continue;
          const nextOn = b.cand[next]! & ~on;
          if (seen.has(next * 512 + nextOn)) continue;
          seen.add(next * 512 + nextOn);
          if (nextOn === z && next !== start && dropSeenByAll(b, [start, next], z)) return true;
          queue.push([next, nextOn]);
        }
      }
    }
  }
  return false;
}

// The grader -----------------------------------------------------------------------------------

/** Every technique, easiest first, with its tier. */
export const TECHNIQUES: readonly [Tier, string, (b: Board) => boolean][] = [
  [1, "naked single", nakedSingles],
  [1, "hidden single", hiddenSingles],
  [2, "locked candidates", lockedCandidates],
  [3, "naked pair", (b) => nakedSubset(b, 2)],
  [3, "hidden pair", (b) => hiddenSubset(b, 2)],
  [4, "naked triple", (b) => nakedSubset(b, 3)],
  [4, "hidden triple", (b) => hiddenSubset(b, 3)],
  [4, "x-wing", (b) => fish(b, 2)],
  [4, "xy-wing", xyWing],
  [4, "naked quad", (b) => nakedSubset(b, 4)],
  [4, "hidden quad", (b) => hiddenSubset(b, 4)],
  [5, "swordfish", (b) => fish(b, 3)],
  [5, "xyz-wing", xyzWing],
  [5, "coloring", coloring],
  [6, "xy-chain", xyChain],
];

/**
 * Solves `givens` by logic using techniques up to `maxTier`. Returns the hardest tier it needed
 * and the solution, or null when it gets stuck (no solution, several, or harder than `maxTier`).
 */
export function grade(
  givens: Cells,
  maxTier: Tier = 6,
): { tier: Tier; hardest: string; solution: Cells } | null {
  const b = boardOf(givens);
  if (!b) return null;
  let tier: Tier = 1;
  let hardest = TECHNIQUES[0]![1];
  let rank = 0;
  for (;;) {
    if (b.vals.every((v) => v !== 0)) break;
    const k = TECHNIQUES.findIndex(([t, , run]) => t <= maxTier && run(b));
    if (k < 0) return null;
    if (k > rank) {
      rank = k;
      tier = TECHNIQUES[k]![0];
      hardest = TECHNIQUES[k]![1];
    }
  }
  // Placements never clash (each removes its digit from its peers), so a full board is the solution.
  return { tier, hardest, solution: [...b.vals] };
}
