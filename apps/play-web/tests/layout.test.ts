import { describe, expect, test } from "vitest";

import { ctLayout, fan, tvMenu } from "../src/table/ct-layout";
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

type Box = { x: number; y: number; w: number; h: number };
const none = { top: 0, right: 0, bottom: 0, left: 0 };
const seatsOf = (n: number) => Array.from({ length: n }, (_, i) => i);
/** TV frames: width, height and overscan on every side. Not all 16:9, as browsers on TVs and laptops aren't. */
const TV_FRAMES = [
  [1280, 720, 0],
  [1440, 900, 0],
  [1920, 1080, 0],
  [1920, 1200, 0],
  [2560, 1080, 0],
  [3840, 2160, 0],
  [1920, 1080, 54],
] as const;
const inset = (n: number) => ({ top: n, right: n, bottom: n, left: n });
/** Two boxes overlap when they share more than a hair (half a pixel) of area. */
const overlaps = (a: Box, b: Box) => Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 0.5 && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 0.5;
/** Inside the frame, and clear of `edge` (overscan) on every side. */
const within = (r: Box, width: number, height: number, edge = 0) => r.x >= edge - 0.5 && r.y >= edge - 0.5 && r.x + r.w <= width - edge + 0.5 && r.y + r.h <= height - edge + 0.5;
const circle = (at: { x: number; y: number }, size: number): Box => ({ x: at.x - size / 2, y: at.y - size / 2, w: size, h: size });
/** A pose's visual box: a scaled element shrinks about its centre. */
const visual = (p: { x: number; y: number; s?: number }, w: number, h: number): Box => {
  const s = p.s ?? 1;
  return { x: p.x + (w * (1 - s)) / 2, y: p.y + (h * (1 - s)) / 2, w: w * s, h: h * s };
};
const pairs = <T>(xs: T[]) => xs.flatMap((a, i) => xs.slice(i + 1).map((b) => [a, b] as const));
/** Every number in a layout by its path, but a pose's turn, scale and stacking, which don't scale with the screen. */
function numbers(v: unknown, path = "", out = new Map<string, number>()): Map<string, number> {
  if (typeof v === "number") out.set(path, v);
  else if (v instanceof Map) for (const [k, x] of v) numbers(x, `${path}.${String(k)}`, out);
  else if (Array.isArray(v)) v.forEach((x, i) => numbers(x, `${path}[${i}]`, out));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) if (k !== "r" && k !== "s" && k !== "z") numbers(x, `${path}.${k}`, out);
  return out;
}
const expectDoubled = (small: unknown, big: unknown) => {
  const a = numbers(small);
  const b = numbers(big);
  expect([...b.keys()]).toEqual([...a.keys()]);
  for (const [k, x] of a) expect(Math.abs(b.get(k)! - 2 * x), k).toBeLessThanOrEqual(1);
};

