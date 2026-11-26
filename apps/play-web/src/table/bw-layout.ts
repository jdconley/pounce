/**
 * Where everything sits on a Birdwatch table (design §5.2): the other cats around the window, the
 * sill with the trick in the middle (each card in front of the cat that played it), the score
 * strip, the panel for this step (bid, trump, nest, the cue), and the hand. Pure geometry from the
 * screen's size and what is on it, like ct-layout.ts: tested without a browser, computed once per
 * change, never per frame.
 */
import { fan, TV, TV_H, TV_MENU, TV_W, bannerRoomOf, tvMap, type Insets } from "./ct-layout";

import type { Rect } from "./drag";
import type { Pose } from "./motion";

export type BwInput = {
  width: number;
  height: number;
  insets: Insets;
  /** The seat whose hand this is (bottom of the screen), or null for a TV or a spectator. */
  me: number | null;
  /** Every other seat, in play order from `me`'s left (bw-model `othersInOrder`). */
  others: number[];
  /** Cards in the hand on show. */
  hand: number;
  /** A TV across the room: no hand, sized for the couch. */
  tv?: boolean;
  /** The phone's Cards view while a TV shows the table: no window or sill, a bigger hand. */
  cards?: boolean;
};

export type BwLayout = {
  landscape: boolean;
  /** A card's size at scale 1 (the hand's). */
  cw: number;
  ch: number;
  avatar: number;
  /** Each other seat: its cat's centre, and the box its cat, name and sign take. */
  seats: Map<number, { x: number; y: number }>;
  seatRects: Map<number, Rect>;
  /** The window the cats sit around, and the sill inside it where the trick lands. */
  window: Rect;
  sill: Rect;
  /** Where each seat's card lands on the sill (mine too), at `sillScale`. */
  slots: Map<number, Pose>;
  sillScale: number;
  /** The trump badge and the high bid, in the sill's corner. */
  trump: Rect;
  /** The score strip: one chip per side. Stacked down a column when `stripColumn`. */
  strip: Rect;
  stripColumn: boolean;
  /** This step's controls (bid, trump, nest) or the cue line. */
  panel: Rect;
  hand: Pose[];
  handRect: Rect;
  /** TV only: where "<Name>'s turn" sits. On a phone, the panel's cue line. */
  banner: Rect;
  bannerRoom: Rect;
  /** TV only: the menu's corner. On a phone, the paw's (top right). */
  menu: Rect;
  centre: { x: number; y: number };
};

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

/** The least of a card that shows under the next in the hand: its numeral's corner. */
export const MIN_SHOW = 24;

/**
 * The hand's poses: one fan when it fits with each card's corner showing, else two rows (the
 * nest's 17 cards on a small phone), the back row's corners above the front row.
 */
export function handPoses(n: number, centreX: number, baseY: number, cw: number, ch: number, maxWidth: number): { poses: Pose[]; rows: 1 | 2 } {
  const minStep = Math.max(MIN_SHOW, cw * 0.36);
  if (n <= 1 || (n - 1) * minStep + cw <= maxWidth) return { poses: fan(n, centreX, baseY, cw, ch, maxWidth), rows: 1 };
  const back = Math.ceil(n / 2);
  const front = n - back;
  const lift = ch * 0.46;
  const top = fan(back, centreX, baseY - lift, cw, ch, maxWidth).map((p) => ({ ...p, r: (p.r ?? 0) * 0.5, z: 100 + (p.z ?? 0) - 100 }));
  const bottom = fan(front, centreX, baseY, cw, ch, maxWidth).map((p, i) => ({ ...p, r: (p.r ?? 0) * 0.5, z: 200 + i }));
  return { poses: [...top, ...bottom], rows: 2 };
}

/** The widest a hand's cards may be for `n` of them to fit `maxWidth` in its rows. */
function cardFor(n: number, maxWidth: number, want: number): number {
  const rows = n > 12 ? 2 : 1;
  const perRow = Math.ceil(n / rows);
  // Each row: one whole card plus a corner of each of the others.
  const fits = (cw: number) => (perRow - 1) * Math.max(MIN_SHOW, cw * 0.36) + cw <= maxWidth;
  let cw = want;
  while (cw > 40 && !fits(cw)) cw -= 2;
  return cw;
}

