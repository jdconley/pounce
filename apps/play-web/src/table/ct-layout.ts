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
  /** Laid groups: each seat's row, and each group's card poses and drop rectangle. */
  laid: Map<number, { avatar: { x: number; y: number; size: number }; groups: { poses: Pose[]; rect: Rect }[] }>;
  /** Where the action button sits (Lay down). */
  action: { x: number; y: number };
  /** The centre of the table, for effects. */
  centre: { x: number; y: number };
};

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

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
    laid: new Map([...L.laid].map(([k, v]) => [k, { avatar: p(v.avatar), groups: v.groups.map((g) => ({ poses: g.poses.map(p), rect: p(g.rect) })) }])),
    action: p(L.action),
    centre: p(L.centre),
  };
}

/**
 * The table on a wide screen is a stage no wider than it needs to be, centred, with the room
 * on either side: a monitor gets a table, not a stretched one.
 */
export function ctLayout(input: CtInput): CtLayout {
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
  // Card height from the height there is: the piles and the hand (a card each), the trays, and
  // in portrait up to two rows of laid groups (more rows squeeze themselves).
  const rows = landscape ? 0 : Math.min(input.laid.length, 2);
  const share = 2 + (input.trays > 0 ? small + 0.2 : 0) + rows * (small + 0.1);
  const fromHeight = (usable - 8 - bandH - 76) / share / 1.406;
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
  const bottomOfCentre = input.trays > 0 ? trayTop - 10 : handRect.y - 8;

  // The tower down the left.
  const tower = { x: towerLeft, y: bandTop + bandH + 4, w: towerW, h: Math.max(bottomOfCentre - (bandTop + bandH + 4), 120) };

  // The centre: in portrait the laid groups sit above the piles; sideways, beside them.
  const centreLeft = towerLeft + towerW + (landscape ? pad : 6);
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
  const laid = new Map<number, { avatar: { x: number; y: number; size: number }; groups: { poses: Pose[]; rect: Rect }[] }>();
  const mini = Math.round(lh * 0.62);
  const colW = laidW / cols;
  input.laid.forEach((row, i) => {
    const col = i % cols;
    const rowY = centreTop + Math.floor(i / cols) * rowH;
    const x0 = laidLeft + col * colW;
    const total = row.groups.reduce((sum, c) => sum + Math.max(c, 1), 0);
    const step = Math.max(6, Math.min(lw * 0.46, (colW - mini - 20 - row.groups.length * (lw * 0.54 + 10)) / Math.max(total, 1)));
    let x = x0 + mini + 10;
    const groups = row.groups.map((count) => {
      const poses = overlap(count, x, rowY, cw, ch, laidScale, step);
      const w = lw + step * Math.max(count - 1, 0);
      const rect = { x: x - 4, y: rowY - 4, w: w + 8, h: lh + 8 };
      x += w + 10;
      return { poses, rect };
    });
    laid.set(row.seat, { avatar: { x: x0 + mini / 2, y: rowY + lh / 2, size: mini }, groups });
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
    laid,
    action,
    centre: { x: cx, y: cy },
  };
}

/** Poses for `n` small cards in a tray. */
export function trayPoses(tray: Rect, n: number, size: number, cw: number, ch: number, small: number): Pose[] {
  const sw = cw * small;
  const sh = ch * small;
  const inner = tray.w - 20;
  const step = n <= 1 ? 0 : Math.min(sw * 0.62, (inner - sw) / Math.max(n - 1, size - 1, 1));
  const width = sw + step * Math.max(n - 1, 0);
  const x = tray.x + Math.max(10, (tray.w - width) / 2);
  const y = tray.y + (tray.h - sh) / 2;
  return overlap(n, x, y, cw, ch, small, step);
}
