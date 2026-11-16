import { describe, expect, test } from "vitest";

import { tilesControllerLayout } from "../src/table/tiles-controller-layout";
import { AIM_MAX_SET, AIM_MAX_SETS, tilesAimOf } from "../src/table/tiles-draft";

// Fish 1-13 are ids 0-12; mouse 1-13 are 26-38; Yarn is 104.
describe("the aim a Tuna Tiles draft sends", () => {
  const server = [
    [0, 1, 2],
    [26, 27, 28],
  ];

  test("nothing while the draft is the table as played", () => {
    expect(tilesAimOf(server.map((s) => [...s]), server)).toBeNull();
    // An empty set left behind is not a change.
    expect(tilesAimOf([[0, 1, 2], [], [26, 27, 28]], server)).toBeNull();
  });

  test("the whole draft, without empty sets", () => {
    expect(tilesAimOf([[0, 1, 2, 3], [26, 27, 28]], server)).toEqual({ table: [[0, 1, 2, 3], [26, 27, 28]] });
    expect(tilesAimOf([[0, 1, 2], [], [26, 27, 28], [104]], server)).toEqual({ table: [[0, 1, 2], [26, 27, 28], [104]] });
    // Everything taken back to make a new arrangement: the empty table is a draft too.
    expect(tilesAimOf([], server)).toEqual({ table: [] });
  });

  test("nothing over the limits the wire allows", () => {
    // A set of 14.
    const long = Array.from({ length: AIM_MAX_SET + 1 }, (_, i) => i);
    expect(tilesAimOf([long], [])).toBeNull();
    expect(tilesAimOf([long.slice(0, AIM_MAX_SET)], [])).toEqual({ table: [long.slice(0, AIM_MAX_SET)] });
    // 61 sets.
    const many = Array.from({ length: AIM_MAX_SETS + 1 }, (_, i) => [i]);
    expect(tilesAimOf(many, [])).toBeNull();
    expect(tilesAimOf(many.slice(0, AIM_MAX_SETS), [])).toEqual({ table: many.slice(0, AIM_MAX_SETS) });
    // An id twice, or not a piece.
    expect(tilesAimOf([[0, 1, 2], [2, 3]], server)).toBeNull();
    expect(tilesAimOf([[0, 1, 106]], server)).toBeNull();
    expect(tilesAimOf([[0, 1, -1]], server)).toBeNull();
    expect(tilesAimOf([[0, 1, 1.5]], server)).toBeNull();
  });
});

type Box = { x: number; y: number; w: number; h: number };
const overlaps = (a: Box, b: Box) => Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 0.5 && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 0.5;
const inside = (r: Box, f: Box) => r.x >= f.x - 0.5 && r.y >= f.y - 0.5 && r.x + r.w <= f.x + f.w + 0.5 && r.y + r.h <= f.y + f.h + 0.5;

