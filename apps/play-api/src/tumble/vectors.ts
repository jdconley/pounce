import { formatVector } from "../daily/box-fort/vectors";

import { applyHit, fits, newBox, receiveJunk, setDown, turn, useTrick, TOTAL, type Box, type Hit, type Waiting } from "./box";
import { fromText, toText, type BoxText } from "./codec";
import { toyAt } from "./queue";
import { rngFloat, rngNext } from "./rng";
import { spawn, type Rot, type ToyId } from "./toys";

import type { Seed } from "../rules/rng";

/**
 * Toy Tumble's golden vectors (spec §9.1): event streams and the exact box after each step,
 * written to `fixtures/tumble/` by `pnpm --filter @pounce/play-api vectors:tumble`. The app's
 * Swift engine replays every file and must match cell for cell; `vectors.test.ts` fails while
 * the files and these rules disagree.
 *
 * A Swap's payload is written as text rows (`cells`, `tricks`, as `codec.ts` has them), not as
 * the 264-number arrays the wire carries.
 */

export type BoxExpect = BoxText & Omit<Box, "cells" | "tricks">;
export type HitText = Exclude<Hit, { k: "swap" }> | ({ k: "swap" } & BoxText);
export type VectorOp =
  | ["setDown", number, Rot, number, number, number[]]
  | ["junk", Waiting]
  | ["hit", HitText]
  | ["use", number]
  | ["turn", ToyId, Rot, number, number, 1 | -1];
export type VectorExpect =
  | { error: string }
  | { cleared: number; sent: number; blocked: { id: number; rows: number }[]; pocketed: string[]; out: boolean; box: BoxExpect }
  | { pocketed: string[]; box: BoxExpect }
  | { trick: string; box: BoxExpect }
  | { box: BoxExpect }
  | { to: [Rot, number, number] | null };
export type VectorStep = { do: VectorOp; expect: VectorExpect };
/** `start`, when present, is the box before the first step; otherwise it is `newBox(trickSeed)`. */
export type VectorFile = { name: string; roundSeed: Seed; trickSeed: Seed; queue: ToyId[]; start?: BoxExpect; steps: VectorStep[] };

export const boxFromExpect = (e: BoxExpect): Box => {
  const { cells, tricks, ...rest } = e;
  return { ...rest, ...fromText(cells, tricks), held: [...rest.held], waiting: rest.waiting.map((w) => ({ ...w })), rng: [...rest.rng] as Seed };
};

export const QUEUE_LENGTH = 32;

export const expectBox = (b: Box): BoxExpect => {
  return { ...toText(b), held: [...b.held], next: b.next, waiting: b.waiting.map((w) => ({ ...w })), rng: [...b.rng] as Seed, out: b.out, rows: b.rows };
};

export const hitFromText = (h: HitText): Hit => (h.k === "swap" ? { k: "swap", ...fromText(h.cells, h.tricks) } : h);

/** Runs one step. The box after it, and what the step's `expect` should say. */
export function runStep(box: Box, roundSeed: Seed, op: VectorOp): { box: Box; expect: VectorExpect } {
  switch (op[0]) {
    case "setDown": {
      const r = setDown(box, roundSeed, op[1], op[2], op[3], op[4], op[5]);
      if ("error" in r) return { box, expect: { error: r.error } };
      return { box: r.box, expect: { cleared: r.cleared, sent: r.sent, blocked: r.blocked, pocketed: r.pocketed, out: r.out, box: expectBox(r.box) } };
    }
    case "junk": {
      const b = receiveJunk(box, op[1]);
      return { box: b, expect: { box: expectBox(b) } };
    }
    case "hit": {
      const r = applyHit(box, hitFromText(op[1]));
      return { box: r.box, expect: { pocketed: r.pocketed, box: expectBox(r.box) } };
    }
    case "use": {
      const r = useTrick(box, op[1]);
      if (!r) return { box, expect: { error: "no_trick" } };
      return { box: r.box, expect: { trick: r.trick, box: expectBox(r.box) } };
    }
    case "turn": {
      const t = turn(box, op[1], op[2], op[3], op[4], op[5]);
      return { box, expect: { to: t ? [t.rot, t.x, t.y] : null } };
    }
  }
}

