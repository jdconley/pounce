import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDays, pairOn, person } from "../../tests/streak-helpers";

import { BACKS, RUGS, TOYS } from "./catalog";
import { newPair, type PairState } from "./pair-core";
import { ownView } from "./personal";
import { trophies, type TrophyInput } from "./trophies";

const own = ownView(null, "America/Los_Angeles", at(D0, "12:00"));

function input(pairs: PairState[], extra: Partial<TrophyInput> = {}): TrophyInput {
  return { me: A, own, pairBest: 0, pairs, connections: [], ...extra };
}

/** A pair of A with someone, at a given streak, owning `owned`. */
function pairWith(partner: string, patch: { count?: number; best?: number; lifetimeKept?: number } = {}, owned: string[] = []): PairState {
  const s = newPair(`pair_${partner}`, [person(A), person(partner)], at(D0, "08:00"), [1, 2, 3, 4]);
  Object.assign(s.streak, { count: 0, best: 0, lifetimeKept: 0, ...patch });
  s.owned = [...owned];
  return s;
}

const item = (t: ReturnType<typeof trophies>, id: string) => t.catalog.find((c) => c.id === id);

describe("the trophy room's records (§3)", () => {
  it("are your own streak's numbers and the longest pair streak, from the pairs or the kept high-water mark", () => {
    const mine = { ...own, count: 4, best: 9, lifetimeKept: 30, perfectWeeks: 2 };
    const t = trophies(input([pairWith(B, { count: 3, best: 12 }), pairWith(C, { count: 5, best: 7 })], { own: mine, pairBest: 10 }));
    expect(t.records).toEqual({ current: 4, best: 9, longestPair: 12, totalDays: 30, perfectWeeks: 2 });
    expect(trophies(input([], { pairBest: 40 })).records.longestPair).toBe(40);
    expect(t.own).toBe(mine);
  });

  it("passes the connections through as they are", () => {
    const connections = [{ pair: "pr_x" }] as unknown as TrophyInput["connections"];
    expect(trophies(input([], { connections })).connections).toBe(connections);
  });
});

describe("what you've earned, merged across your pairs (§3 the shelf)", () => {
  it("unions toys, backs and rugs across pairs, in catalog order, without the defaults", () => {
    const b = pairWith(B, { lifetimeKept: 8 }, ["toy-mouse", "back-crown", "rug-night-sky", "back-violet-paw"]);
    const c = pairWith(C, { lifetimeKept: 31 }, ["toy-yarn-ball", "toy-mouse", "rug-classic", "back-yarn-swirl"]);
    const t = trophies(input([b, c]));
    expect(t.earned).toEqual({
      toys: ["toy-yarn-ball", "toy-mouse"],
      backs: ["back-yarn-swirl", "back-crown"],
      rugs: ["rug-night-sky"],
      condoStage: 5,
    });
  });

  it("leaves out a gift's item until you've opened it, even if your partner has", () => {
    const b = pairWith(B, {}, ["rug-fish-pond", "toy-bell"]);
    b.gifts.push({ id: "g1", milestone: 7, item: "rug-fish-pond", openedBy: [B] });
    b.gifts.push({ id: "g2", milestone: 3, item: "toy-bell", openedBy: [A, B] });
    const t = trophies(input([b]));
    expect(t.earned.rugs).toEqual([]);
    expect(t.earned.toys).toEqual(["toy-bell"]);
    expect(item(t, "rug-fish-pond")?.progress).toBeLessThan(1);
  });

  it("is nothing with no pairs", () => {
    expect(trophies(input([])).earned).toEqual({ toys: [], backs: [], rugs: [], condoStage: 0 });
  });
});

