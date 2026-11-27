/**
 * Where everything sits on a Cat Tower table, for any screen: a phone held either way, a tablet,
 * a laptop, a wide monitor. Pure geometry from the table's size and what is on it, so it is
 * tested without a browser and computed once per change, never per frame.
 */
import type { Rect } from "./drag";
import type { Pose } from "./motion";

export type Insets = { top: number; right: number; bottom: number; left: number };

export type CtInput = {
  width: number;
  height: number;
  insets: Insets;
  /** Seats shown across the top (everyone but the hand on show), in seat order. */
  opponents: number[];
  /** Cards in the hand on show (not in a tray). */
  handCount: number;
  /** Trays to draw (the phase's groups while not laid down): 0 hides them. */
  trays: number;
  /** For each seat with groups laid down: how many cards in each group. */
  laid: { seat: number; groups: number[] }[];
  /** A TV across the room: every seat in `opponents`, no hand or trays, sized for the couch. */
  tv?: boolean;
  /** The reader's text size against the default (the root font over 16 px): 1.625 at the largest. */
  text?: number;
};

/** A laid row's owner: their cat, and their name tag under it, in a column of its own at the row's left. */
export type LaidOwner = {
  /** The cat's circle (its centre and size); size 0 when the row has no room for one. */
  avatar: { x: number; y: number; size: number };
  /** The name tag's box: it is drawn this tall, and no wider (a long name ends in an ellipsis). Zero on a TV, whose seats carry the names. */
  tag: Rect;
  /** The name tag's font size, in px. */
  font: number;
};

export type CtLayout = {
  landscape: boolean;
  /** A card's size at scale 1. */
  cw: number;
  ch: number;
  /** Scale for cards in trays and laid groups. */
  small: number;
  avatar: number;
  opponents: Map<number, { x: number; y: number }>;
  tower: Rect;
  rug: Rect;
  deck: Pose;
  discard: Pose;
  deckRect: Rect;
  discardRect: Rect;
  hand: Pose[];
  handRect: Rect;
  trays: Rect[];
  /** Each tray's count ("2/3"): its font, and the room kept for it at the tray's left, clear of the tray's cards. */
  trayLabel: TrayLabel;
  /** Laid groups: each seat's row (its owner, and each group's card poses and drop rectangle). */
  laid: Map<number, LaidOwner & { groups: { poses: Pose[]; rect: Rect }[] }>;
  /** Where the action button sits (Lay down). */
  action: { x: number; y: number };
  /** The centre of the table, for effects. */
  centre: { x: number; y: number };
  /** TV only: where "<Name>'s turn" sits. On a phone, a placeholder where today's cue is. */
  banner: Rect;
  /** TV only: each seat in `opponents`, its cat with its name and score under it. On a phone, a placeholder: each cat's circle. */
  seats: Map<number, Rect>;
  /** TV only: as wide as the banner may grow for a long name, centred on it. On a phone, the banner. */
  bannerRoom: Rect;
  /** TV only: the menu's button, in a corner every TV screen keeps free. On a phone, nothing (zero size). */
  menu: Rect;
};

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

/**
 * How far past its width a tower `w` wide reaches: its shelves' numbers (`.tower .shelf i`, 10 px
 * out and a border) and a pickled cat's cucumber (a quarter of a tower and a bit).
 */
export const towerReach = (w: number) => Math.max(12, Math.ceil(w * 0.28));

/** A tray's count: its font, and the width kept for it at the tray's left. */
export type TrayLabel = { font: number; w: number };

/**
 * The room a tray's count needs: "9/9" in the label's font, which follows the reader's text size
 * (`text`) and a controller's `unit`, never taller than the tray allows. Digits in the rounded black
 * face are about 0.66 em, the slash 0.42, the outline 0.15.
 */
export function trayLabelOf(trayH: number, width: number, text = 1, unit = 1, size = 9): TrayLabel {
  const font = Math.round(Math.min(clamp(width * 0.036, 13.6 * text, 16.8 * text) * unit, trayH * 0.42));
  const digits = 2 * String(size).length;
  return { font, w: Math.ceil(font * (0.66 * digits + 0.42 + 0.15)) };
}

/** The pad inside a tray's rim, and the gap between its count and its cards. */
const TRAY_PAD = 10;
const LABEL_GAP = 6;

