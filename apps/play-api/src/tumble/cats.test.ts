import { describe, expect, it } from "vitest";

import { highest, newBox, type Box } from "./box";
import { CAT_LEVELS, chooseTrick, place, placements, victim, type TableView } from "./cats";
import { gravityMs } from "./clock";
import { fromText } from "./codec";
import { toyAt } from "./queue";
import { TumbleRound } from "./round";

import type { Seed } from "../rules/rng";

const SEED: Seed = [7, 7, 7, 7];
const nFor = (toy: string): number => {
  for (let n = 0; n < 64; n++) if (toyAt(SEED, n) === toy) return n;
  throw new Error(toy);
};
const at = (rows: string[], toy: string, extra: Partial<Box> = {}): Box => ({ ...newBox([1, 1, 1, 1]), ...fromText(rows), next: nFor(toy), ...extra });

describe("placing a toy", () => {
  it("lies the long stick flat on an empty floor", () => {
    const [p] = place(at([], "i4"), SEED, 0, [1, 2, 3, 4]);
    expect(p?.y).toBe(-2);
    expect(p?.rot === 0 || p?.rot === 2).toBe(true);
  });

  it("takes the 4-row clear when one is offered", () => {
    const [p] = place(at(Array.from({ length: 4 }, () => "#####.######"), "i4"), SEED, 0, [1, 2, 3, 4]);
    expect(p).toMatchObject({ x: 3, y: 0 });
  });

  it("takes the second best when sloppy", () => {
    const box = at([], "t4");
    const all = placements(box, SEED);
    const [p] = place(box, SEED, 1, [1, 2, 3, 4]);
    expect(p).toEqual({ rot: all[1]?.rot, x: all[1]?.x, y: all[1]?.y });
  });
});

describe("tricks", () => {
  const view = (boxes: Box[], wins: number[], humans = boxes.map((_, i) => i !== 0)): TableView => ({ me: 0, boxes, live: boxes.map(() => true), humans, wins });

  it("aims harmful tricks at the person with the most wins, then the lowest stack", () => {
    const low = at([], "i4");
    const high = at(Array.from({ length: 6 }, () => "#..........."), "i4");
    expect(victim(view([low, high, low], [0, 2, 1]))).toBe(1);
    expect(victim(view([low, high, low], [0, 1, 1]))).toBe(2);
  });

  it("never Swaps from a lower box", () => {
    const me = at([], "i4", { held: ["swap"] });
    const them = at(Array.from({ length: 6 }, () => "#..........."), "i4");
    expect(chooseTrick(view([me, them], [0, 0]), CAT_LEVELS.quick)).toBeNull();
    const tall = at(Array.from({ length: 14 }, () => "#..........."), "i4", { held: ["swap"] });
    expect(chooseTrick(view([tall, them], [0, 0]), CAT_LEVELS.quick)).toEqual({ slot: 0, seat: 1 });
  });

  it("an Easy cat never uses Catnip, Settle, Swap or Bath", () => {
    const tall = at(Array.from({ length: 14 }, () => "#..........."), "i4", { held: ["catnip", "settle", "swap", "bath"] });
    expect(chooseTrick(view([tall, at([], "i4")], [0, 0]), CAT_LEVELS.easy)).toBeNull();
    expect(highest(tall)).toBe(13);
  });

  it("keeps helpful tricks until they help", () => {
    const low = at([], "i4", { held: ["scoop"] });
    expect(chooseTrick(view([low, at([], "i4")], [0, 0]), CAT_LEVELS.quick)).toBeNull();
    const high = at(Array.from({ length: 9 }, () => "#..........."), "i4", { held: ["scoop"] });
    expect(chooseTrick(view([high, at([], "i4")], [0, 0]), CAT_LEVELS.quick)).toEqual({ slot: 0, seat: 0 });
  });
});

describe("gravity", () => {
  it("starts at 1000 ms a row, speeds up 15% each 30 s, and the Zoomies from 2:30", () => {
    expect(gravityMs(0)).toBe(1000);
    expect(gravityMs(30_000)).toBeCloseTo(850);
    expect(gravityMs(149_999)).toBeCloseTo(1000 * 0.85 ** 4);
    expect(gravityMs(150_000)).toBeCloseTo(1000 * 0.85 ** 5 * 0.7);
    expect(gravityMs(10 * 60_000)).toBe(50);
    expect(gravityMs(0, true)).toBe(250);
  });
});

describe("House Cats in a round", () => {
  it("play a round against an idle person to the end, through the same checks as a phone", () => {
    const T0 = 1_000_000;
    const r = new TumbleRound({ r: 1, seats: [{ kind: "human" }, { kind: "cat" }, { kind: "cat" }], roundSeed: SEED, trickSeeds: [[1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]], startsAt: T0, rng: [5, 5, 5, 5], cats: "quick" });
    let refusals = 0;
    let t = T0;
    while (!r.result().over && t < T0 + 20 * 60_000) {
      t += 100;
      r.input(0, { t: "tumble", r: 1, ev: [] }, t); // the person is there, but never moves
      for (const o of r.tick(t)) if (o.message.t === "tumbleSync" && typeof o.to === "object" && "seat" in o.to && o.to.seat !== 0) refusals++;
    }
    const res = r.result();
    expect(res.over).toBe(true);
    expect(res.winner).not.toBeNull();
    expect(refusals).toBe(0);
    expect(r.box(1).rows + r.box(2).rows).toBeGreaterThan(0);
  });
});