/**
 * Seats around an ellipse at `angles` (degrees, counter-clockwise from the right, y up), each
 * `seatW` by `seatH`, centred on `c`.
 */
function ring(seats: number[], angles: number[], c: { x: number; y: number }, rx: number, ry: number, avatar: number, seatW: number, seatH: number) {
  const centres = new Map<number, { x: number; y: number }>();
  const rects = new Map<number, Rect>();
  seats.forEach((s, i) => {
    const a = ((angles[i] ?? 0) * Math.PI) / 180;
    const x = c.x + Math.cos(a) * rx;
    // The seat's box is its cat with the name under it: its centre sits a little below the cat's.
    const boxY = c.y - Math.sin(a) * ry;
    const rect = { x: x - seatW / 2, y: boxY - seatH / 2, w: seatW, h: seatH };
    rects.set(s, rect);
    centres.set(s, { x, y: rect.y + avatar / 2 + 4 });
  });
  return { centres, rects };
}


const MIN_AVATAR = 34;

/** A seat's box for a cat `avatar` wide: the cat, its name under it, its bid sign over its corner. */
const seatBox = (avatar: number) => ({ w: Math.round(avatar * 1.6), h: avatar + 30 });

const anyOverlap = (rects: Rect[], slack = 4): boolean =>
  rects.some((a, i) => rects.some((b, j) => j > i && a.x + slack < b.x + b.w && b.x + slack < a.x + a.w && a.y + slack < b.y + b.h && b.y + slack < a.y + a.h));

/** The sill inside `window`: between the seats beside the centre, below every seat above it. */
function sillAmong(window: Rect, rects: Rect[]): Rect {
  const c = { x: window.x + window.w / 2, y: window.y + window.h / 2 };
  const besides = rects.filter((r) => r.y + r.h > c.y && r.y < c.y);
  const above = rects.filter((r) => !besides.includes(r));
  const left = Math.max(window.x, ...besides.filter((r) => r.x + r.w / 2 < c.x).map((r) => r.x + r.w + 6));
  const right = Math.min(window.x + window.w, ...besides.filter((r) => r.x + r.w / 2 > c.x).map((r) => r.x - 6));
  const top = Math.max(window.y, ...above.map((r) => r.y + r.h + 6));
  return { x: left, y: top, w: Math.max(0, right - left), h: Math.max(0, window.y + window.h - top) };
}

/**
 * The others' seats and the sill they leave. Tries the ring (cats beside the sill and over it),
 * then a row along the window's top, each with cats as big as `avatar0` and smaller, and takes
 * the first that overlaps nothing and leaves the sill room for a trick.
 */
function placeSeats(others: number[], window: Rect, avatar0: number, cw: number, ch: number, short: boolean) {
  const c = { x: window.x + window.w / 2, y: window.y + window.h / 2 };
  const roomy = (sill: Rect) => sill.w >= cw * 0.42 * 2.3 && sill.h >= ch * 0.42 * 1.95;
  const tryRing = (avatar: number) => {
    const { w, h } = seatBox(avatar);
    const angles = phoneAngles(others.length);
    const { centres, rects } = ring(others, angles, c, Math.max(0, window.w / 2 - w / 2), Math.max(0, window.h / 2 - h / 2), avatar, w, h);
    return { seats: centres, seatRects: rects, angles, avatar, sill: sillAmong(window, [...rects.values()]) };
  };
  const tryRow = (avatar: number) => {
    const { w, h } = seatBox(avatar);
    const slot = window.w / Math.max(others.length, 1);
    const seats = new Map<number, { x: number; y: number }>();
    const seatRects = new Map<number, Rect>();
    others.forEach((s, i) => {
      const x = window.x + slot * (i + 0.5);
      seatRects.set(s, { x: x - w / 2, y: window.y, w, h });
      seats.set(s, { x, y: window.y + avatar / 2 + 4 });
    });
    // Seats in a row point down at the sill from above: left of centre leans left.
    const angles = others.map((_, i) => 180 - (i * 180) / Math.max(others.length - 1, 1));
    const sill = { x: window.x, y: window.y + h + 6, w: window.w, h: Math.max(0, window.h - h - 6) };
    return { seats, seatRects, angles, avatar, sill };
  };
  const sizes: number[] = [];
  for (let a = avatar0; a >= MIN_AVATAR; a -= 4) sizes.push(a);
  // A short window (a phone on its side) seats the cats along its top first.
  const plans = short ? [tryRow, tryRing] : [tryRing, tryRow];
  for (const plan of plans) {
    for (const a of sizes) {
      const p = plan(a);
      if (!anyOverlap([...p.seatRects.values()]) && roomy(p.sill)) return p;
    }
  }
  return tryRow(MIN_AVATAR);
}