/** Poses for `n` cards fanned in a hand `width` wide, bottoms on `baseY`. */
export function fan(n: number, centreX: number, baseY: number, cw: number, ch: number, maxWidth: number): Pose[] {
  if (n === 0) return [];
  const step = n === 1 ? 0 : Math.min(cw * 0.78, (maxWidth - cw) / (n - 1));
  const width = cw + step * (n - 1);
  const left = centreX - width / 2;
  const mid = (n - 1) / 2;
  const tilt = Math.min(3.2, 34 / Math.max(n, 1));
  const drop = (d: number) => d * d * (ch * 0.006) + Math.abs(d) * ch * 0.01;
  // The outermost cards sit lowest: lift the whole fan so they stay on screen.
  const lowest = drop(mid) + Math.sin((mid * tilt * Math.PI) / 180) * cw * 0.5;
  return Array.from({ length: n }, (_, i) => {
    const d = i - mid;
    return {
      x: left + i * step,
      y: baseY - ch - lowest + drop(d),
      r: d * tilt,
      s: 1,
      z: 100 + i,
    };
  });
}

/** Poses for a group of `n` small cards overlapped from `x`, top at `y`. */
export function overlap(n: number, x: number, y: number, cw: number, ch: number, scale: number, step: number): Pose[] {
  // A scaled element shrinks about its centre: shift so its visual top-left is (x, y).
  const dx = (cw * (1 - scale)) / 2;
  const dy = (ch * (1 - scale)) / 2;
  return Array.from({ length: n }, (_, i) => ({ x: x + i * step - dx, y: y - dy, r: 0, s: scale, z: 10 + i }));
}

/** Moves a whole layout `dx` to the right. */
function shift(L: CtLayout, dx: number): CtLayout {
  const p = <T extends { x: number }>(v: T): T => ({ ...v, x: v.x + dx });
  return {
    ...L,
    opponents: new Map([...L.opponents].map(([k, v]) => [k, p(v)])),
    tower: p(L.tower),
    rug: p(L.rug),
    deck: p(L.deck),
    discard: p(L.discard),
    deckRect: p(L.deckRect),
    discardRect: p(L.discardRect),
    hand: L.hand.map(p),
    handRect: p(L.handRect),
    trays: L.trays.map(p),
    laid: new Map([...L.laid].map(([k, v]) => [k, { ...v, avatar: p(v.avatar), tag: p(v.tag), groups: v.groups.map((g) => ({ poses: g.poses.map(p), rect: p(g.rect) })) }])),
    action: p(L.action),
    centre: p(L.centre),
    banner: p(L.banner),
    seats: new Map([...L.seats].map(([k, v]) => [k, p(v)])),
    bannerRoom: p(L.bannerRoom),
    menu: p(L.menu),
  };
}

/**
 * The table on a wide screen is a stage no wider than it needs to be, centred, with the room
 * on either side: a monitor gets a table, not a stretched one.
 */
export function ctLayout(input: CtInput): CtLayout {
  if (input.tv) return onTv(tvLayoutOn(input), input);
  const stage = Math.min(input.width, Math.max(input.height * 1.75, 360), 1500);
  if (stage >= input.width - 1) return layoutOn(input);
  const dx = (input.width - stage) / 2;
  return shift(layoutOn({ ...input, width: stage, insets: { ...input.insets, left: 0, right: 0 } }), dx);
}

