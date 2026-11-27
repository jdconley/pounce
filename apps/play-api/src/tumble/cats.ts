import { highest, restingY, setDown, TOTAL, W, type Box, type Trick } from "./box";
import { toyAt } from "./queue";
import { rngFloat, rngNext } from "./rng";

import type { Rot } from "./toys";
import type { Seed } from "../rules/rng";

/**
 * House Cats (spec §6.9): where a cat puts its toy and which trick it uses on whom. Pure; the
 * referee (`round.ts`) drives cats through the same events a phone sends.
 */

export type CatLevel = {
  /** Ms a cat thinks before moving each toy: [min, max). */
  think: readonly [number, number];
  /** How often it takes its second-best placement. */
  sloppy: number;
  /** The tricks it uses; the rest it holds. Empty: none. */
  tricks: readonly Trick[];
};

const ALL: readonly Trick[] = ["hairball", "swipe", "catnip", "scoop", "settle", "nap", "swap", "bath"];
export const CAT_LEVELS: Record<"easy" | "quick", CatLevel> = {
  easy: { think: [3000, 4600], sloppy: 0.5, tricks: ["hairball", "swipe", "scoop", "nap"] },
  quick: { think: [800, 1600], sloppy: 0.15, tricks: ALL },
};

const HARMFUL: readonly Trick[] = ["hairball", "swipe", "catnip", "swap"];

export type Placement = { rot: Rot; x: number; y: number };

/** Column heights, holes and bumpiness of a box: what a cat weighs. */
export function shape(box: Box): { heights: number[]; holes: number; bumpiness: number } {
  const heights: number[] = [];
  let holes = 0;
  for (let x = 0; x < W; x++) {
    let h = 0;
    for (let y = TOTAL - 1; y >= 0; y--) {
      if (box.cells[y * W + x] !== 0) {
        if (h === 0) h = y + 1;
      } else if (h > 0) holes++;
    }
    heights.push(h);
  }
  let bumpiness = 0;
  for (let x = 1; x < W; x++) bumpiness += Math.abs((heights[x] as number) - (heights[x - 1] as number));
  return { heights, holes, bumpiness };
}

/** A placement's worth: well-known weights for this kind of game, height, rows cleared, holes, bumps. */
const score = (after: Box, cleared: number): number => {
  const { heights, holes, bumpiness } = shape(after);
  const aggregate = heights.reduce((a, h) => a + h, 0);
  return -0.51 * aggregate + 0.76 * cleared - 0.36 * holes - 0.18 * bumpiness;
};

/** Every resting placement of the toy in hand, best first. */
export function placements(box: Box, roundSeed: Readonly<Seed>): (Placement & { score: number })[] {
  const toy = toyAt(roundSeed, box.next);
  const out: (Placement & { score: number })[] = [];
  for (const rot of [0, 1, 2, 3] as Rot[]) {
    for (let x = -3; x < W; x++) {
      const y = restingY(box, toy, rot, x);
      if (y === null) continue;
      const r = setDown(box, roundSeed, box.next, rot, x, y, []);
      if ("error" in r) continue;
      out.push({ rot, x, y, score: score(r.box, r.cleared) - (r.out ? 1000 : 0) });
    }
  }
  return out.sort((a, b) => b.score - a.score || a.rot - b.rot || a.x - b.x);
}

/** Where the cat sets its toy: the best placement, or the second best `sloppy` of the time. */
export function place(box: Box, roundSeed: Readonly<Seed>, sloppy: number, rng: Readonly<Seed>): [Placement | null, Seed] {
  const all = placements(box, roundSeed);
  const [u, next] = rngNext(rng);
  if (all.length === 0) return [null, next];
  const pick = rngFloat(u) < sloppy && all.length > 1 ? all[1] : all[0];
  const { rot, x, y } = pick as Placement;
  return [{ rot, x, y }, next];
}

export type TableView = { me: number; boxes: readonly Box[]; live: readonly boolean[]; humans: readonly boolean[]; wins: readonly number[] };

/** The box a harmful trick goes to: the live person with the most wins, then the lowest stack; with no person, the lowest other box. */
export function victim(v: TableView): number | null {
  const others = v.boxes.map((_, i) => i).filter((i) => i !== v.me && v.live[i]);
  const people = others.filter((i) => v.humans[i]);
  const pool = people.length > 0 ? people : others;
  if (pool.length === 0) return null;
  return [...pool].sort((a, b) => (v.wins[b] ?? 0) - (v.wins[a] ?? 0) || highest(v.boxes[a] as Box) - highest(v.boxes[b] as Box) || a - b)[0] as number;
}

/** The trick a cat uses now, and on whom, or null to hold on. */
export function chooseTrick(v: TableView, level: CatLevel): { slot: number; seat: number } | null {
  const mine = v.boxes[v.me] as Box;
  const top = highest(mine);
  for (let slot = 0; slot < mine.held.length; slot++) {
    const t = mine.held[slot] as Trick;
    if (!level.tricks.includes(t)) continue;
    if (HARMFUL.includes(t)) {
      const seat = victim(v);
      if (seat === null) continue;
      // Never Swap from a box lower than the target's.
      if (t === "swap" && top <= highest(v.boxes[seat] as Box) + 3) continue;
      return { slot, seat };
    }
    const useful =
      t === "bath" ? top >= 12
      : t === "nap" ? mine.waiting.length > 0 || top >= 10
      : top >= 8;
    if (useful) return { slot, seat: v.me };
  }
  return null;
}