/** Angles for a phone's others: from my left, over the top, to my right. */
const phoneAngles = (n: number): number[] => (n === 1 ? [90] : Array.from({ length: n }, (_, i) => 180 - (i * 180) / (n - 1)));

/** Angles for a table seen from outside (a TV): seat 0 at the bottom, then on round to the left. */
const tvAngles = (n: number): number[] => Array.from({ length: n }, (_, i) => 270 - (i * 360) / n);

/** Each seat's card on the sill: towards its cat from the sill's centre, overlapping like a real trick. */
function slotsFor(sill: Rect, seats: { seat: number; angle: number }[], cw: number, ch: number, s: number): Map<number, Pose> {
  const cx = sill.x + sill.w / 2;
  const cy = sill.y + sill.h / 2;
  const out = new Map<number, Pose>();
  // A scaled card shrinks about its centre: its pose is the unscaled card's corner.
  const reachX = Math.max(0, Math.min(cw * s * 0.62, sill.w / 2 - (cw * s) / 2 - 4));
  const reachY = Math.max(0, Math.min(ch * s * 0.42, sill.h / 2 - (ch * s) / 2 - 4));
  seats.forEach(({ seat, angle }, i) => {
    const a = (angle * Math.PI) / 180;
    const x = cx + Math.cos(a) * reachX;
    const y = cy - Math.sin(a) * reachY;
    out.set(seat, { x: x - cw / 2, y: y - ch / 2, r: ((seat * 37) % 11) - 5, s, z: 300 + i });
  });
  return out;
}

export function bwLayout(input: BwInput): BwLayout {
  if (input.tv) return tvBird(input);
  // A wide screen gets a table no wider than it needs, centred, the room on either side.
  const stage = Math.min(input.width, Math.max(input.height * 1.75, 360), 1500);
  if (stage >= input.width - 1) return input.cards ? cardsOn(input) : phoneOn(input);
  const dx = (input.width - stage) / 2;
  const inner = { ...input, width: stage, insets: { ...input.insets, left: 0, right: 0 } };
  return shift(input.cards ? cardsOn(inner) : phoneOn(inner), dx);
}