function layoutOn(input: CtInput): CtLayout {
  const { width: W, height: H, insets } = input;
  const landscape = W > H * 1.15;
  const usable = H - insets.top - insets.bottom;
  const avatar = Math.round(landscape ? clamp(usable / 8.5, 40, 84) : clamp(Math.min(W / 7.5, usable / 10), 46, 92));
  const bandH = avatar + 30;
  const small = landscape ? 0.6 : 0.56;
  // Card height from the height there is: the piles and the hand (a card each), the trays, the
  // cue's line, and in portrait up to two rows of laid groups (more rows squeeze themselves).
  const rows = landscape ? 0 : Math.min(input.laid.length, 2);
  const share = 2 + (input.trays > 0 ? small + 0.2 : 0) + rows * (small + 0.1);
  const fromHeight = (usable - 8 - bandH - 76 - 30) / share / 1.406;
  const cw = Math.round(clamp(Math.min(W / (landscape ? 12.5 : 7.4), fromHeight), 40, 108));
  const ch = Math.round(cw * 1.406);
  const sw = cw * small;
  const sh = ch * small;
  const pad = 10;

  // Opponents across the top.
  const bandTop = insets.top + 8;
  const opponents = new Map<number, { x: number; y: number }>();
  const n = input.opponents.length;
  const across = W - insets.left - insets.right - 2 * pad;
  input.opponents.forEach((seat, i) => {
    const x = insets.left + pad + (across * (i + 0.5)) / Math.max(n, 1);
    opponents.set(seat, { x, y: bandTop + avatar / 2 });
  });

  // The hand at the bottom.
  const handBase = H - insets.bottom - 10;
  const towerW = Math.round(clamp(cw * 0.62, 34, 64));
  const towerLeft = insets.left + 6;
  const handMax = Math.min(W - insets.left - insets.right - 2 * pad - (landscape ? 0 : 0), cw * 13);
  const hand = fan(input.handCount, W / 2, handBase, cw, ch, handMax);
  const handRect = { x: (W - handMax) / 2, y: handBase - ch - 18, w: handMax, h: ch + 28 };

  // The trays above the hand.
  const trayH = Math.round(sh + 22);
  const trayTop = handRect.y - trayH - 10;
  const trays: Rect[] = [];
  if (input.trays > 0) {
    const room = Math.min(W - insets.left - insets.right - 2 * pad - (landscape ? 0 : towerW + 12) - 8, cw * 9);
    const gap = 12;
    const each = Math.min((room - gap * (input.trays - 1)) / input.trays, cw * 4.4);
    const used = each * input.trays + gap * (input.trays - 1);
    const left = (W - used) / 2 + (landscape ? 0 : (towerW + 12) / 2);
    for (let i = 0; i < input.trays; i++) trays.push({ x: left + i * (each + gap), y: trayTop, w: each, h: trayH });
  }
  const trayLabel = trayLabelOf(trayH, W, input.text);
  // The cue's line, over the trays (or the hand): the centre and the tower end above it.
  const cueY = (input.trays > 0 ? trayTop : handRect.y) - 34;
  const bottomOfCentre = cueY - 6;

  // The tower down the left.
  const tower = { x: towerLeft, y: bandTop + bandH + 4, w: towerW, h: Math.max(bottomOfCentre - (bandTop + bandH + 4), 120) };

  // The centre: in portrait the laid groups sit above the piles; sideways, beside them. It starts
  // past the tower's shelf numbers, which hang off its right edge.
  const centreLeft = towerLeft + towerW + towerReach(towerW) + (landscape ? pad : 4);
  const centreRight = W - insets.right - pad;
  const centreTop = bandTop + bandH + 6;
  const gap = cw * 0.22;
  const cx = landscape ? Math.max(centreLeft + cw + gap / 2 + 16, centreLeft + (centreRight - centreLeft) * 0.3) : centreLeft + (centreRight - centreLeft) / 2;
  const laidLeft = landscape ? cx + cw + gap / 2 + 24 : centreLeft;
  const laidW = centreRight - laidLeft;
  const laidSpace = landscape ? bottomOfCentre - centreTop : Math.max(bottomOfCentre - centreTop - ch - 8, sh + 10);
  const cols = landscape && input.laid.length > 3 && laidW > sw * 12 ? 2 : 1;
  const rowCount = Math.ceil(input.laid.length / cols);
  const rowH = rowCount > 0 ? Math.min(sh + 10, laidSpace / rowCount) : sh + 10;
  // Rows squeezed below a card's height draw their cards smaller.
  const laidScale = Math.min(small, ((rowH - 10) / ch) * 1.0);
  const lw = cw * laidScale;
  const lh = ch * laidScale;
  const laid: CtLayout["laid"] = new Map();
  const colW = laidW / cols;
  // Each row's owner has a column of its own at the row's left, as tall as the row's groups: their
  // cat, and their name tag under it (over the cat's foot, as a seat's is). The tag follows the
  // reader's text size as far as the row allows; a long name ends in an ellipsis.
  const text = input.text ?? 1;
  const band = lh + 6;
  const tagFont = Math.max(10, Math.round(Math.min(clamp(W * 0.028, 11 * text, 13 * text), band * 0.42)));
  const tagH = Math.round(tagFont * 1.2 + 9);
  const ownerW = Math.round(Math.min(Math.max(tagFont * 7.5, 60), Math.max(colW * 0.3, 60), 130));
  const catSize = Math.round(Math.min(lh * 0.62, band - tagH + 8));
  const cat = catSize >= 16 ? catSize : 0;
  const stack = (cat ? cat - 8 : 0) + tagH;
  input.laid.forEach((row, i) => {
    const col = i % cols;
    const rowY = centreTop + Math.floor(i / cols) * rowH;
    const x0 = laidLeft + col * colW;
    const top = rowY + lh / 2 - stack / 2;
    const tag = { x: x0, y: top + stack - tagH, w: ownerW, h: tagH };
    const avatar = { x: x0 + ownerW / 2, y: top + cat / 2, size: cat };
    const total = row.groups.reduce((sum, c) => sum + Math.max(c, 1), 0);
    const step = Math.max(6, Math.min(lw * 0.46, (colW - ownerW - 20 - row.groups.length * (lw * 0.54 + 10)) / Math.max(total, 1)));
    let x = x0 + ownerW + 10;
    const groups = row.groups.map((count) => {
      const poses = overlap(count, x, rowY, cw, ch, laidScale, step);
      const w = lw + step * Math.max(count - 1, 0);
      const rect = { x: x - 4, y: rowY - 4, w: w + 8, h: lh + 8 };
      x += w + 10;
      return { poses, rect };
    });
    laid.set(row.seat, { avatar, tag, font: tagFont, groups });
  });
  const laidBottom = landscape ? centreTop : centreTop + rowCount * rowH;

  // The piles in what is left of the centre.
  const pileTop = Math.max(laidBottom + 4, centreTop);
  const pileSpace = bottomOfCentre - pileTop;
  const cy = pileTop + Math.max(pileSpace, ch) / 2;
  const deck = { x: cx - cw - gap / 2, y: cy - ch / 2, r: 0, s: 1, z: 5 };
  const discard = { x: cx + gap / 2, y: cy - ch / 2, r: 0, s: 1, z: 6 };
  // The rug sits under the piles and never runs under the tower.
  const rugSize = Math.min(Math.max(pileSpace + ch * 0.6, ch * 2), (cw * 2 + gap) * 2.3, landscape ? usable : W, (cx - (towerLeft + towerW + 4)) * 2);
  const rug = { x: cx - rugSize / 2, y: cy - rugSize / 2, w: rugSize, h: rugSize };

  const lastTray = trays[trays.length - 1];
  const action = lastTray ? { x: W / 2 + (landscape ? 0 : (towerW + 12) / 2), y: trayTop - 4 } : { x: W / 2, y: handRect.y - 34 };

  return {
    landscape,
    cw,
    ch,
    small,
    avatar,
    opponents,
    tower,
    rug,
    deck,
    discard,
    deckRect: { x: deck.x, y: deck.y, w: cw, h: ch },
    discardRect: { x: discard.x, y: discard.y, w: cw, h: ch },
    hand,
    handRect,
    trays,
    trayLabel,
    laid,
    action,
    centre: { x: cx, y: cy },
    // The cue the phone table draws today, centred over the trays or the hand.
    banner: { x: W / 2 - 160, y: cueY, w: 320, h: 30 },
    seats: new Map([...opponents].map(([k, at]) => [k, { x: at.x - avatar / 2, y: at.y - avatar / 2, w: avatar, h: avatar }])),
    bannerRoom: { x: W / 2 - 160, y: cueY, w: 320, h: 30 },
    menu: { x: 0, y: 0, w: 0, h: 0 },
  };
}

