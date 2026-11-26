import { describe, expect, test } from "vitest";

import { drawLayout, GUTTER } from "../src/table/purr-layout";

/** Everything stacked on a portrait phone: the bar, the easel, the palette, the tools and the actions. */
const stacked = (L: ReturnType<typeof drawLayout>) => L.bar + L.easel.height + L.palette + L.tools + L.actions + GUTTER * 5;

describe("the drawer's screen fits", () => {
  const phones: [string, number, number, number, number][] = [
    ["iPhone SE (1st)", 320, 568, 20, 0],
    ["iPhone SE", 375, 667, 20, 0],
    ["iPhone 15", 393, 852, 59, 34],
    ["iPhone 15 Pro Max", 430, 932, 59, 34],
    ["Pixel 7", 412, 915, 24, 0],
  ];
  for (const [name, w, h, top, bottom] of phones) {
    for (const text of [1, 1.5, 2]) {
      test(`${name} at ${text * 100}% text: no scrolling, an easel worth drawing on`, () => {
        const L = drawLayout(w, h, text, top, bottom);
        expect(L.side).toBe(false);
        expect(stacked(L) + top + bottom).toBeLessThanOrEqual(h);
        expect(L.easel.width).toBeLessThanOrEqual(w - GUTTER * 2);
        expect(L.easel.height / L.easel.width).toBeCloseTo(4 / 3, 1);
        // Half the screen's width at the very least, even at the largest text.
        expect(L.easel.width).toBeGreaterThanOrEqual(text > 1.5 ? w * 0.45 : w * 0.6);
        // Nine swatches across, each a finger's width.
        expect(L.swatch * 9 + 8 * 4).toBeLessThanOrEqual(w - GUTTER * 2);
        expect(L.swatch).toBeGreaterThanOrEqual(28);
      });
    }
  }

  test("a tablet on its side puts the tools beside an easel the height of the screen", () => {
    const L = drawLayout(1180, 820, 1);
    expect(L.side).toBe(true);
    expect(L.easel.height).toBeGreaterThan(820 * 0.8);
    const portrait = drawLayout(820, 1180, 1);
    expect(portrait.side).toBe(false);
    expect(portrait.easel.width).toBeGreaterThan(600);
  });
});
