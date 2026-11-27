import { describe, expect, test } from "vitest";

import { ctControllerLayout } from "../src/table/ct-controller-layout";
import { ctLayout, fan, towerReach, trayLabelRect, trayPoses, tvMenu } from "../src/table/ct-layout";
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

describe("Cat Tower on a phone controller", () => {
  /** The safe areas of each frame: notched phones, a home-bar iPad, a phone held sideways. */
  const ipad = { top: 24, right: 0, bottom: 20, left: 0 };
  const CTL_SIZES = [
    [320, 568, portrait],
    [375, 667, portrait],
    [390, 844, portrait],
    [430, 932, portrait],
    [820, 1180, ipad],
    [1180, 820, ipad],
    [844, 390, sideways],
  ] as const;
  const STEPS = ["off", "draw", "play"] as const;
  /** Each size and step, with three trays, or laid down with the hit list shut or open (three rows). */
  const CASES = CTL_SIZES.flatMap(([w, h, insets]) =>
    STEPS.flatMap((step) =>
      [
        [3, 0],
        [0, 0],
        [0, 3],
      ].map(([trays, hits]) => [w, h, step, trays!, hits!, insets] as const),
    ),
  );
  const layout = (width: number, height: number, step: (typeof STEPS)[number], trays: number, insets: typeof portrait, hits = 0) =>
    ctControllerLayout({ width, height, insets, handCount: 11, trays, step, hits: step === "play" && trays === 0 ? hits : 0 });
  /** A card's box as drawn: turned about its centre and scaled. */
  const turned = (p: { x: number; y: number; r?: number; s?: number }, w: number, h: number): Box => {
    const s = p.s ?? 1;
    const a = ((p.r ?? 0) * Math.PI) / 180;
    const bw = (Math.abs(Math.cos(a)) * w + Math.abs(Math.sin(a)) * h) * s;
    const bh = (Math.abs(Math.sin(a)) * w + Math.abs(Math.cos(a)) * h) * s;
    return { x: p.x + w / 2 - bw / 2, y: p.y + h / 2 - bh / 2, w: bw, h: bh };
  };
  const union = (bs: Box[]): Box => {
    const x = Math.min(...bs.map((b) => b.x));
    const y = Math.min(...bs.map((b) => b.y));
    return { x, y, w: Math.max(...bs.map((b) => b.x + b.w)) - x, h: Math.max(...bs.map((b) => b.y + b.h)) - y };
  };
  /** Everything the controller draws, by name. */
  const parts = (L: ReturnType<typeof ctControllerLayout>) => {
    const out: [string, Box][] = [
      ["switch", L.switch],
      ["menu", L.menu],
      ["status", L.status],
      ["hand", union(L.hand.map((p) => turned(p, L.cw, L.ch)))],
    ];
    out.push(["deck", L.piles.deckRect], ["discard", L.piles.discardRect], ["actions", L.actions]);
    L.trays.forEach((t, i) => out.push([`tray ${i}`, t]));
    if (L.hits) out.push(["hit list", L.hits]);
    if (L.hitClose) out.push(["hit list's X", L.hitClose]);
    return out;
  };
  /** The hit list opens over the piles' room, and its X sits inside it: those may overlap. */
  const mayOverlap = (a: string, b: string) => {
    const pair = [a, b].sort().join(" and ");
    return ["deck and hit list", "discard and hit list", "deck and hit list's X", "discard and hit list's X", "hit list and hit list's X"].includes(pair);
  };

  test.each(CASES)("at %i x %i, %s step, %i trays, %i hit rows: everything is inside the safe frame", (width, height, step, trays, hits, insets) => {
    const L = layout(width, height, step, trays, insets, hits);
    const frame = { x: insets.left, y: insets.top, w: width - insets.left - insets.right, h: height - insets.top - insets.bottom };
    for (const [name, r] of parts(L)) {
      expect(within({ x: r.x - frame.x, y: r.y - frame.y, w: r.w, h: r.h }, frame.w, frame.h), `${name} ${JSON.stringify(r)}`).toBe(true);
      expect(r.w, name).toBeGreaterThan(0);
      expect(r.h, name).toBeGreaterThan(0);
    }
    for (const p of L.hand) expect(within(turned(p, L.cw, L.ch), width, height)).toBe(true);
  });

  test.each(CASES)("at %i x %i, %s step, %i trays, %i hit rows: nothing overlaps", (width, height, step, trays, hits, insets) => {
    const L = layout(width, height, step, trays, insets, hits);
    for (const [[a, ra], [b, rb]] of pairs(parts(L))) if (!mayOverlap(a, b)) expect(overlaps(ra, rb), `${a} and ${b}`).toBe(false);
  });

  /** Large text (a 200% root font): the switch widens with its words and the bar still fits. */
  test.each(CTL_SIZES)("at %i x %i with text at 200%%: the switch is wider, inside the frame, and nothing overlaps", (width, height, insets) => {
    for (const step of STEPS) {
      const normal = layout(width, height, step, 3, insets);
      const L = ctControllerLayout({ width, height, insets, handCount: 11, trays: 3, step, text: 2 });
      const frame = { x: insets.left, y: insets.top, w: width - insets.left - insets.right, h: height - insets.top - insets.bottom };
      expect(L.switch.w).toBeGreaterThan(normal.switch.w * 1.8);
      for (const [name, r] of parts(L)) expect(within({ x: r.x - frame.x, y: r.y - frame.y, w: r.w, h: r.h }, frame.w, frame.h), `${name} ${JSON.stringify(r)}`).toBe(true);
      for (const [[a, ra], [b, rb]] of pairs(parts(L))) if (!mayOverlap(a, b)) expect(overlaps(ra, rb), `${a} and ${b}`).toBe(false);
    }
  });

  test.each(CASES)("at %i x %i, %s step, %i trays, %i hit rows: the hand is big, and every card's corner shows", (width, height, step, trays, hits, insets) => {
    const L = layout(width, height, step, trays, insets, hits);
    expect(L.hand).toHaveLength(11);
    expect(L.cw).toBeGreaterThanOrEqual(56);
    for (let i = 1; i < L.hand.length; i++) expect(L.hand[i]!.x - L.hand[i - 1]!.x).toBeGreaterThanOrEqual(L.cw * 0.38 - 0.01);
  });

  test.each(CTL_SIZES)("at %i x %i: the hit list's X is inside the list and the safe frame, and a hit row is tall enough to tap", (width, height, insets) => {
    for (const rows of [1, 2, 3]) {
      const L = layout(width, height, "play", 0, insets, rows);
      const x = L.hitClose!;
      const list = L.hits!;
      expect(x.x).toBeGreaterThanOrEqual(list.x);
      expect(x.y).toBeGreaterThanOrEqual(list.y);
      expect(x.x + x.w).toBeLessThanOrEqual(list.x + list.w);
      expect(x.y + x.h).toBeLessThanOrEqual(list.y + list.h);
      expect(x.x + x.w).toBeLessThanOrEqual(width - insets.right);
      expect(x.w).toBeGreaterThanOrEqual(32);
      // The list sits on the buttons, under the status.
      expect(list.y + list.h).toBeLessThanOrEqual(L.actions.y);
      expect(list.y).toBeGreaterThanOrEqual(L.switch.y + L.switch.h);
    }
  });

  test.each(CTL_SIZES)("at %i x %i: the piles stay put when the hit list opens, and fill their room", (width, height, insets) => {
    const shut = layout(width, height, "play", 0, insets, 0);
    const open = layout(width, height, "play", 0, insets, 3);
    expect(open.piles).toEqual(shut.piles);
    expect(open.hand).toEqual(shut.hand);
    expect(open.actions).toEqual(shut.actions);
    const { deckRect } = shut.piles;
    // As big as the room allows: never under a hand card, and either the width or the height is used up.
    expect(deckRect.w).toBeGreaterThanOrEqual(shut.cw);
    const stageTop = shut.switch.y + shut.switch.h;
    const roomH = shut.landscape ? shut.handRect.y - stageTop : shut.actions.y - stageTop;
    const roomW = shut.landscape ? (shut.handRect.w - 10) / 2 : shut.handRect.w;
    expect(Math.max(deckRect.h / roomH, (2 * deckRect.w) / roomW)).toBeGreaterThan(0.7);
  });

  test("at 320 wide a card is at least 56 px, and grows with the screen", () => {
    const small = layout(320, 568, "play", 3, portrait);
    const big = layout(430, 932, "play", 3, portrait);
    const ipadL = layout(820, 1180, "play", 3, ipad);
    expect(small.cw).toBeGreaterThanOrEqual(56);
    expect(big.cw).toBeGreaterThan(small.cw);
    expect(ipadL.cw).toBeGreaterThan(big.cw);
  });

  test.each(CTL_SIZES)("at %i x %i: your turn's piles are bigger than a card in the hand, and the same in both steps", (width, height, insets) => {
    const draw = layout(width, height, "draw", 3, insets);
    const play = layout(width, height, "play", 3, insets);
    expect(draw.piles.deckRect.w).toBeGreaterThanOrEqual(draw.cw * 0.9);
    expect(play.piles).toEqual(draw.piles);
    expect(play.hand).toEqual(draw.hand);
  });

  test.each(CTL_SIZES)("at %i x %i: off turn is the same frame as your turn, so nothing jumps when it comes", (width, height, insets) => {
    for (const trays of [0, 2, 3]) {
      const off = layout(width, height, "off", trays, insets);
      for (const step of ["draw", "play"] as const) expect(layout(width, height, step, trays, insets)).toEqual(off);
    }
  });

  test("buttons are big enough to tap: the switch, the actions and each tray", () => {
    for (const [w, h, insets] of CTL_SIZES) {
      const L = layout(w, h, "play", 3, insets);
      expect(L.switch.h).toBeGreaterThanOrEqual(44);
      expect(L.actions.h).toBeGreaterThanOrEqual(44);
      for (const t of L.trays) expect(t.h).toBeGreaterThanOrEqual(44);
    }
  });

  test("the menu's place is the table menu's: the top-right corner of the safe area, at the unit", () => {
    for (const [w, h, insets] of CTL_SIZES) {
      const L = layout(w, h, "draw", 3, insets);
      expect(L.menu).toEqual({ x: w - insets.right - 8 - 44 * L.unit, y: insets.top + 8, w: 44 * L.unit, h: 44 * L.unit });
    }
  });

  test("a phone's top bar is phone-sized; a tablet's grows with its cards, up to 1.6", () => {
    for (const [w, h] of [
      [320, 568],
      [390, 844],
      [430, 932],
    ] as const)
      expect(layout(w, h, "draw", 3, portrait).unit).toBe(1);
    for (const [w, h] of [
      [820, 1180],
      [1180, 820],
    ] as const) {
      const L = layout(w, h, "draw", 3, ipad);
      expect(L.unit).toBeGreaterThan(1.3);
      expect(L.unit).toBeLessThanOrEqual(1.6);
      expect(L.switch.h).toBeCloseTo(44 * L.unit);
    }
  });

  test("on a tablet the hand is bigger than a phone's, and a tray's cards are big too", () => {
    for (const [w, h] of [
      [820, 1180],
      [1180, 820],
    ] as const) {
      const L = layout(w, h, "play", 2, ipad);
      expect(L.cw).toBeGreaterThan(132);
      expect(L.cw * L.small).toBeGreaterThanOrEqual(70);
      for (const t of L.trays) expect(t.w).toBeLessThanOrEqual(L.cw * 4.6 + 0.5);
    }
  });

  test("off turn on a phone, the status is in the top bar beside the menu, so a tip under the switch never covers it", () => {
    for (const [w, h] of [
      [320, 568],
      [390, 844],
      [430, 932],
    ] as const) {
      const L = layout(w, h, "off", 0, portrait);
      expect(L.status.y).toBe(L.menu.y);
      expect(L.switch.y).toBeGreaterThan(L.status.y + L.status.h);
    }
  });
});