/*
 * The TV: a table seen from the couch, about three metres away. Each layout is planned on a
 * 1920 x 1080 frame and drawn at `unit = min(width / 1920, height / 1080)`, centred, so a 4K TV
 * draws exactly twice a 1080p one and a 720p one two thirds of it.
 */
export const TV_W = 1920;
export const TV_H = 1080;
/** The most seats a TV table places: Cat Tower's six and Tuna Tiles' four (`maxSeats`). */
export const TV_SEATS = { catTower: 6, tiles: 4 } as const;

/** What both games' TV tables share, in 1080p pixels. */
export const TV = {
  edge: 24,
  gap: 24,
  avatar: 136,
  /** A seat is its cat with its name and score under it: at least room for a 20-character name... */
  seatW: 372,
  /** ...and wider where its place on the table has the room, for fewer cut-off names. */
  seatMaxW: 560,
  seatH: 136 + 96,
  banner: { w: 760, h: 88 },
  /** The widest the banner grows for a long name ("Great Aunt Josephine's turn"). */
  bannerMaxW: 1400,
  /** The menu's button, a square in the bottom-right corner. */
  menu: 88,
} as const;

/** The menu's button on the 1920 x 1080 plan: the bottom-right corner, kept free by every TV screen. */
export const TV_MENU: Rect = { x: TV_W - TV.edge - TV.menu, y: TV_H - TV.edge - TV.menu, w: TV.menu, h: TV.menu };