describe("the catalog: still to earn (D4)", () => {
  it("lists every condo stage, back, rug and toy in that order, earned ones at progress 1", () => {
    const t = trophies(input([pairWith(B, { lifetimeKept: 3 }, ["toy-cork", "back-crown", "back-golden-yarn"])]));
    const unlockable = BACKS.length - 1 + RUGS.length - 1;
    expect(t.catalog).toHaveLength(10 + unlockable + TOYS.length);
    expect(t.catalog.slice(0, 10).map((c) => c.id)).toEqual(Array.from({ length: 10 }, (_, i) => `condo-${i + 1}`));
    expect(t.catalog[10]).toMatchObject({ id: "back-yarn-swirl", kind: "back" });
    expect(t.catalog.at(-1)).toMatchObject({ id: "toy-golden-mouse", kind: "toy" });
    expect(t.catalog.map((c) => c.kind)).toEqual([
      ...Array(10).fill("condo"),
      ...Array(BACKS.length - 1).fill("back"),
      ...Array(RUGS.length - 1).fill("rug"),
      ...Array(TOYS.length).fill("toy"),
    ]);
    expect(item(t, "condo-2")).toMatchObject({ at: 3, progress: 1 });
    expect(item(t, "toy-cork")?.progress).toBe(1);
    expect(item(t, "back-crown")?.progress).toBe(1);
    expect(item(t, "back-golden-yarn")).toMatchObject({ at: 24, progress: 1 });
  });

  it("rings a condo stage at its lifetime threshold, against the most days together of any pair", () => {
    const t = trophies(input([pairWith(B, { lifetimeKept: 12 }), pairWith(C, { lifetimeKept: 20 })]));
    expect(item(t, "condo-4")).toMatchObject({ at: 14, progress: 1 });
    expect(item(t, "condo-5")).toMatchObject({ at: 30 });
    expect(item(t, "condo-5")?.progress).toBeCloseTo(20 / 30);
    expect(item(t, "condo-10")).toMatchObject({ at: 365 });
  });

  it("rings a normal back at the next small milestone and a rug or rare back at the next big one", () => {
    const t = trophies(input([pairWith(B, { count: 20 }), pairWith(C, { count: 5 })]));
    expect(item(t, "back-yarn-swirl")).toMatchObject({ at: 50 });
    expect(item(t, "back-yarn-swirl")?.progress).toBeCloseTo(20 / 50);
    expect(item(t, "rug-night-sky")).toMatchObject({ at: 30 });
    expect(item(t, "back-heart-paws")?.progress).toBeCloseTo(20 / 30);
    // Past the last listed small milestone, only a fresh start's 3 can bring one.
    expect(item(trophies(input([pairWith(B, { count: 320 })])), "back-moonlit-fish")).toMatchObject({ at: 3, progress: 0 });
    expect(item(trophies(input([pairWith(B, { count: 370 })])), "rug-candy-stripe")).toMatchObject({ at: 400 });
  });

  it("rings the golden yarn back at a full set of toys, against the most toys one pair has", () => {
    const toys = TOYS.slice(0, 12).map((x) => x.id);
    const t = trophies(input([pairWith(B, {}, toys), pairWith(C, {}, toys.slice(0, 3))]));
    expect(item(t, "back-golden-yarn")).toMatchObject({ at: 24, progress: 0.5 });
  });

  it("rings a toy at its rarity's guarantee, against the pair closest to it", () => {
    const b = pairWith(B);
    b.pity = { shiny: 3, golden: 12 };
    const c = pairWith(C);
    c.pity = { shiny: 5, golden: 2 };
    const t = trophies(input([b, c]));
    expect(item(t, "toy-mouse")).toMatchObject({ at: 1, progress: 0 });
    expect(item(t, "toy-disco-ball")).toMatchObject({ at: 7 });
    expect(item(t, "toy-disco-ball")?.progress).toBeCloseTo(5 / 7);
    expect(item(t, "toy-golden-fish")).toMatchObject({ at: 30, progress: 12 / 30 });
  });

  it("starts every ring at the tier's first numeral with no pairs", () => {
    const t = trophies(input([]));
    expect(item(t, "condo-1")).toMatchObject({ at: 1, progress: 0 });
    expect(item(t, "back-cucumber-chaos")).toMatchObject({ at: 3, progress: 0 });
    expect(item(t, "rug-royal-violet")).toMatchObject({ at: 7, progress: 0 });
    expect(t.catalog.every((c) => c.progress === 0)).toBe(true);
  });

  it("measures real pairs after kept days", () => {
    const s = pairOn();
    keepDays(s, D0, 4);
    const t = trophies(input([s]));
    expect(t.earned.condoStage).toBe(2);
    // The day-3 milestone's gift is still wrapped for A.
    const wrapped = s.gifts.map((g) => g.item);
    expect(wrapped).toHaveLength(1);
    expect(t.earned.toys).toHaveLength(s.owned.filter((id) => id.startsWith("toy-") && !wrapped.includes(id)).length);
    expect(item(t, "condo-3")?.progress).toBeCloseTo(4 / 7);
  });
});
