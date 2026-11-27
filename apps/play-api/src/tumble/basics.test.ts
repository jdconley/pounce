import { describe, expect, it } from "vitest";

import { createRng, type Seed } from "../rules/rng";

import { toyAt } from "./queue";
import { rngFloat, rngNext, rngShuffle } from "./rng";
import { TOY_IDS, boxSize, spawn, toyCells, type Rot } from "./toys";

describe("rngNext", () => {
  it("matches createRng for the same seed", () => {
    const rng = createRng([1, 2, 3, 4]);
    let s: Seed = [1, 2, 3, 4];
    for (let i = 0; i < 1000; i++) {
      const [u, next] = rngNext(s);
      s = next;
      expect(rngFloat(u)).toBe(rng());
    }
  });

  it("never changes the state it is given", () => {
    const s: Seed = [5, 6, 7, 8];
    rngNext(s);
    expect(s).toEqual([5, 6, 7, 8]);
  });

  it("shuffles as rules/rng does, returning the state after", () => {
    const [out, after] = rngShuffle([1, 2, 3, 4, 5], [9, 9, 9, 9]);
    expect([...out].sort()).toEqual([1, 2, 3, 4, 5]);
    expect(after).not.toEqual([9, 9, 9, 9]);
  });
});

describe("toys", () => {
  it("turns clockwise inside the toy's box", () => {
    expect(toyCells("t4", 0)).toEqual([[0, 1], [1, 1], [2, 1], [1, 2]]);
    expect(toyCells("t4", 1)).toEqual([[1, 2], [1, 1], [1, 0], [2, 1]]);
  });

  it("comes back after four turns, and the square never changes", () => {
    const key = (cells: readonly (readonly number[])[]) => cells.map((c) => c.join(",")).sort().join(" ");
    for (const toy of TOY_IDS) {
      const k = boxSize(toy);
      const fourth = toyCells(toy, 3).map(([x, y]) => [y, k - 1 - x]);
      expect(fourth).toEqual(toyCells(toy, 0).map((c) => [...c]));
      for (const rot of [1, 2, 3] as Rot[]) {
        for (const [x, y] of toyCells(toy, rot)) {
          expect(x >= 0 && x < k && y >= 0 && y < k).toBe(true);
        }
      }
    }
    for (const rot of [1, 2, 3] as Rot[]) expect(key(toyCells("o4", rot))).toBe(key(toyCells("o4", 0)));
  });

  it("has 3, 4 and 5 cell toys in boxes of 2 to 4", () => {
    expect(TOY_IDS.map((t) => toyCells(t, 0).length)).toEqual([3, 3, 4, 4, 4, 4, 4, 5, 5]);
    expect(TOY_IDS.map(boxSize)).toEqual([3, 2, 4, 2, 3, 3, 3, 3, 3]);
  });

  it("appears centred, rounding left, with its lowest cells in row 18", () => {
    expect(spawn("i4")).toEqual({ rot: 0, x: 4, y: 16 });
    expect(spawn("v3")).toEqual({ rot: 0, x: 5, y: 18 });
    expect(spawn("t4")).toEqual({ rot: 0, x: 4, y: 17 });
    expect(spawn("p5")).toEqual({ rot: 0, x: 4, y: 18 });
  });
});

describe("the queue", () => {
  it("deals bags of 8 and 7 in turn: the seven small toys each time, and a paw print or a bowl in every other bag", () => {
    const seed: Seed = [11, 22, 33, 44];
    let n = 0;
    for (let bag = 0; bag < 8; bag++) {
      const size = bag % 2 === 0 ? 8 : 7;
      const toys = Array.from({ length: size }, (_, i) => toyAt(seed, n + i));
      n += size;
      const five = bag % 2 === 1 ? [] : [bag % 4 === 0 ? "p5" : "u5"];
      expect([...toys].sort()).toEqual(["i3", "i4", "j4", "l4", "o4", "t4", "v3", ...five].sort());
    }
  });

  it("is the same for a seed, whatever order it is asked in", () => {
    const seed: Seed = [3, 1, 4, 1];
    const forward = Array.from({ length: 40 }, (_, i) => toyAt(seed, i));
    const backward = Array.from({ length: 40 }, (_, i) => toyAt([3, 1, 4, 1], 39 - i)).reverse();
    expect(backward).toEqual(forward);
  });
});