/** Where the menu's button sits on a screen of this size. */
export const tvMenu = (width: number, height: number, insets: Insets): Rect => tvMap(width, height, insets).box(TV_MENU);

/** The room a TV banner has to grow into, centred on it. */
export const bannerRoomOf = (banner: Rect): Rect => ({ x: banner.x + banner.w / 2 - TV.bannerMaxW / 2, y: banner.y, w: TV.bannerMaxW, h: banner.h });

/** Where the 1920 x 1080 plan lands on a screen: its scale and its top-left corner. */
export function tvFrame(width: number, height: number, insets: Insets): { unit: number; x: number; y: number } {
  const w = width - insets.left - insets.right;
  const h = height - insets.top - insets.bottom;
  const unit = Math.min(w / TV_W, h / TV_H);
  return { unit, x: insets.left + (w - TV_W * unit) / 2, y: insets.top + (h - TV_H * unit) / 2 };
}

/** Maps points and rectangles of the plan onto the screen. */
export function tvMap(width: number, height: number, insets: Insets) {
  const f = tvFrame(width, height, insets);
  const u = f.unit;
  return {
    unit: u,
    at: <T extends { x: number; y: number }>(v: T): T => ({ ...v, x: f.x + v.x * u, y: f.y + v.y * u }),
    box: (r: Rect): Rect => ({ x: f.x + r.x * u, y: f.y + r.y * u, w: r.w * u, h: r.h * u }),
  };
}

const TV_CARD = 128;
const TV_TOWER = 96;
const ROW_GAP = 12;
const GROUP_GAP = 16;
/** How much of a laid card shows under the next: as much as there is room for, never less than tight in the plan. */
const ROOMY = 0.5;
const TIGHT = 0.42;
/** The table every seat is planned for: three groups of ten, so laying down never moves anything. */
const PLAN = { groups: 3, cards: 10 };

type Align = { x: "start" | "centre" | "end"; y: "top" | "centre" };

/**
 * Rows of laid groups in `area`, cards `lw` wide: spread out if they fit, closer if that is what
 * fits, and smaller only if even that would not.
 */
function placeGroups(area: Rect, counts: number[], cw: number, ch: number, lw0: number, align: Align): { poses: Pose[]; rect: Rect }[] {
  for (let k = 0; ; k++) {
    const lw = lw0 - 2 * Math.floor(k / 2);
    const spread = k % 2 === 0 ? ROOMY : TIGHT;
    const lh = (ch * lw) / cw;
    const sized = counts.map((c) => {
      const count = Math.max(c, 1);
      const step = count === 1 ? 0 : Math.max(6, Math.min(lw * spread, (area.w - lw) / (count - 1)));
      return { count: c, step, w: lw + step * (count - 1) };
    });
    const rows: (typeof sized)[] = [];
    let used = Infinity;
    for (const g of sized) {
      if (used + GROUP_GAP + g.w > area.w) {
        rows.push([]);
        used = -GROUP_GAP;
      }
      rows[rows.length - 1]!.push(g);
      used += GROUP_GAP + g.w;
    }
    const h = rows.length * lh + Math.max(rows.length - 1, 0) * ROW_GAP;
    if (h > area.h + 0.01 && lw > 24) continue;
    const out: { poses: Pose[]; rect: Rect }[] = [];
    let y = area.y + (align.y === "centre" ? Math.max(area.h - h, 0) / 2 : 0);
    for (const row of rows) {
      const rowW = row.reduce((sum, g) => sum + g.w, 0) + GROUP_GAP * (row.length - 1);
      let x = align.x === "start" ? area.x : align.x === "end" ? area.x + area.w - rowW : area.x + (area.w - rowW) / 2;
      for (const g of row) {
        out.push({ poses: overlap(g.count, x, y, cw, ch, lw / cw, g.step), rect: { x: x - 4, y: y - 4, w: g.w + 8, h: lh + 8 } });
        x += g.w + GROUP_GAP;
      }
      y += lh + ROW_GAP;
    }
    return out;
  }
}