function phoneOn(input: BwInput): BwLayout {
  const { width: W, height: H, insets } = input;
  const landscape = W > H * 1.15;
  const pad = 10;
  const usable = H - insets.top - insets.bottom;
  const avatar0 = Math.round(landscape ? clamp(usable / 8, 40, 84) : clamp(Math.min(W / 6.4, usable / 10.5), 42, 88));
  const handMax = Math.min(W - insets.left - insets.right - 2 * pad, 1180);
  const want = Math.round(landscape ? clamp(Math.min(W / 11, usable / 5.2), 44, 104) : clamp(Math.min(W / 5.6, usable / 6.8), 50, 112));
  const cw = cardFor(input.hand, handMax, want);
  const ch = Math.round(cw * 1.4);
  const handBase = H - insets.bottom - 8;
  const { poses: hand } = handPoses(input.hand, W / 2, handBase, cw, ch, handMax);
  // Room over the fan's highest card for a card lifted to play (a fifth of its height).
  const handTop = Math.min(handBase - ch, ...hand.map((p) => p.y)) - ch * 0.2 - 6;
  const handRect = { x: (W - handMax) / 2, y: handTop, w: handMax, h: handBase - handTop + 4 };

  // The panel and the strip: under the window in portrait; a column on the right sideways.
  const panelH = Math.round(landscape ? clamp(usable * 0.26, 92, 140) : clamp(usable * 0.16, 100, 150));
  const top = insets.top + 8;
  let window: Rect;
  let panel: Rect;
  let strip: Rect;
  // A phone on its side: the strip and the panel take a column on the right, so the window keeps its height.
  const column = landscape && usable < 600;
  if (column) {
    const colW = Math.round(clamp(W * 0.3, 220, 380));
    const colX = W - insets.right - pad - colW;
    // Below the paw's corner.
    strip = { x: colX, y: top + 52, w: colW, h: 0 };
    panel = { x: colX, y: handTop - panelH - 6, w: colW, h: panelH };
    strip.h = Math.max(40, panel.y - 8 - strip.y);
    window = { x: insets.left + pad, y: top, w: colX - 12 - (insets.left + pad), h: handTop - 8 - top };
  } else {
    panel = { x: insets.left + pad, y: handTop - panelH - 4, w: W - insets.left - insets.right - 2 * pad, h: panelH };
    strip = { x: insets.left + pad, y: panel.y - 48, w: panel.w, h: 42 };
    window = { x: insets.left + pad, y: top, w: W - insets.left - insets.right - 2 * pad, h: strip.y - 8 - top };
  }

  // The others around the window, from my left over the top to my right; or, where the window is
  // too short for that, in a row along its top. Cats shrink before anything overlaps.
  const placed = placeSeats(input.others, window, avatar0, cw, ch, column);
  const { seats, seatRects, angles, avatar } = placed;
  // The sill is as big as a trick needs, centred in the room the cats leave: the window shows round it.
  const room = placed.sill;
  const sw = Math.min(room.w, cw * 3.8);
  const sh = Math.min(room.h, ch * 2.4);
  const sill = { x: room.x + (room.w - sw) / 2, y: room.y + (room.h - sh) / 2, w: sw, h: sh };
  const sillScale = clamp(Math.min(sill.h / (ch * 1.95), sill.w / (cw * 2.3)), 0.42, 0.9);
  const slotSeats = [...input.others.map((seat, i) => ({ seat, angle: angles[i] ?? 90 })), ...(input.me !== null ? [{ seat: input.me, angle: 270 }] : [])];
  const slots = slotsFor(sill, slotSeats, cw, ch, sillScale);
  const badge = Math.round(clamp(Math.min(sill.w, sill.h) * 0.3, 40, 64));
  const trump = { x: sill.x + 4, y: sill.y + 4, w: badge, h: badge };
  const banner = { x: panel.x, y: panel.y, w: panel.w, h: 40 };

  return {
    landscape,
    cw,
    ch,
    avatar,
    seats,
    seatRects,
    window,
    sill,
    slots,
    sillScale,
    trump,
    strip,
    stripColumn: column,
    panel,
    hand,
    handRect,
    banner,
    bannerRoom: banner,
    menu: { x: W - insets.right - 52, y: insets.top, w: 52, h: 52 },
    centre: { x: sill.x + sill.w / 2, y: sill.y + sill.h / 2 },
  };
}

/** The Cards view: just this player's things, big. The strip along the top, then the panel, then the hand. */
function cardsOn(input: BwInput): BwLayout {
  const { width: W, height: H, insets } = input;
  const landscape = W > H * 1.15;
  const pad = 12;
  const usable = H - insets.top - insets.bottom;
  const handMax = Math.min(W - insets.left - insets.right - 2 * pad, 1280);
  const cw = cardFor(input.hand, handMax, Math.round(clamp(Math.min(W / 4.8, usable / (landscape ? 3.4 : 4.6)), 56, 150)));
  const ch = Math.round(cw * 1.4);
  const handBase = H - insets.bottom - 10;
  const { poses: hand } = handPoses(input.hand, W / 2, handBase, cw, ch, handMax);
  const handTop = Math.min(handBase - ch, ...hand.map((p) => p.y)) - ch * 0.2 - 6;
  const top = insets.top + 8;
  // Beside the Cards/Table switch and the paw, which sit along the top.
  const strip = { x: insets.left + pad, y: top + 52, w: W - insets.left - insets.right - 2 * pad, h: 44 };
  const panelH = Math.round(clamp(usable * 0.24, 110, 220));
  const panel = { x: strip.x, y: Math.max(strip.y + strip.h + 10, handTop - panelH - 8), w: strip.w, h: panelH };
  const badge = 56;
  const trump = { x: strip.x, y: strip.y + strip.h + 10, w: badge, h: badge };
  const empty = { x: W / 2, y: panel.y, w: 0, h: 0 };
  return {
    landscape,
    cw,
    ch,
    avatar: 0,
    seats: new Map(),
    seatRects: new Map(),
    window: empty,
    sill: empty,
    slots: new Map(),
    sillScale: 0.6,
    trump,
    strip,
    stripColumn: false,
    panel,
    hand,
    handRect: { x: (W - handMax) / 2, y: handTop, w: handMax, h: handBase - handTop + 4 },
    banner: { x: panel.x, y: panel.y, w: panel.w, h: 40 },
    bannerRoom: { x: panel.x, y: panel.y, w: panel.w, h: 40 },
    menu: { x: W - insets.right - 52, y: insets.top, w: 52, h: 52 },
    centre: { x: W / 2, y: panel.y + panel.h / 2 },
  };
}

