import { describe, expect, it } from "vitest";

import { createRng } from "../rules/rng";

import { NORMAL_BACKS, RARE_BACKS, RUGS, TOYS, DEFAULT_RUG, BACKS, DEFAULT_BACK } from "./catalog";
import { drawToy, giftItem, type Pity } from "./rewards";

const rarity = (id: string) => TOYS.find((t) => t.id === id)?.rarity;
const toyIds = TOYS.map((t) => t.id);

describe("drawToy", () => {
  it("never repeats until the set is complete", () => {
    const rng = createRng([1, 2, 3, 4]);
    let pity: Pity = { shiny: 0, golden: 0 };
    const owned: string[] = [];
    for (let i = 0; i < 24; i++) {
      const drawn = drawToy(owned, pity, rng);
      expect(owned).not.toContain(drawn.toy);
      owned.push(drawn.toy);
      pity = drawn.pity;
    }
    expect(new Set(owned).size).toBe(24);
    // A full set may repeat.
    expect(toyIds).toContain(drawToy(owned, pity, rng).toy);
  });

  it("gives a shiny at least every 7 kept days and a golden at least every 30", () => {
    for (const seed of [1, 7, 42, 99, 1234]) {
      const rng = createRng([seed, 5, 6, 7]);
      let pity: Pity = { shiny: 0, golden: 0 };
      const owned: string[] = [];
      let sinceShiny = 0;
      let sinceGolden = 0;
      for (let day = 0; day < 200; day++) {
        const drawn = drawToy(owned, pity, rng);
        pity = drawn.pity;
        if (!owned.includes(drawn.toy)) owned.push(drawn.toy);
        const r = rarity(drawn.toy);
        sinceShiny = r === "common" ? sinceShiny + 1 : 0;
        sinceGolden = r === "golden" ? 0 : sinceGolden + 1;
        expect(sinceShiny).toBeLessThan(7);
        expect(sinceGolden).toBeLessThan(30);
      }
    }
  });

  it("forces the pity rarity", () => {
    const rng = () => 0.99;
    expect(rarity(drawToy([], { shiny: 6, golden: 0 }, rng).toy)).toBe("shiny");
    expect(rarity(drawToy([], { shiny: 0, golden: 29 }, rng).toy)).toBe("golden");
    expect(drawToy([], { shiny: 6, golden: 0 }, rng).pity).toEqual({ shiny: 0, golden: 1 });
    expect(drawToy([], { shiny: 6, golden: 29 }, rng).pity).toEqual({ shiny: 0, golden: 0 });
    expect(drawToy([], { shiny: 2, golden: 3 }, rng).pity).toEqual({ shiny: 3, golden: 4 });
  });

  it("falls back to what's left when a rarity is used up", () => {
    const allButOne = toyIds.filter((id) => id !== "toy-mouse");
    expect(drawToy(allButOne, { shiny: 6, golden: 29 }, () => 0).toy).toBe("toy-mouse");
    const noGolden = toyIds.filter((id) => rarity(id) !== "golden");
    const drawn = drawToy(noGolden, { shiny: 0, golden: 0 }, () => 0.5);
    expect(rarity(drawn.toy)).toBe("golden");
    expect(drawn.pity).toEqual({ shiny: 0, golden: 0 });
  });
});

describe("giftItem", () => {
  it("gives a toy or a card back at a small milestone", () => {
    for (let s = 1; s < 20; s++) {
      const item = giftItem(3, [], createRng([s, 1, 1, 1]));
      expect([...toyIds, ...NORMAL_BACKS]).toContain(item);
    }
  });

  it("gives a rug or a rare card back at a big one", () => {
    for (let s = 1; s < 20; s++) {
      const item = giftItem(7, [], createRng([s, 1, 1, 1]));
      expect([...RUGS.filter((r) => r !== DEFAULT_RUG), ...RARE_BACKS]).toContain(item);
    }
  });

  it("skips what the pair owns, then gives toys, then confetti", () => {
    const bigOwned = [...RUGS, ...RARE_BACKS];
    expect(toyIds).toContain(giftItem(30, bigOwned, createRng([1, 2, 3, 4])));
    const smallOwned = [...toyIds, ...NORMAL_BACKS];
    expect(giftItem(14, smallOwned, createRng([1, 2, 3, 4]))).toBe("confetti");
    expect(giftItem(100, [...toyIds, ...BACKS, ...RUGS], createRng([1, 2, 3, 4]))).toBe("confetti");
    expect(giftItem(3, [DEFAULT_BACK], createRng([1, 2, 3, 4]))).not.toBe(DEFAULT_BACK);
  });

  it("is the same for the same seed", () => {
    expect(giftItem(7, [], createRng([9, 9, 9, 9]))).toBe(giftItem(7, [], createRng([9, 9, 9, 9])));
  });
});
