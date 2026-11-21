/**
 * Box Fort's puzzle maker, server only. From the day's `Rng` and level it makes the whole run up
 * front: every set, in order, and the boxes already on the rug. Clients only ever see the sets
 * dealt so far (`module.ts`).
 *
 * A level changes three things (spec §2): how often awkward pieces come, how many boxes start on
 * the rug, and, on Sunday, how many sets there are. The maker doesn't prove every set can be
 * placed: running out of room is how a run normally ends.
 */
import { shuffle, type Rng } from "../../rules/rng";

import { SHAPES, type Piece, type Shape } from "./pieces";
import { anyFits, CLUTTER, SIZE } from "./rules";

import type { DayLevel } from "../days";

export type LevelSpec = {
  /** How often each tier is drawn: easy, medium, awkward. */
  weights: [number, number, number];
  /** At most this many awkward pieces in one set. */
  maxAwkward: number;
  /** Boxes on the rug at the start. */
  boxes: number;
  sets: number;
};

export const LEVELS: Record<DayLevel, LevelSpec> = {
  1: { weights: [6, 3, 1], maxAwkward: 1, boxes: 0, sets: 15 },
  2: { weights: [5, 4, 2], maxAwkward: 1, boxes: 4, sets: 15 },
  3: { weights: [4, 4, 3], maxAwkward: 1, boxes: 6, sets: 15 },
  4: { weights: [3, 4, 4], maxAwkward: 2, boxes: 8, sets: 15 },
  5: { weights: [2, 4, 5], maxAwkward: 2, boxes: 10, sets: 15 },
  6: { weights: [2, 3, 6], maxAwkward: 3, boxes: 12, sets: 15 },
  7: { weights: [3, 4, 4], maxAwkward: 2, boxes: 8, sets: 22 },
};

/** The whole day, server only. */
export type BoxFortPuzzle = { rug: number[]; sets: Piece[][] };

/** No row or column starts with more boxes than this. */
const MAX_PER_LINE = 5;
const TRIES = 50;
const TINTS = 6;

const TIERS: Shape[][] = [0, 1, 2].map((tier) => SHAPES.filter((s) => s.tier === tier));

const pick = <T>(items: readonly T[], rng: Rng): T => items[Math.floor(rng() * items.length)] as T;

function drawTier(weights: readonly number[], rng: Rng): number {
  let roll = rng() * weights.reduce((a, b) => a + b, 0);
  let tier = 0;
  while (tier < weights.length - 1 && roll >= (weights[tier] as number)) roll -= weights[tier++] as number;
  return tier;
}

function drawSet(spec: LevelSpec, rng: Rng): Piece[] {
  const set: Piece[] = [];
  let awkward = 0;
  while (set.length < 3) {
    const room = awkward < spec.maxAwkward;
    const tier = drawTier(room ? spec.weights : [spec.weights[0], spec.weights[1]], rng);
    if (tier === 2) awkward++;
    const s = pick(TIERS[tier] as Shape[], rng);
    set.push({ id: s.id, tint: 1 + Math.floor(rng() * TINTS), cells: s.cells });
  }
  return set;
}

function crowded(rug: readonly number[]): boolean {
  const lines = [...Array(SIZE).keys()];
  return lines.some(
    (i) =>
      lines.filter((j) => rug[i * SIZE + j] !== 0).length > MAX_PER_LINE ||
      lines.filter((j) => rug[j * SIZE + i] !== 0).length > MAX_PER_LINE,
  );
}

/**
 * Up to `boxes` boxes at random spots, with no line over 5 boxes and room for every piece of the
 * first set. When `TRIES` layouts fail, it tries again with one box fewer.
 */
export function clutter(rng: Rng, boxes: number, first: readonly Piece[]): number[] {
  const spots = [...Array(SIZE * SIZE).keys()];
  for (let count = boxes; count > 0; count--) {
    for (let t = 0; t < TRIES; t++) {
      const rug = Array<number>(SIZE * SIZE).fill(0);
      for (const at of shuffle(spots, rng).slice(0, count)) rug[at] = CLUTTER;
      if (!crowded(rug) && first.every((p) => anyFits(rug, [p]))) return rug;
    }
  }
  return Array<number>(SIZE * SIZE).fill(0);
}

export function make(rng: Rng, level: DayLevel): BoxFortPuzzle {
  const spec = LEVELS[level];
  const sets = Array.from({ length: spec.sets }, () => drawSet(spec, rng));
  return { rug: clutter(rng, spec.boxes, sets[0] as Piece[]), sets };
}
