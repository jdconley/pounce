/**
 * The Toy Tumble screen fits every screen AGENTS.md lists, at 2 and 6 players (spec §5.2): cells
 * of 20 px or more on a phone, nothing overlapping, everything inside the safe area, and chips
 * instead of minis at a TV table. Watching and the TV's row fit too.
 */
import { describe, expect, test } from "vitest";

import { overlaps, playLayout, tvLayout, watchLayout, type Rect } from "../src/tumble/layout";

const SIZES = [
  { name: "iPhone SE", width: 375, height: 667, phone: true, insets: { top: 20, right: 0, bottom: 0, left: 0 } },
  { name: "large iPhone", width: 390, height: 844, phone: true, insets: { top: 47, right: 0, bottom: 34, left: 0 } },
  { name: "iPad portrait", width: 768, height: 1024, phone: false, insets: { top: 24, right: 0, bottom: 20, left: 0 } },
  { name: "iPad landscape", width: 1024, height: 768, phone: false, insets: { top: 24, right: 0, bottom: 20, left: 0 } },
  { name: "laptop", width: 1440, height: 900, phone: false, insets: { top: 0, right: 0, bottom: 0, left: 0 } },
];

const inside = (r: Rect, s: (typeof SIZES)[number]) =>
  r.x >= s.insets.left && r.y >= s.insets.top && r.x + r.w <= s.width - s.insets.right + 0.01 && r.y + r.h <= s.height - s.insets.bottom + 0.01;

describe("the player screen", () => {
  for (const s of SIZES) {
    for (const players of [2, 6]) {
      for (const chips of [false, true]) {
        test(`${s.name}, ${players} players${chips ? ", at a TV table" : ""}`, () => {
          const L = playLayout({ width: s.width, height: s.height, insets: s.insets, others: players - 1, chips });
          if (s.phone) expect(L.box.cell).toBeGreaterThanOrEqual(20);
          expect(L.box.cell).toBeGreaterThanOrEqual(20);
          const others = chips ? L.chips : L.minis;
          expect(others.length).toBe(players - 1);
          if (chips) expect(L.minis).toEqual([]);
          else for (const m of L.minis) expect(m.cell, "a mini is still a box").toBeGreaterThanOrEqual(2.5);
          const rects: [string, Rect][] = [
            ["box", L.box],
            ["rim", L.rim],
            ["meter", L.meter],
            ["menu", L.menu],
            ...L.slots.map((r, i): [string, Rect] => [`slot ${i}`, r]),
            ...others.map((r, i): [string, Rect] => [`other ${i}`, r]),
          ];
          for (const [name, r] of rects) {
            expect(r.w, name).toBeGreaterThan(0);
            expect(inside(r, s), `${name} inside ${JSON.stringify(r)}`).toBe(true);
          }
          for (let i = 0; i < rects.length; i++)
            for (let j = i + 1; j < rects.length; j++) expect(overlaps(rects[i]![1], rects[j]![1]), `${rects[i]![0]} and ${rects[j]![0]}`).toBe(false);
        });
      }
    }
  }

  test("an iPad in landscape splits the minis to both sides of the box", () => {
    const L = playLayout({ width: 1024, height: 768, insets: { top: 0, right: 0, bottom: 0, left: 0 }, others: 5, chips: false });
    expect(L.landscape).toBe(true);
    expect(L.minis.filter((m) => m.x < L.box.x).length).toBe(3);
    expect(L.minis.filter((m) => m.x > L.box.x + L.box.w).length).toBe(2);
  });
});

describe("watching and the TV", () => {
  test("watching shows every box, in the grid with the biggest cells", () => {
    for (const s of SIZES) {
      const boxes = watchLayout({ width: s.width, height: s.height, insets: s.insets, n: 6 });
      expect(boxes.length).toBe(6);
      for (const b of boxes) expect(inside(b, s)).toBe(true);
      for (let i = 0; i < 6; i++) for (let j = i + 1; j < 6; j++) expect(overlaps(boxes[i]!, boxes[j]!)).toBe(false);
      expect(boxes[0]!.cell).toBeGreaterThanOrEqual(5);
    }
  });

  test("the TV puts up to 6 boxes in one row, bigger with fewer players", () => {
    const six = tvLayout({ width: 1920, height: 1080, n: 6, header: 120, label: 150 });
    expect(new Set(six.map((b) => b.y)).size).toBe(1);
    expect(six.at(-1)!.x + six.at(-1)!.w + six.at(-1)!.cell).toBeLessThanOrEqual(1920);
    expect(six[0]!.x).toBeGreaterThanOrEqual(0);
    for (let i = 1; i < 6; i++) expect(six[i]!.x).toBeGreaterThan(six[i - 1]!.x + six[i - 1]!.w);
    const three = tvLayout({ width: 1920, height: 1080, n: 3, header: 120, label: 150 });
    expect(three[0]!.cell).toBeGreaterThan(six[0]!.cell);
    expect(three[0]!.y + three[0]!.h + 150).toBeLessThanOrEqual(1080);
  });
});