/** Moves a whole layout `dx` to the right. */
function shift(L: BwLayout, dx: number): BwLayout {
  const p = <T extends { x: number }>(v: T): T => ({ ...v, x: v.x + dx });
  return {
    ...L,
    seats: new Map([...L.seats].map(([k, v]) => [k, p(v)])),
    seatRects: new Map([...L.seatRects].map(([k, v]) => [k, p(v)])),
    window: p(L.window),
    sill: p(L.sill),
    slots: new Map([...L.slots].map(([k, v]) => [k, p(v)])),
    trump: p(L.trump),
    strip: p(L.strip),
    panel: p(L.panel),
    hand: L.hand.map(p),
    handRect: p(L.handRect),
    banner: p(L.banner),
    bannerRoom: p(L.bannerRoom),
    menu: p(L.menu),
    centre: p(L.centre),
  };
}

/**
 * The TV, planned at 1920 x 1080 like the other games' TV tables: the score strip across the top,
 * every seat around the window with seat 0 at the bottom, the trick on the sill in the middle, the
 * turn banner along the bottom and the menu in its corner.
 */
function tvBird(input: BwInput): BwLayout {
  const { edge, gap, avatar, seatW, banner: bannerSize } = TV;
  const seatsAll = input.others;
  const n = Math.max(seatsAll.length, 1);
  const stripH = 84;
  const strip = { x: edge + TV.menu + gap, y: edge, w: TV_W - 2 * (edge + TV.menu + gap), h: stripH };
  const banner = { x: TV_W / 2 - bannerSize.w / 2, y: TV_H - edge - bannerSize.h, w: bannerSize.w, h: bannerSize.h };
  const window = { x: edge, y: edge + stripH + gap, w: TV_W - 2 * edge, h: banner.y - gap - (edge + stripH + gap) };
  const seatH = avatar + 76;
  const c = { x: window.x + window.w / 2, y: window.y + window.h / 2 };
  const rx = window.w / 2 - seatW / 2;
  const ry = window.h / 2 - seatH / 2;
  const angles = tvAngles(n);
  const { centres, rects } = ring(seatsAll, angles, c, rx, ry, avatar, seatW, seatH);
  const sill = { x: c.x - rx * 0.56, y: c.y - ry * 0.42, w: rx * 1.12, h: ry * 0.84 };
  const cw = 168;
  const ch = Math.round(cw * 1.4);
  const sillScale = clamp(Math.min(sill.h / (ch * 1.9), sill.w / (cw * 2.4)), 0.5, 1);
  const slots = slotsFor(sill, seatsAll.map((seat, i) => ({ seat, angle: angles[i] ?? 270 })), cw, ch, sillScale);
  const trump = { x: sill.x + 8, y: sill.y + 8, w: 112, h: 112 };

  const { unit: u, at, box } = tvMap(input.width, input.height, input.insets);
  return {
    landscape: true,
    cw: Math.round(cw * u),
    ch: Math.round(ch * u),
    avatar: Math.round(avatar * u),
    seats: new Map([...centres].map(([k, v]) => [k, at(v)])),
    seatRects: new Map([...rects].map(([k, v]) => [k, box(v)])),
    window: box(window),
    sill: box(sill),
    slots: new Map([...slots].map(([k, v]) => [k, at(v)])),
    sillScale,
    trump: box(trump),
    strip: box(strip),
    stripColumn: false,
    panel: box({ x: banner.x, y: banner.y, w: 0, h: 0 }),
    hand: [],
    handRect: box({ x: banner.x, y: banner.y, w: 0, h: 0 }),
    banner: box(banner),
    bannerRoom: box(bannerRoomOf(banner)),
    menu: box(TV_MENU),
    centre: at(c),
  };
}
