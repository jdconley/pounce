import { describe, expect, test } from "vitest";

import { ctLayout, fan } from "../src/table/ct-layout";
import { tilesLayout } from "../src/table/tiles-layout";

const portrait = { top: 47, right: 0, bottom: 34, left: 0 };
const sideways = { top: 0, right: 47, bottom: 21, left: 47 };
/** A phone held sideways has its notch and home bar at the sides and bottom. */
const insetsFor = (width: number, height: number) => (width > height && height < 500 ? sideways : width < 500 ? portrait : { top: 0, right: 0, bottom: 0, left: 0 });
const SIZES = [
  [320, 568],
  [390, 844],
  [430, 932],
  [844, 390],
  [768, 1024],
  [1024, 768],
  [1440, 900],
  [2560, 1440],
] as const;

describe("table layouts fit every screen", () => {
  test.each(SIZES)("Cat Tower at %i x %i: the hand stays on screen, the piles clear the hand", (width, height) => {
    const insets = insetsFor(width, height);
    const L = ctLayout({ width, height, insets, opponents: [1, 2, 3, 4, 5], handCount: 11, trays: 2, laid: [{ seat: 1, groups: [3, 4] }, { seat: 2, groups: [7] }] });
    for (const p of L.hand) {
      expect(p.x).toBeGreaterThanOrEqual(0);
      expect(p.x + L.cw).toBeLessThanOrEqual(width);
      expect(p.y + L.ch).toBeLessThanOrEqual(height - insets.bottom + 1);
    }
    expect(L.deck.y + L.ch).toBeLessThanOrEqual(L.trays[0]!.y + 1);
    for (const t of L.trays) expect(t.x + t.w).toBeLessThanOrEqual(width);
  });

  test.each(SIZES)("Tuna Tiles at %i x %i: the rack and every set fit", (width, height) => {
    const insets = insetsFor(width, height);
    const L = tilesLayout({ width, height, insets, opponents: [1, 2, 3], sets: [3, 4, 5, 3, 3, 4, 13, 3], rack: 20 });
    for (const p of L.rack) {
      const visual = L.pw * (p.s ?? 1);
      expect(p.x + (L.pw - visual) / 2).toBeGreaterThanOrEqual(0);
      expect(p.x + (L.pw + visual) / 2).toBeLessThanOrEqual(width + 0.5);
    }
    for (const set of L.sets) expect(set.rect.y + set.rect.h).toBeLessThanOrEqual(L.board.y + L.board.h);
  });

  test("a fan keeps every card's index in view", () => {
    const poses = fan(12, 200, 600, 60, 84, 380);
    for (let i = 1; i < poses.length; i++) expect(poses[i]!.x - poses[i - 1]!.x).toBeGreaterThan(20);
  });
});