describe("Cat Tower on a TV", () => {
  /**
   * The worst table, every seat laid down with three groups of ten, or a sparse one: two seats
   * down with a phase's groups, nobody else.
   */
  const tv = (width: number, height: number, n: number, edge = 0, table: "full" | "sparse" = "full") => {
    const seats = seatsOf(n);
    const laid = table === "full" ? seats.map((seat) => ({ seat, groups: [10, 10, 10] })) : [0, n - 1].map((seat) => ({ seat, groups: [4, 7] }));
    return ctLayout({ width, height, insets: inset(edge), opponents: seats, handCount: 0, trays: 0, laid, tv: true });
  };
  const CASES = TV_FRAMES.flatMap(([w, h, e]) => [2, 3, 4, 5, 6].flatMap((n) => (["full", "sparse"] as const).map((t) => [w, h, e, n, t] as const)));
  const groupsOf = (L: ReturnType<typeof tv>) => [...L.laid.values()].flatMap((row) => row.groups.map((g) => g.rect));

  test.each(CASES)("at %i x %i, overscan %i, with %i seats, %s table: nothing private, every seat around the table", (width, height, edge, n, table) => {
    const L = tv(width, height, n, edge, table);
    expect(L.hand).toEqual([]);
    expect(L.trays).toEqual([]);
    expect([...L.opponents.keys()].sort()).toEqual(seatsOf(n));
    expect([...L.seats.keys()].sort()).toEqual(seatsOf(n));
    expect([...L.laid.keys()].sort()).toEqual(table === "full" ? seatsOf(n) : [0, n - 1]);
  });

  test.each(CASES)("at %i x %i, overscan %i, with %i seats, %s table: everything is inside the frame", (width, height, edge, n, table) => {
    const L = tv(width, height, n, edge, table);
    const rects: Box[] = [L.tower, L.rug, L.deckRect, L.discardRect, L.banner, L.bannerRoom, L.menu, ...L.seats.values(), ...[...L.opponents.values()].map((at) => circle(at, L.avatar)), ...groupsOf(L)];
    for (const row of L.laid.values()) for (const g of row.groups) for (const p of g.poses) rects.push(visual(p, L.cw, L.ch));
    for (const r of rects) expect(within(r, width, height, edge), JSON.stringify(r)).toBe(true);
  });

  test.each(CASES)("at %i x %i, overscan %i, with %i seats, %s table: seats, cats, groups, piles and the banner never overlap", (width, height, edge, n, table) => {
    const L = tv(width, height, n, edge, table);
    const seats = [...L.seats.values()];
    for (const [a, b] of pairs(seats)) expect(overlaps(a, b), `${JSON.stringify(a)} ${JSON.stringify(b)}`).toBe(false);
    // Each cat sits inside its own seat.
    for (const [s, at] of L.opponents) {
      const c = circle(at, L.avatar);
      const r = L.seats.get(s)!;
      expect(c.x >= r.x - 0.5 && c.y >= r.y - 0.5 && c.x + c.w <= r.x + r.w + 0.5 && c.y + c.h <= r.y + r.h + 0.5).toBe(true);
    }
    const groups = groupsOf(L);
    const piles = [L.deckRect, L.discardRect];
    for (const [a, b] of pairs(groups)) expect(overlaps(a, b)).toBe(false);
    for (const g of groups) for (const other of [...piles, ...seats, L.tower]) expect(overlaps(g, other), `${JSON.stringify(g)} ${JSON.stringify(other)}`).toBe(false);
    for (const other of [...piles, ...groups, ...seats, L.tower]) expect(overlaps(L.banner, other), JSON.stringify(other)).toBe(false);
    for (const s of seats) for (const other of [...piles, L.tower]) expect(overlaps(s, other)).toBe(false);
    // The rug under the piles stays clear of the banner.
    expect(overlaps(L.rug, L.banner)).toBe(false);
    // A long name's banner, as wide as it may grow, keeps clear of everything.
    for (const other of [...piles, ...groups, ...seats, L.tower, L.rug, L.menu]) expect(overlaps(L.bannerRoom, other), JSON.stringify(other)).toBe(false);
    // The menu's corner is free of everything on the table.
    const cats = [...L.opponents.values()].map((at) => circle(at, L.avatar));
    for (const other of [...piles, ...groups, ...seats, ...cats, L.tower, L.rug, L.banner]) expect(overlaps(L.menu, other), JSON.stringify(other)).toBe(false);
    expect(L.menu.w).toBeGreaterThan(0);
  });

  test.each([2, 3, 4, 5, 6])("at 1920 x 1080 with %i seats: big enough to read from the couch", (n) => {
    const L = tv(1920, 1080, n);
    expect(L.cw).toBeGreaterThanOrEqual(112);
    expect(L.avatar).toBeGreaterThanOrEqual(132);
    expect(L.banner.h).toBeGreaterThanOrEqual(64);
    // A laid card's two-digit numeral (46% of its width) is at least 28 px.
    for (const row of L.laid.values()) for (const g of row.groups) for (const p of g.poses) expect(L.cw * (p.s ?? 1) * 0.46).toBeGreaterThanOrEqual(28);
  });

  test.each([2, 3, 4, 5, 6])("at 3840 x 2160 with %i seats: everything is twice the size", (n) => {
    expectDoubled(tv(1920, 1080, n), tv(3840, 2160, n));
  });

  test("a seat with no groups down yet keeps its place", () => {
    const seats = seatsOf(4);
    const L = ctLayout({ width: 1920, height: 1080, insets: none, opponents: seats, handCount: 0, trays: 0, laid: [{ seat: 2, groups: [3, 4] }], tv: true });
    const M = tv(1920, 1080, 4);
    expect(L.seats).toEqual(M.seats);
    expect(L.deckRect).toEqual(M.deckRect);
    expect([...L.laid.keys()]).toEqual([2]);
  });

  test.each([2, 3, 4, 5, 6])("at 1920 x 1080 with %i seats: a seat across the top is as wide as its room allows, up to 560", (n) => {
    const L = tv(1920, 1080, n);
    const top = [...L.seats.values()].filter((r) => r.y < 100);
    for (const r of top) expect(r.w).toBeGreaterThanOrEqual(372);
    if (n === 3 || n === 4) for (const r of top) expect(r.w).toBe(560);
    for (const r of L.seats.values()) expect(r.w).toBeLessThanOrEqual(560);
  });

  test("more seats than the game has is refused, never a seat left out", () => {
    expect(() => tv(1920, 1080, 7)).toThrow(RangeError);
  });
});

test.each(TV_FRAMES)("at %i x %i, overscan %i: both games put the menu in the same corner", (width, height, edge) => {
  const ct = ctLayout({ width, height, insets: inset(edge), opponents: seatsOf(4), handCount: 0, trays: 0, laid: [], tv: true });
  const tt = tilesLayout({ width, height, insets: inset(edge), opponents: seatsOf(4), sets: [3], rack: 0, tv: true });
  expect(ct.menu).toEqual(tt.menu);
  expect(ct.menu).toEqual(tvMenu(width, height, inset(edge)));
});