/** A small seeded random source for building the random games (not part of the rules). */
class Dice {
  constructor(private s: Seed) {}
  float(): number {
    const [u, next] = rngNext(this.s);
    this.s = next;
    return rngFloat(u);
  }
  int(n: number): number {
    return Math.floor(this.float() * n);
  }
}

/** Where a toy rests if dropped straight down from row 18 at this rotation and column, or null. */
export function restingY(box: Box, toy: ToyId, rot: Rot, x: number): number | null {
  let y = spawn(toy).y;
  if (!fits(box, toy, rot, x, y)) return null;
  while (fits(box, toy, rot, x, y - 1)) y--;
  return y;
}

const holesAndHeight = (b: Box): number => {
  let holes = 0;
  let height = 0;
  for (let x = 0; x < 12; x++) {
    let seen = false;
    for (let y = TOTAL - 1; y >= 0; y--) {
      const filled = b.cells[y * 12 + x] !== 0;
      if (filled && !seen) {
        seen = true;
        height = Math.max(height, y + 1);
      } else if (!filled && seen) holes++;
    }
  }
  return holes * 4 + height;
};

/** A seeded random game: greedy-ish set-downs, with junk, hits, tricks used, turns and refusals mixed in. */
function randomGame(i: number): VectorFile {
  const dice = new Dice([1000 + i, 2000 + i * 7, 3000 + i * 13, 4000 + i * 17]);
  const roundSeed: Seed = [101 + i, 202 + i, 303 + i, 404 + i];
  const trickSeed: Seed = [505 + i, 606 + i, 707 + i, 808 + i];
  let box = newBox(trickSeed);
  const steps: VectorStep[] = [];
  const earlier: Box[] = [];
  let junkId = 1;
  const push = (op: VectorOp) => {
    const r = runStep(box, roundSeed, op);
    steps.push({ do: op, expect: r.expect });
    box = r.box;
  };
  const target = 150 + dice.int(151);
  while (steps.length < target && !box.out) {
    const roll = dice.float();
    if (roll < 0.06) {
      push(["junk", { id: junkId++, rows: 1 + dice.int(dice.float() < 0.8 ? 2 : 4), gap: dice.int(12) }]);
      continue;
    }
    if (roll < 0.17) {
      const kinds = ["hairball", "swipe", "catnip", "scoop", "settle", "nap", "swap", "bath"] as const;
      const k = kinds[dice.int(kinds.length)] as (typeof kinds)[number];
      const from = earlier[dice.int(Math.max(1, earlier.length))] ?? newBox(trickSeed);
      const hit: HitText =
        k === "hairball" ? { k, gap: dice.int(12) }
        : k === "swipe" ? { k, shifts: Array.from({ length: TOTAL }, () => dice.int(5) - 2) }
        : k === "swap" ? { k, ...toText(from) }
        : { k };
      push(["hit", hit]);
      continue;
    }
    if (roll < 0.25 && box.held.length > 0) {
      push(["use", dice.int(box.held.length + 1)]);
      continue;
    }
    const toy = toyAt(roundSeed, box.next);
    if (roll < 0.32) {
      const at = spawn(toy);
      push(["turn", toy, dice.int(4) as Rot, at.x - 2 + dice.int(5), at.y - dice.int(10), dice.float() < 0.5 ? 1 : -1]);
      continue;
    }
    if (roll < 0.35) {
      // A refusal: the wrong toy, or one left hanging in the air.
      push(dice.float() < 0.5 ? ["setDown", box.next + 1, 0, 4, 0, []] : ["setDown", box.next, 0, spawn(toy).x, spawn(toy).y, []]);
      continue;
    }
    const options: { rot: Rot; x: number; y: number; score: number }[] = [];
    for (const rot of [0, 1, 2, 3] as Rot[]) {
      for (let x = -3; x < 12; x++) {
        const y = restingY(box, toy, rot, x);
        if (y === null) continue;
        const r = setDown(box, roundSeed, box.next, rot, x, y, []);
        if ("error" in r) continue;
        options.push({ rot, x, y, score: holesAndHeight(r.box) - r.cleared * 6 });
      }
    }
    if (options.length === 0) break;
    options.sort((a, b) => a.score - b.score);
    const pick = options[dice.float() < 0.7 ? 0 : Math.min(options.length - 1, 1 + dice.int(2))] as (typeof options)[number];
    const trial = setDown(box, roundSeed, box.next, pick.rot, pick.x, pick.y, []);
    const clears = !("error" in trial) && trial.cleared > 0;
    const landed = !clears && box.waiting.length > 0 && dice.float() < 0.6 ? box.waiting.slice(0, 1 + dice.int(box.waiting.length)).map((w) => w.id) : [];
    earlier.push(box);
    push(["setDown", box.next, pick.rot, pick.x, pick.y, landed]);
  }
  return { name: `random-${String(i).padStart(2, "0")}`, roundSeed, trickSeed, queue: Array.from({ length: QUEUE_LENGTH }, (_, n) => toyAt(roundSeed, n)), steps };
}