/**
 * The phone's full table and its trays, at every size it is played on, at the default text and the
 * largest (a 26 px root, 1.625): no name tag on the tower or on cards, no tray's count under its cards.
 */
describe("Cat Tower on a phone's full table: nothing overlaps", () => {
  const TEXT = [1, 1.625] as const;
  /** Who has laid down: one seat, two, a full table of five rows, and long groups. */
  const TABLES: { name: string; laid: { seat: number; groups: number[] }[] }[] = [
    { name: "one row", laid: [{ seat: 0, groups: [3, 3] }] },
    { name: "two rows", laid: [{ seat: 0, groups: [3, 3] }, { seat: 1, groups: [3, 4] }] },
    {
      name: "five rows",
      laid: [
        { seat: 0, groups: [3, 3] },
        { seat: 1, groups: [4, 4] },
        { seat: 2, groups: [9] },
        { seat: 3, groups: [5, 2] },
        { seat: 4, groups: [7] },
      ],
    },
    { name: "long groups", laid: [{ seat: 0, groups: [5, 6] }, { seat: 1, groups: [12] }] },
  ];
  const CASES = SIZES.flatMap(([w, h]) => TEXT.flatMap((text) => TABLES.flatMap((t) => [0, 2].map((trays) => [w, h, text, t.name, trays] as const))));
  const layout = (width: number, height: number, text: number, table: string, trays: number) =>
    ctLayout({ width, height, insets: insetsFor(width, height), opponents: [1, 2, 3, 4, 5], handCount: trays ? 6 : 2, trays, laid: TABLES.find((t) => t.name === table)!.laid, text });

  /** Everything on the table, by name, with the tower as far as its shelf numbers reach. */
  const parts = (L: ReturnType<typeof ctLayout>, width: number) => {
    const out: [string, Box][] = [
      ["tower", { ...L.tower, w: L.tower.w + towerReach(L.tower.w) }],
      // The seats across the top: each cat and its name tag under it.
      ["seats", { x: 0, y: 0, w: width, h: Math.max(...[...L.opponents.values()].map((at) => at.y + L.avatar / 2 + 22)) }],
      ["deck", L.deckRect],
      ["discard", L.discardRect],
      ["hand", L.handRect],
      ["cue", L.banner],
    ];
    L.trays.forEach((t, i) => out.push([`tray ${i}`, t]));
    for (const [s, row] of L.laid) {
      out.push([`row ${s} name`, row.tag]);
      if (row.avatar.size) out.push([`row ${s} cat`, circle(row.avatar, row.avatar.size)]);
      row.groups.forEach((g, i) => out.push([`row ${s} group ${i}`, g.rect]));
    }
    return out;
  };
  /** A row's cat sits on its name tag's top, as a seat's does; the hand's room is where a picked card rises, over the cue. */
  const mayOverlap = (a: string, b: string) => {
    const [x, y] = [a, b].sort();
    const row = (n: string) => n.match(/^row (\d+) (name|cat)$/)?.[1];
    if (row(x!) !== undefined && row(x!) === row(y!)) return true;
    return [x, y].join(" and ") === "cue and hand";
  };

  test.each(CASES)("at %i x %i, text %d, %s, %i trays: names, cats, groups, the tower, the piles and the trays are apart", (width, height, text, table, trays) => {
    const L = layout(width, height, text, table, trays);
    const all = parts(L, width);
    for (const [[a, ra], [b, rb]] of pairs(all)) if (!mayOverlap(a, b)) expect(overlaps(ra, rb), `${a} ${JSON.stringify(ra)} and ${b} ${JSON.stringify(rb)}`).toBe(false);
  });

  test.each(CASES)("at %i x %i, text %d, %s, %i trays: every name tag and group is on screen, a tag is big enough to read", (width, height, text, table, trays) => {
    const L = layout(width, height, text, table, trays);
    const insets = insetsFor(width, height);
    for (const [s, row] of L.laid) {
      for (const r of [row.tag, ...row.groups.map((g) => g.rect)]) expect(within(r, width, height), `row ${s} ${JSON.stringify(r)}`).toBe(true);
      expect(row.tag.x).toBeGreaterThanOrEqual(insets.left);
      expect(row.tag.w).toBeGreaterThanOrEqual(56);
      expect(row.font).toBeGreaterThanOrEqual(10);
      // The tag fits its line of text.
      expect(row.tag.h).toBeGreaterThanOrEqual(row.font * 1.2 + 5);
    }
  });

  test.each(SIZES)("at %i x %i: a larger text size makes the name tags larger", (width, height) => {
    const normal = layout(width, height, 1, "two rows", 0);
    const large = layout(width, height, 1.625, "two rows", 0);
    expect(large.laid.get(0)!.font).toBeGreaterThan(normal.laid.get(0)!.font);
  });
});