describe("Tuna Tiles on a TV", () => {
  /** The worst board: thirty sets of three. */
  const tv = (width: number, height: number, n: number, edge = 0) => tilesLayout({ width, height, insets: inset(edge), opponents: seatsOf(n), sets: Array.from({ length: 30 }, () => 3), rack: 0, tv: true });
  const CASES = TV_FRAMES.flatMap(([w, h, e]) => [2, 3, 4].map((n) => [w, h, e, n] as const));

  test.each(CASES)("at %i x %i, overscan %i, with %i seats: everything is inside the frame, nothing private", (width, height, edge, n) => {
    const L = tv(width, height, n, edge);
    expect(L.rack).toEqual([]);
    expect([...L.seats.keys()].sort()).toEqual(seatsOf(n));
    const pool = { x: L.pool.x, y: L.pool.y, w: L.pool.size, h: L.pool.size };
    const rects: Box[] = [L.board, pool, L.banner, L.bannerRoom, L.menu, ...L.seats.values(), ...[...L.opponents.values()].map((at) => circle(at, L.avatar))];
    for (const set of L.sets) {
      rects.push(set.rect);
      for (const p of set.poses) rects.push(visual(p, L.pw, L.ph));
    }
    for (const r of rects) expect(within(r, width, height, edge), JSON.stringify(r)).toBe(true);
    for (const set of L.sets) for (const p of set.poses) expect(within(visual(p, L.pw, L.ph), L.board.x + L.board.w, L.board.y + L.board.h) && p.y >= L.board.y && p.x >= L.board.x).toBe(true);
  });

  test.each(CASES)("at %i x %i, overscan %i, with %i seats: seats, sets, the toy box and the banner never overlap", (width, height, edge, n) => {
    const L = tv(width, height, n, edge);
    const seats = [...L.seats.values()];
    const pool = { x: L.pool.x, y: L.pool.y, w: L.pool.size, h: L.pool.size };
    for (const [a, b] of pairs(seats)) expect(overlaps(a, b)).toBe(false);
    for (const [s, at] of L.opponents) {
      const c = circle(at, L.avatar);
      const r = L.seats.get(s)!;
      expect(c.x >= r.x - 0.5 && c.y >= r.y - 0.5 && c.x + c.w <= r.x + r.w + 0.5 && c.y + c.h <= r.y + r.h + 0.5).toBe(true);
    }
    const sets = L.sets.map((s) => s.rect);
    for (const [a, b] of pairs(sets)) expect(overlaps(a, b)).toBe(false);
    for (const set of sets) for (const other of [...seats, pool, L.banner]) expect(overlaps(set, other)).toBe(false);
    for (const other of [...seats, pool]) expect(overlaps(L.banner, other)).toBe(false);
    for (const s of seats) expect(overlaps(s, L.board)).toBe(false);
    for (const other of [...seats, ...sets, pool, L.board, L.menu]) expect(overlaps(L.bannerRoom, other), JSON.stringify(other)).toBe(false);
    const cats = [...L.opponents.values()].map((at) => circle(at, L.avatar));
    for (const other of [...seats, ...cats, ...sets, pool, L.board, L.banner]) expect(overlaps(L.menu, other), JSON.stringify(other)).toBe(false);
  });

  test.each([2, 3, 4])("at 1920 x 1080 with %i seats: big enough to read from the couch", (n) => {
    const L = tv(1920, 1080, n);
    expect(L.pw).toBeGreaterThanOrEqual(52);
    expect(L.avatar).toBeGreaterThanOrEqual(132);
    expect(L.banner.h).toBeGreaterThanOrEqual(64);
  });

  test.each([2, 3, 4])("at 3840 x 2160 with %i seats: everything is twice the size", (n) => {
    expectDoubled(tv(1920, 1080, n), tv(3840, 2160, n));
  });

  test.each([2, 3, 4])("at 1920 x 1080 with %i seats: a seat is as wide as its room allows, up to 560", (n) => {
    const L = tv(1920, 1080, n);
    for (const r of L.seats.values()) {
      expect(r.w).toBeGreaterThanOrEqual(372);
      expect(r.w).toBeLessThanOrEqual(560);
      if (n <= 3) expect(r.w).toBe(560);
    }
  });

  test("more seats than the game has is refused, never a seat left out", () => {
    expect(() => tv(1920, 1080, 5)).toThrow(RangeError);
  });

  test("a near-empty board draws its pieces bigger", () => {
    const few = tilesLayout({ width: 1920, height: 1080, insets: none, opponents: seatsOf(4), sets: [3, 4], rack: 0, tv: true });
    expect(few.pw).toBeGreaterThan(tv(1920, 1080, 4).pw);
  });
});