/**
 * The Cat Tower table on a TV, planned at 1920 x 1080. The tower down the left; seats across the
 * top, and from four players one more down each side; each seat's laid groups beside it, between
 * it and the piles; the piles in the middle; the turn banner along the bottom.
 */
function tvLayoutOn(input: CtInput): CtLayout {
  const { edge, gap, avatar, seatW, seatMaxW, seatH, banner: bannerSize } = TV;
  const n = input.opponents.length;
  // Planned for the game's six seats; refuse more rather than leave a player off the table.
  if (n > TV_SEATS.catTower) throw new RangeError(`A Cat Tower TV table seats ${TV_SEATS.catTower}, not ${n}`);
  const sides = n >= 4;
  const across = Math.max(sides ? n - 2 : n, 1);
  const cw = TV_CARD;
  const ch = Math.round(cw * 1.406);
  const pileGap = Math.round(cw * 0.22);
  const pileW = cw * 2 + pileGap;
  const tower = { x: edge, y: edge, w: TV_TOWER, h: TV_H - 2 * edge };
  const x0 = edge + TV_TOWER + gap;
  const x1 = TV_W - edge;
  const cx = (x0 + x1) / 2;
  const banner = { x: cx - bannerSize.w / 2, y: TV_H - edge - bannerSize.h, w: bannerSize.w, h: bannerSize.h };
  const midBottom = banner.y - gap;
  const cellW = (x1 - x0 - (across - 1) * gap) / across;
  const sideW = cx - pileW / 2 - gap - (x0 + seatW + GROUP_GAP);

  // The biggest laid cards with which the planned table fits: rows under the top seats, the piles
  // and the side seats' rows in what is left, above the banner.
  const rowsFor = (w: number, lw: number) => {
    const long = lw * (1 + (PLAN.cards - 1) * TIGHT);
    if (w < long) return Infinity;
    return Math.ceil(PLAN.groups / Math.max(1, Math.floor((w + GROUP_GAP) / (long + GROUP_GAP))));
  };
  const heightOf = (rows: number, lw: number) => rows * ((ch * lw) / cw) + (rows - 1) * ROW_GAP;
  let lw = 96;
  let topH = 0;
  let sideH = 0;
  for (; lw > 48; lw -= 2) {
    topH = heightOf(rowsFor(cellW, lw), lw);
    sideH = sides ? heightOf(rowsFor(sideW, lw), lw) : 0;
    const midH = midBottom - (edge + seatH + ROW_GAP + topH + gap);
    if (midH >= ch + 96 && midH >= Math.max(sideH, sides ? seatH : 0)) break;
  }
  const midTop = edge + seatH + ROW_GAP + topH + gap;
  const midH = midBottom - midTop;
  const cy = midTop + midH / 2;

  // Seats clockwise from the left side: the left, the top from the left, the right.
  const cells: { seat: Rect; area: Rect; align: Align }[] = [];
  if (sides) cells.push({ seat: { x: x0, y: cy - seatH / 2, w: seatW, h: seatH }, area: { x: x0 + seatW + GROUP_GAP, y: cy - sideH / 2, w: sideW, h: sideH }, align: { x: "start", y: "centre" } });
  for (let i = 0; i < across; i++) {
    const x = x0 + i * (cellW + gap);
    const w = Math.min(seatMaxW, cellW);
    cells.push({ seat: { x: x + (cellW - w) / 2, y: edge, w, h: seatH }, area: { x, y: edge + seatH + ROW_GAP, w: cellW, h: topH }, align: { x: "centre", y: "top" } });
  }
  if (sides) cells.push({ seat: { x: x1 - seatW, y: cy - seatH / 2, w: seatW, h: seatH }, area: { x: cx + pileW / 2 + gap, y: cy - sideH / 2, w: sideW, h: sideH }, align: { x: "end", y: "centre" } });

  const opponents = new Map<number, { x: number; y: number }>();
  const seats = new Map<number, Rect>();
  const cellOf = new Map<number, (typeof cells)[number]>();
  input.opponents.forEach((s, i) => {
    // One cell for every seat: the guard above keeps `n` within the plan.
    const cell = cells[i]!;
    cellOf.set(s, cell);
    seats.set(s, cell.seat);
    opponents.set(s, { x: cell.seat.x + cell.seat.w / 2, y: cell.seat.y + avatar / 2 });
  });
  const laid: CtLayout["laid"] = new Map();
  for (const row of input.laid) {
    // Groups of a seat that isn't playing (none on a TV, as `opponents` is everyone) aren't drawn.
    const cell = cellOf.get(row.seat);
    if (!cell) continue;
    laid.set(row.seat, { avatar: { ...opponents.get(row.seat)!, size: avatar }, tag: { x: 0, y: 0, w: 0, h: 0 }, font: 0, groups: placeGroups(cell.area, row.groups, cw, ch, lw, cell.align) });
  }

  const deck = { x: cx - cw - pileGap / 2, y: cy - ch / 2, r: 0, s: 1, z: 5 };
  const discard = { x: cx + pileGap / 2, y: cy - ch / 2, r: 0, s: 1, z: 6 };
  // The rug sits under the piles, clear of the side seats' groups and the banner.
  const rugSize = Math.min(Math.max(midH, pileW + 48), midH + gap, sides ? pileW + gap : pileW * 2);
  return {
    landscape: true,
    cw,
    ch,
    small: lw / cw,
    avatar,
    opponents,
    tower,
    rug: { x: cx - rugSize / 2, y: cy - rugSize / 2, w: rugSize, h: rugSize },
    deck,
    discard,
    deckRect: { x: deck.x, y: deck.y, w: cw, h: ch },
    discardRect: { x: discard.x, y: discard.y, w: cw, h: ch },
    hand: [],
    handRect: { x: cx, y: cy, w: 0, h: 0 },
    trays: [],
    trayLabel: { font: 0, w: 0 },
    laid,
    action: { x: cx, y: cy },
    centre: { x: cx, y: cy },
    banner,
    seats,
    bannerRoom: bannerRoomOf(banner),
    menu: TV_MENU,
  };
}