describe("Cat Tower trays: the count is never under the cards", () => {
  const TEXT = [1, 1.625, 2] as const;
  /** Every tray a level asks for: two of three, three and four, a run of nine, five and two. */
  const LEVELS = [[3, 3], [3, 4], [9], [5, 2], [5, 3], [4, 4]];
  const ipad = { top: 24, right: 0, bottom: 20, left: 0 };
  const CTL_SIZES = [
    [320, 568, portrait],
    [375, 667, portrait],
    [430, 932, portrait],
    [820, 1180, ipad],
    [1180, 820, ipad],
    [844, 390, sideways],
  ] as const;
  const check = (L: { trays: Box[]; trayLabel: { font: number; w: number }; cw: number; ch: number; small: number }, sizes: number[]) => {
    L.trays.forEach((tray, i) => {
      const size = sizes[i]!;
      const label = trayLabelRect(tray, L.trayLabel);
      expect(label.x + label.w, "the count is inside its tray").toBeLessThanOrEqual(tray.x + tray.w);
      expect(L.trayLabel.font).toBeGreaterThanOrEqual(13);
      for (let n = 1; n <= size; n++) {
        for (const p of trayPoses(tray, n, size, L.cw, L.ch, L.small, L.trayLabel)) {
          const card = visual(p, L.cw, L.ch);
          expect(overlaps(card, label), `${n} of ${size} in tray ${i}: card ${JSON.stringify(card)}, count ${JSON.stringify(label)}`).toBe(false);
          expect(card.x + card.w, "the card is inside its tray").toBeLessThanOrEqual(tray.x + tray.w + 0.5);
          expect(card.y).toBeGreaterThanOrEqual(tray.y);
        }
      }
    });
  };

  test.each(SIZES.flatMap(([w, h]) => TEXT.map((t) => [w, h, t] as const)))("on the full table at %i x %i, text %d", (width, height, text) => {
    for (const level of LEVELS) {
      const L = ctLayout({ width, height, insets: insetsFor(width, height), opponents: [1, 2], handCount: 8, trays: level.length, laid: [], text });
      check(L, level);
    }
  });

  test.each(CTL_SIZES.flatMap(([w, h, insets]) => TEXT.map((t) => [w, h, t, insets] as const)))("on Cards at a TV table at %i x %i, text %d", (width, height, text, insets) => {
    for (const level of LEVELS) {
      const L = ctControllerLayout({ width, height, insets, handCount: 8, trays: level.length, step: "play", text });
      check(L, level);
    }
  });

  test("the count grows with the text, and with a tablet's controls", () => {
    const at = (text: number) => ctControllerLayout({ width: 375, height: 667, insets: portrait, handCount: 8, trays: 2, step: "play", text }).trayLabel;
    expect(at(1.625).font).toBeGreaterThan(at(1).font);
    expect(at(1.625).w).toBeGreaterThan(at(1).w);
    const tablet = ctControllerLayout({ width: 820, height: 1180, insets: { top: 24, right: 0, bottom: 20, left: 0 }, handCount: 8, trays: 2, step: "play" });
    expect(tablet.trayLabel.font).toBeGreaterThan(at(1).font);
  });
});