describe("Tuna Tiles on a phone controller", () => {
  const portrait = { top: 47, right: 0, bottom: 34, left: 0 };
  const se = { top: 20, right: 0, bottom: 0, left: 0 };
  const ipad = { top: 24, right: 0, bottom: 20, left: 0 };
  const SIZES = [
    [320, 568, se],
    [390, 844, portrait],
    [430, 932, portrait],
    [820, 1180, ipad],
    [1180, 820, ipad],
  ] as const;
  const CASES = SIZES.flatMap(([w, h, insets]) => [14, 24].map((n) => [w, h, n, insets] as const));
  const layout = (width: number, height: number, rack: number, insets: typeof portrait) => tilesControllerLayout({ width, height, insets, rack });
  const parts = (L: ReturnType<typeof tilesControllerLayout>): [string, Box][] => [
    ["switch", L.switch],
    ["menu", L.menu],
    ["status", L.status],
    ["pool", L.poolRect],
    ["sort", L.sort],
    ...L.rack.map((p, i): [string, Box] => [`piece ${i}`, { x: p.x, y: p.y, w: L.pw, h: L.ph }]),
  ];

  test.each(CASES)("at %i x %i with %i pieces: everything is inside the safe frame", (width, height, n, insets) => {
    const L = layout(width, height, n, insets);
    const frame = { x: insets.left, y: insets.top, w: width - insets.left - insets.right, h: height - insets.top - insets.bottom };
    expect(L.rack).toHaveLength(n);
    for (const [name, r] of parts(L)) expect(inside(r, frame), `${name} ${JSON.stringify(r)}`).toBe(true);
    for (const p of L.rack) expect(inside({ x: p.x, y: p.y, w: L.pw, h: L.ph }, L.rackRect)).toBe(true);
  });

  test.each(CASES)("at %i x %i with %i pieces: nothing overlaps", (width, height, n, insets) => {
    const all = parts(layout(width, height, n, insets));
    for (let i = 0; i < all.length; i++)
      for (let j = i + 1; j < all.length; j++) expect(overlaps(all[i]![1], all[j]![1]), `${all[i]![0]} and ${all[j]![0]}`).toBe(false);
  });

  test.each(CASES)("at %i x %i with %i pieces: the pieces are big, and the rack fills its room", (width, height, n, insets) => {
    const L = layout(width, height, n, insets);
    expect(L.pw).toBeGreaterThanOrEqual(44);
    // The rack reads as rows of runs: at least four to a row.
    const rows = new Set(L.rack.map((p) => Math.round(p.y))).size;
    expect(Math.ceil(n / rows)).toBeGreaterThanOrEqual(4);
    // No big empty field: the toy box takes the room the rack leaves.
    expect(L.pool.size).toBeGreaterThanOrEqual(Math.min(96, L.ph));
    const used = L.rackRect.h + L.poolRect.h + L.sort.h;
    const room = height - insets.top - insets.bottom - (L.switch.y + L.switch.h - insets.top);
    expect(used / room).toBeGreaterThan(0.6);
  });

  test("bigger screens get bigger pieces; the top bar grows on a tablet", () => {
    const at = (w: number, h: number, insets: typeof portrait) => layout(w, h, 14, insets);
    expect(at(320, 568, se).pw).toBeLessThan(at(390, 844, portrait).pw);
    expect(at(390, 844, portrait).pw).toBeLessThanOrEqual(at(430, 932, portrait).pw);
    expect(at(430, 932, portrait).pw).toBeLessThan(at(820, 1180, ipad).pw);
    expect(at(390, 844, portrait).unit).toBe(1);
    expect(at(820, 1180, ipad).unit).toBeGreaterThan(1.4);
    expect(at(820, 1180, ipad).menu.w).toBeGreaterThan(60);
  });

  test("taps are at least 44 px", () => {
    for (const [w, h, insets] of SIZES) {
      const L = layout(w, h, 14, insets);
      for (const r of [L.switch, L.menu, L.sort]) expect(Math.min(r.w, r.h)).toBeGreaterThanOrEqual(44);
    }
  });

  test("each row is centred, and a drop finds the place in the rack it is over", () => {
    const L = layout(390, 844, 14, portrait);
    const rows = [...new Set(L.rack.map((p) => p.y))];
    for (const y of rows) {
      const row = L.rack.filter((p) => p.y === y);
      const left = row[0]!.x;
      const right = row[row.length - 1]!.x + L.pw;
      expect(Math.abs(left + right - 390)).toBeLessThan(2);
    }
    const centre = (i: number) => ({ x: L.rack[i]!.x + L.pw / 2, y: L.rack[i]!.y + L.ph / 2 });
    // Over a piece's left half: its place; over its right half: after it.
    expect(L.indexAt({ x: centre(6).x - 4, y: centre(6).y })).toBe(6);
    expect(L.indexAt({ x: centre(6).x + 4, y: centre(6).y })).toBe(7);
    // Past the end of the last row: the end.
    expect(L.indexAt({ x: 380, y: centre(13).y })).toBe(14);
  });
});
