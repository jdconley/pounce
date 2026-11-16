/**
 * Where everything sits on a Tuna Tiles table: opponents across the top, the table's sets
 * flowing in rows inside the rope, the toy box, the controls and the rack. Pure geometry, like
 * ct-layout.ts.
 */
import { TV, TV_H, TV_W, tvMap, type Insets } from "./ct-layout";

import type { Rect } from "./drag";
import type { Pose } from "./motion";

export type TilesInput = {
  width: number;
  height: number;
  insets: Insets;
  opponents: number[];
  sets: number[];
  rack: number;
  /** A TV across the room: every seat in `opponents`, no rack, sized for the couch. */
  tv?: boolean;
};

export type TilesLayout = {
  landscape: boolean;
  pw: number;
  ph: number;
  avatar: number;
  opponents: Map<number, { x: number; y: number }>;
  board: Rect;
  pool: { x: number; y: number; size: number };
  sets: { rect: Rect; poses: Pose[] }[];
  newSet: Rect;
  controls: { y: number; h: number };
  rack: Pose[];
  rackRect: Rect;
  /** Where "<Name>'s turn" sits. */
  banner: Rect;
  /** Each seat in `opponents`: its cat, and on a TV its name and score under it. */
  seats: Map<number, Rect>;
};

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

/** Lays sets out in rows inside `area` with pieces `pw` wide: the poses, or null if they don't fit. */
function flow(sets: number[], area: Rect, pw: number, ph: number) {
  const gap = pw * 0.4;
  const rowGap = ph * 0.32;
  const step = pw * 1.02;
  let x = area.x;
  let y = area.y;
  const out: { rect: Rect; poses: Pose[] }[] = [];
  for (const n of sets) {
    const w = step * n - (step - pw);
    if (x > area.x && x + w > area.x + area.w) {
      x = area.x;
      y += ph + rowGap;
    }
    // A set longer than a whole row wraps inside itself.
    const perRow = Math.max(1, Math.floor((area.w + (step - pw)) / step));
    const poses: Pose[] = [];
    for (let i = 0; i < n; i++) {
      const row = Math.floor(i / perRow);
      const col = i % perRow;
      poses.push({ x: (n > perRow ? area.x : x) + col * step, y: y + row * (ph + 4), r: 0, s: 1, z: 10 + i });
    }
    const rows = Math.ceil(n / perRow);
    const rect = { x: n > perRow ? area.x : x, y, w: n > perRow ? area.w : w, h: rows * ph + (rows - 1) * 4 };
    out.push({ rect, poses });
    if (n > perRow) {
      x = area.x;
      y += rect.h + rowGap;
    } else x += w + gap;
  }
  const newSet = { x: x + (x > area.x ? 0 : 0), y, w: pw * 1.9, h: ph };
  if (newSet.x + newSet.w > area.x + area.w) {
    newSet.x = area.x;
    newSet.y = y + ph + rowGap;
  }
  const fits = newSet.y + newSet.h <= area.y + area.h;
  return { sets: out, newSet, fits };
}

export function tilesLayout(input: TilesInput): TilesLayout {
  if (input.tv) return tvTiles(input);
  const { width: W, height: H, insets } = input;
  const landscape = W > H * 1.15;
  const pad = 10;
  const avatar = Math.round(clamp(Math.min(W / 7, H / 10), 46, 84));
  const bandTop = insets.top + 8;
  const bandH = avatar + 30;
  const opponents = new Map<number, { x: number; y: number }>();
  const across = W - insets.left - insets.right - 2 * pad;
  input.opponents.forEach((seat, i) => {
    opponents.set(seat, { x: insets.left + pad + (across * (i + 0.5)) / Math.max(input.opponents.length, 1), y: bandTop + avatar / 2 });
  });

  // Rack pieces are drawn a little bigger than the table's, as big as the rack's share of the
  // height allows: more to a row when the screen is wide, smaller when it is short.
  const usable = H - insets.top - insets.bottom;
  const rackBudget = usable * (landscape ? 0.3 : 0.27);
  const rackWidth = Math.min(W - insets.left - insets.right - 2 * pad, 1100);
  let rackPw = Math.round(clamp(Math.min(rackWidth / 9.4, 76), 24, 76));
  const rowsAt = (size: number) => Math.max(1, Math.ceil(input.rack / Math.max(1, Math.floor(rackWidth / (size * 1.04)))));
  while (rackPw > 24 && rowsAt(rackPw) * (rackPw * 1.2 + 6) + 10 > rackBudget) rackPw -= 2;
  const rackRows = rowsAt(rackPw);
  // Even rows: 20 pieces over two rows of ten, not eighteen and two.
  const perRow = Math.ceil(input.rack / rackRows);
  const rh = Math.round(rackPw * 1.2);
  const rackH = rackRows * (rh + 6) + 10;
  const rackTop = H - insets.bottom - 8 - rackH;
  const rack: Pose[] = [];
  for (let i = 0; i < input.rack; i++) {
    const row = Math.floor(i / perRow);
    const inRow = Math.min(perRow, input.rack - row * perRow);
    const step = rackPw * 1.04;
    const left = W / 2 - (step * inRow - (step - rackPw)) / 2;
    rack.push({ x: left + (i % perRow) * step, y: rackTop + 6 + row * (rh + 6), r: 0, s: 1, z: 200 + i });
  }
  const rackRect = { x: insets.left + pad, y: rackTop - 6, w: W - insets.left - insets.right - 2 * pad, h: rackH + 12 };

  const controlsH = landscape && usable < 500 ? 52 : 64;
  const controlsY = rackTop - controlsH - 4;
  const board = { x: insets.left + pad, y: bandTop + bandH + 4, w: W - insets.left - insets.right - 2 * pad, h: controlsY - (bandTop + bandH + 4) - 6 };
  const inner = { x: board.x + 18, y: board.y + 18, w: board.w - 36 - 54, h: board.h - 36 };

  // The biggest table pieces that let every set and the new-set spot fit.
  let pw = Math.round(clamp(Math.min(inner.w / 8.6, inner.h / 5.5), 26, 64));
  let laid = flow(input.sets, inner, pw, Math.round(pw * 1.2));
  while (!laid.fits && pw > 20) {
    pw -= 2;
    laid = flow(input.sets, inner, pw, Math.round(pw * 1.2));
  }
  const ph = Math.round(pw * 1.2);
  const poolSize = Math.round(clamp(pw * 1.3, 40, 72));
  return {
    landscape,
    pw,
    ph,
    avatar,
    opponents,
    board,
    pool: { x: board.x + board.w - poolSize - 10, y: board.y + 12, size: poolSize },
    sets: laid.sets,
    newSet: laid.newSet,
    controls: { y: controlsY, h: controlsH },
    // Rack pieces are table pieces scaled up about their centre: shift so they sit where planned.
    rack: rack.map((p) => ({ ...p, x: p.x - (pw - rackPw) / 2, y: p.y - (ph - rh) / 2, s: rackPw / pw })),
    rackRect,
    // The cue the phone table draws today, at the foot of the board.
    banner: { x: W / 2 - 160, y: board.y + board.h - 40, w: 320, h: 30 },
    seats: new Map([...opponents].map(([k, at]) => [k, { x: at.x - avatar / 2, y: at.y - avatar / 2, w: avatar, h: avatar }])),
  };
}