/** Hand-made boxes for the rules a random game rarely reaches. */
function handMade(): VectorFile[] {
  const roundSeed: Seed = [7, 7, 7, 7];
  const trickSeed: Seed = [1, 2, 3, 4];
  const nFor = (toy: ToyId) => Array.from({ length: 64 }, (_, n) => n).find((n) => toyAt(roundSeed, n) === toy) as number;
  const file = (name: string, start: Box, ops: VectorOp[]): VectorFile => {
    let box = start;
    const steps = ops.map((op) => {
      const r = runStep(box, roundSeed, op);
      box = r.box;
      return { do: op, expect: r.expect };
    });
    return { name, roundSeed, trickSeed, queue: Array.from({ length: QUEUE_LENGTH }, (_, n) => toyAt(roundSeed, n)), start: expectBox(start), steps };
  };
  const at = (rows: string[], toy: ToyId, extra: Partial<Box> = {}, tricks: string[] = []): Box => ({ ...newBox(trickSeed), ...fromText(rows, tricks), next: nFor(toy), ...extra });
  const n = nFor("i4");
  const notch = (k: number) => Array.from({ length: k }, () => ".###########");
  return [
    file("clears-and-blocking", at(notch(4), "i4", { waiting: [{ id: 1, rows: 2, gap: 0 }, { id: 2, rows: 3, gap: 5 }] }), [
      ["setDown", n + 1, 1, -2, 0, []],
      ["setDown", n, 1, -2, 3, []],
      ["setDown", n, 1, -2, 0, [1]],
      ["setDown", n, 1, -2, 0, []],
    ]),
    file("landing-and-pocketing", at(["......#....."], "i4", { waiting: [{ id: 1, rows: 2, gap: 7 }, { id: 2, rows: 1, gap: 2 }], held: ["nap", "bath", "swap", "scoop", "settle"] }, ["......c....."]), [
      ["setDown", n, 0, 0, -2, [1, 2]],
      ["hit", { k: "scoop" }],
      ["use", 4],
      ["use", 9],
    ]),
    file("every-hit", at(["5...5.......", "1#..........", "#.##########", "############"], "i4", { waiting: [{ id: 4, rows: 2, gap: 1 }] }, ["a...b.......", "", "..c.........", ".d.........."]), [
      ["hit", { k: "swipe", shifts: [2, -1, 0, 1, ...new Array<number>(TOTAL - 4).fill(0)] }],
      ["hit", { k: "hairball", gap: 4 }],
      ["hit", { k: "catnip" }],
      ["hit", { k: "nap" }],
      ["hit", { k: "settle" }],
      ["hit", { k: "swap", ...toText(fromText(["1..........."], ["a..........."])) }],
      ["hit", { k: "bath" }],
    ]),
    file("turns-and-nudges", at(Array.from({ length: 8 }, () => "###.########"), "i4"), [
      ["turn", "i4", 0, 0, 5, 1],
      ["turn", "i4", 1, -2, 10, 1],
      ["turn", "i4", 1, 1, 0, 1],
      ["turn", "i4", 0, 8, 10, -1],
      ["turn", "l4", 3, -1, 10, 1],
      ["turn", "p5", 0, 9, 10, 1],
      ["turn", "u5", 2, 0, 9, -1],
    ]),
    file("going-out", at(Array.from({ length: 15 }, () => "#..........."), "i4"), [
      ["setDown", n, 1, -2, 15, []],
      ["setDown", n + 1, 0, 4, 0, []],
    ]),
  ];
}

export function buildVectors(): VectorFile[] {
  return [...handMade(), ...Array.from({ length: 12 }, (_, i) => randomGame(i))];
}

export { formatVector };
