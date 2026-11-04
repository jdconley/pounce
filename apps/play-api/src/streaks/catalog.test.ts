import { describe, expect, it } from "vitest";

import {
  BACKS,
  condoStage,
  DEFAULT_BACK,
  DEFAULT_RUG,
  FULL_SET_BACK,
  isBack,
  isBigMilestone,
  isMilestone,
  isRug,
  nextMilestone,
  NORMAL_BACKS,
  RARE_BACKS,
  RUGS,
  TOYS,
} from "./catalog";

describe("milestones", () => {
  it("are quick early and widen later, then every hundred", () => {
    for (const n of [3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365, 400, 500, 900]) expect(isMilestone(n)).toBe(true);
    for (const n of [0, 1, 2, 8, 360, 366, 450, 365 + 100]) expect(isMilestone(n)).toBe(false);
  });

  it("names the next one above a count", () => {
    expect(nextMilestone(0)).toBe(3);
    expect(nextMilestone(3)).toBe(7);
    expect(nextMilestone(364)).toBe(365);
    expect(nextMilestone(365)).toBe(400);
    expect(nextMilestone(401)).toBe(500);
  });

  it("gives big gifts at 7, 30, 100, 365 and beyond", () => {
    for (const n of [7, 30, 100, 365, 400]) expect(isBigMilestone(n)).toBe(true);
    for (const n of [3, 14, 50, 75, 300]) expect(isBigMilestone(n)).toBe(false);
  });
});

describe("condo stages", () => {
  it("grow with lifetime days together", () => {
    expect(condoStage(0)).toBe(0);
    expect(condoStage(1)).toBe(1);
    expect(condoStage(2)).toBe(1);
    expect(condoStage(3)).toBe(2);
    expect(condoStage(29)).toBe(4);
    expect(condoStage(30)).toBe(5);
    expect(condoStage(364)).toBe(9);
    expect(condoStage(365)).toBe(10);
    expect(condoStage(5000)).toBe(10);
  });
});

describe("catalog", () => {
  it("has 24 toys: 16 common, 6 shiny, 2 golden", () => {
    expect(new Set(TOYS.map((t) => t.id)).size).toBe(24);
    const count = (r: string) => TOYS.filter((t) => t.rarity === r).length;
    expect([count("common"), count("shiny"), count("golden")]).toEqual([16, 6, 2]);
    expect(TOYS.every((t) => t.id.startsWith("toy-"))).toBe(true);
  });

  it("has a default and six card backs, a default and four rugs", () => {
    expect(BACKS).toHaveLength(7);
    expect(RUGS).toHaveLength(5);
    expect(BACKS).toContain(DEFAULT_BACK);
    expect(RUGS).toContain(DEFAULT_RUG);
    expect([...NORMAL_BACKS, ...RARE_BACKS, FULL_SET_BACK, DEFAULT_BACK].sort()).toEqual([...BACKS].sort());
  });

  it("tells backs from rugs", () => {
    expect(isBack("back-crown")).toBe(true);
    expect(isBack("rug-night-sky")).toBe(false);
    expect(isRug("rug-night-sky")).toBe(true);
    expect(isRug("toy-mouse")).toBe(false);
  });
});