/** The 1920 x 1080 plan drawn on the screen it is for. */
function onTv(L: CtLayout, input: CtInput): CtLayout {
  const { unit: u, at, box } = tvMap(input.width, input.height, input.insets);
  return {
    ...L,
    cw: Math.round(L.cw * u),
    ch: Math.round(L.ch * u),
    avatar: Math.round(L.avatar * u),
    opponents: new Map([...L.opponents].map(([k, v]) => [k, at(v)])),
    tower: box(L.tower),
    rug: box(L.rug),
    deck: at(L.deck),
    discard: at(L.discard),
    deckRect: box(L.deckRect),
    discardRect: box(L.discardRect),
    handRect: box(L.handRect),
    laid: new Map([...L.laid].map(([k, v]) => [k, { ...v, avatar: { ...at(v.avatar), size: v.avatar.size * u }, tag: box(v.tag), groups: v.groups.map((g) => ({ poses: g.poses.map(at), rect: box(g.rect) })) }])),
    action: at(L.action),
    centre: at(L.centre),
    banner: box(L.banner),
    seats: new Map([...L.seats].map(([k, v]) => [k, box(v)])),
    bannerRoom: box(L.bannerRoom),
    menu: box(L.menu),
  };
}

/** Where a tray's count sits: at its left, inside the rim, as tall as the tray. */
export const trayLabelRect = (tray: Rect, label: TrayLabel): Rect => ({ x: tray.x + TRAY_PAD, y: tray.y, w: label.w, h: tray.h });

/**
 * Poses for `n` small cards in a tray, sized for `size`: fanned in what the tray has past its count
 * (`label`, kept clear at its left), centred there.
 */
export function trayPoses(tray: Rect, n: number, size: number, cw: number, ch: number, small: number, label: TrayLabel = { font: 0, w: 0 }): Pose[] {
  const sw = cw * small;
  const sh = ch * small;
  const left = tray.x + TRAY_PAD + (label.w > 0 ? label.w + LABEL_GAP : 0);
  const inner = tray.x + tray.w - TRAY_PAD - left;
  const step = n <= 1 ? 0 : Math.max(0, Math.min(sw * 0.62, (inner - sw) / Math.max(n - 1, size - 1, 1)));
  const width = sw + step * Math.max(n - 1, 0);
  const x = left + Math.max(0, (inner - width) / 2);
  const y = tray.y + (tray.h - sh) / 2;
  return overlap(n, x, y, cw, ch, small, step);
}