/** The bottom of the lowest set `flow` placed. */
const bottomOf = (sets: { rect: Rect }[], top: number) => sets.reduce((b, s) => Math.max(b, s.rect.y + s.rect.h), top);

/**
 * The Tuna Tiles table on a TV, planned at 1920 x 1080 like Cat Tower's: the seats across the
 * top, the board filling the rest with pieces as big as it allows, and along the bottom the turn
 * banner and the toy box.
 */
function tvTiles(input: TilesInput): TilesLayout {
  const { edge, gap, avatar, seatW, seatH, banner: bannerSize } = TV;
  const n = Math.max(input.opponents.length, 1);
  const slot = (TV_W - 2 * edge) / n;
  const w = Math.min(seatW, slot - gap);
  const opponents = new Map<number, { x: number; y: number }>();
  const seats = new Map<number, Rect>();
  input.opponents.forEach((s, i) => {
    const x = edge + slot * (i + 0.5);
    seats.set(s, { x: x - w / 2, y: edge, w, h: seatH });
    opponents.set(s, { x, y: edge + avatar / 2 });
  });

  const stripH = bannerSize.h + 16;
  const stripY = TV_H - edge - stripH;
  const banner = { x: TV_W / 2 - bannerSize.w / 2, y: stripY + (stripH - bannerSize.h) / 2, w: bannerSize.w, h: bannerSize.h };
  const board = { x: edge, y: edge + seatH + gap, w: TV_W - 2 * edge, h: stripY - gap - (edge + seatH + gap) };
  const inner = { x: board.x + gap, y: board.y + gap, w: board.w - 2 * gap, h: board.h - 2 * gap };

  // The biggest pieces with which every set fits; no new-set spot, nobody drops on a TV.
  let pw = 128;
  let laid = flow(input.sets, inner, pw, Math.round(pw * 1.2));
  while (bottomOf(laid.sets, inner.y) > inner.y + inner.h && pw > 20) {
    pw -= 2;
    laid = flow(input.sets, inner, pw, Math.round(pw * 1.2));
  }
  const ph = Math.round(pw * 1.2);
  // The sets centred across the board, not hugging its left edge.
  const right = laid.sets.reduce((r, s) => Math.max(r, s.rect.x + s.rect.w), inner.x);
  const dx = (inner.x + inner.w - right) / 2;
  const sets = laid.sets.map((s) => ({ rect: { ...s.rect, x: s.rect.x + dx }, poses: s.poses.map((p) => ({ ...p, x: p.x + dx })) }));

  const { unit: u, at, box } = tvMap(input.width, input.height, input.insets);
  return {
    landscape: true,
    pw: Math.round(pw * u),
    ph: Math.round(ph * u),
    avatar: Math.round(avatar * u),
    opponents: new Map([...opponents].map(([k, v]) => [k, at(v)])),
    board: box(board),
    pool: { ...at({ x: board.x + board.w - stripH, y: stripY }), size: stripH * u },
    sets: sets.map((s) => ({ rect: box(s.rect), poses: s.poses.map(at) })),
    newSet: box({ x: inner.x, y: inner.y, w: 0, h: 0 }),
    controls: { y: at({ x: 0, y: board.y + board.h }).y, h: 0 },
    rack: [],
    rackRect: box({ x: board.x, y: board.y + board.h, w: 0, h: 0 }),
    banner: box(banner),
    seats: new Map([...seats].map(([k, v]) => [k, box(v)])),
  };
}
