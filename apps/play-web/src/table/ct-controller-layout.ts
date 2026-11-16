/**
 * Where everything sits on a phone that is a Cat Tower controller (the table is on a TV): the
 * Cards/Table switch, whose turn it is and the menu along the top, the two piles on your turn (or
 * the cat whose turn it is), the trays, the buttons, and the hand, big, along the bottom. Once laid
 * down, the list of places to hit opens over the bottom of the piles' room, so nothing moves.
 * Everything along the top grows with the cards (`unit`) on a tablet. Pure geometry, tested at
 * every size it runs on.
 */
import type { Insets } from "./ct-layout";
import type { Rect } from "./drag";
import type { Pose } from "./motion";

/** Off turn; your turn, before the draw; your turn, after it. */
export type CtlStep = "off" | "draw" | "play";

export type CtlInput = {
  width: number;
  height: number;
  insets: Insets;
  /** Cards in the hand (not in a tray). Cards are sized for eleven, the most a hand holds. */
  handCount: number;
  /** The phase's trays while not laid down; 0 once laid down. */
  trays: number;
  step: CtlStep;
  /** Rows in the open hit list (places the picked card fits); 0 or none when it is closed. */
  hits?: number;
};

export type CtlLayout = {
  landscape: boolean;
  /** How much bigger than a phone's the top bar, the buttons and their words are: 1 to 1.6. */
  unit: number;
  /** A hand card at scale 1. */
  cw: number;
  ch: number;
  /** Scale for cards in a tray. */
  small: number;
  /** The table menu's paw (drawn by the table screen, at this unit): kept clear. */
  menu: Rect;
  switch: Rect;
  /** "Your turn" or "<Name>'s turn": in the top bar, beside the menu (or between the switch and the menu where there is room). */
  status: Rect;
  /** Off turn: the cat whose turn it is. */
  hero: Rect | null;
  /** Your turn: the deck and the discard, as big as fit. Each pose is a hand card's, scaled. */
  piles: { deck: Pose; discard: Pose; deckRect: Rect; discardRect: Rect } | null;
  trays: Rect[];
  /** The open hit list, as tall as its rows: over the bottom of the piles' room, sitting on the buttons. */
  hits: Rect | null;
  /** The hit list's X, inside it. */
  hitClose: Rect | null;
  /** Your turn: the row of buttons (Lay down, Discard, Hit). */
  actions: Rect | null;
  hand: Pose[];
  /** The hand and the room a picked card rises into: drops here reorder. */
  handRect: Rect;
};

const EDGE = 8;
const PAD = 8;
const GAP = 10;
/** At unit 1 (a phone): the top bar's height, the switch's width, the button row and a hit row. */
const BAR = 44;
const SWITCH_W = 164;
const ACTIONS = 48;
const HIT_ROW = 44;
/** Room the status needs to share the top bar with the switch: "Great Aunt Josephine's turn" and a cat. */
const STATUS_INLINE = 340;
/** A hand card shows at least this much of itself under the next. */
export const SHOWS = 0.38;
/** The outermost card's turn, in degrees. */
const TILT = 8;
const LIFT = 0.18;
const MAX_CW = 168;
const MIN_CW = 40;
/** The card at which the top bar starts to grow, and how far it grows. */
const UNIT_CW = 88;
const MAX_UNIT = 1.6;
const MAX_HITS = 3;

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

const rad = (deg: number) => (deg * Math.PI) / 180;

/** How far a card turned `deg` reaches past its own box, each side across and up and down. */
const reach = (deg: number, cw: number, ch: number) => {
  const a = rad(Math.abs(deg));
  return { x: (Math.cos(a) * cw + Math.sin(a) * ch - cw) / 2, y: (Math.sin(a) * cw + Math.cos(a) * ch - ch) / 2 };
};

/** A gentle fan of `n` cards across `maxW`, the turned cards' bottoms on `baseY`. */
export function controllerFan(n: number, cx: number, baseY: number, cw: number, ch: number, maxW: number): Pose[] {
  if (n === 0) return [];
  const mid = (n - 1) / 2;
  const per = n > 1 ? Math.min(2, (2 * TILT) / (n - 1)) : 0;
  const outer = reach(per * mid, cw, ch);
  const step = n === 1 ? 0 : Math.min(cw * 0.9, (maxW - 2 * outer.x - cw) / (n - 1));
  const left = cx - (cw + step * (n - 1)) / 2;
  const drop = (d: number) => d * d * ch * 0.003;
  const lowest = drop(mid) + outer.y;
  return Array.from({ length: n }, (_, i) => {
    const d = i - mid;
    return { x: left + i * step, y: baseY - ch - lowest + drop(d), r: d * per, s: 1, z: 100 + i };
  });
}

export function ctControllerLayout(input: CtlInput): CtlLayout {
  const first = Math.floor(Math.min(widthCap(input), heightCap(input), MAX_CW));
  const unit = Math.round(clamp(first / UNIT_CW, 1, MAX_UNIT) * 100) / 100;
  // The biggest cards with which everything else still fits.
  for (let cw = first; cw > MIN_CW; cw -= 2) {
    const L = layoutAt(input, cw, unit);
    if (L) return L;
  }
  return layoutAt(input, MIN_CW, unit, true)!;
}

const frameOf = (input: CtlInput) => {
  const { width: W, height: H, insets } = input;
  return { l: insets.left, r: W - insets.right, t: insets.top, b: H - insets.bottom };
};

const columnOf = (input: CtlInput) => {
  const f = frameOf(input);
  const w = Math.min(f.r - f.l - 2 * PAD, 1000);
  return { x: (f.l + f.r) / 2 - w / 2, w };
};

const landscapeOf = (input: CtlInput) => input.width > input.height * 1.15;

/** The widest card with which eleven fan across the screen, each showing its corner. */
function widthCap(input: CtlInput): number {
  const n = Math.max(input.handCount, 11);
  const per = Math.min(2, (2 * TILT) / (n - 1));
  // The outer cards turn: their reach is about this share of a card on each side.
  const turn = reach(per * ((n - 1) / 2), 1, 1.406).x;
  return columnOf(input).w / (1 + (n - 1) * SHOWS + 2 * turn);
}

/** The hand takes about a quarter of a tall screen, or a third of a wide one. */
function heightCap(input: CtlInput): number {
  const f = frameOf(input);
  return ((f.b - f.t) * (landscapeOf(input) ? 0.32 : 0.24)) / 1.406;
}

/** A hit list of `rows` rows: the rows, the gaps between them, and the panel's padding. */
const listH = (rows: number, u: number) => rows * HIT_ROW * u + (rows - 1) * 6 + 16;

function layoutAt(input: CtlInput, cw: number, u: number, force = false): CtlLayout | null {
  const f = frameOf(input);
  const col = columnOf(input);
  const landscape = landscapeOf(input);
  const ch = Math.round(cw * 1.406);
  const cx = col.x + col.w / 2;
  const mine = input.step !== "off";
  const bar = BAR * u;

  // The top bar: the status beside the menu, the switch under it; or all three in a row when wide.
  const menu = { x: f.r - EDGE - 44 * u, y: f.t + EDGE, w: 44 * u, h: 44 * u };
  const inline = menu.x - GAP - (f.l + EDGE + SWITCH_W * u + GAP) >= STATUS_INLINE * u;
  const sw = { x: f.l + EDGE, y: inline ? f.t + EDGE : f.t + EDGE + bar + GAP, w: SWITCH_W * u, h: bar };
  const statusX = inline ? sw.x + sw.w + GAP : f.l + EDGE;
  const status = { x: statusX, y: f.t + EDGE, w: menu.x - GAP - statusX, h: bar };
  const top = sw.y + sw.h + GAP;

  // The hand along the bottom.
  const baseY = f.b - EDGE;
  const hand = controllerFan(input.handCount, cx, baseY, cw, ch, col.w);
  const sized = controllerFan(Math.max(input.handCount, 11), cx, baseY, cw, ch, col.w);
  const highest = Math.min(...sized.map((p) => p.y - reach(p.r ?? 0, cw, ch).y));
  const handTop = highest - ch * LIFT;
  const handRect = { x: col.x, y: handTop, w: col.w, h: baseY - handTop };
  const middle = { y: top, h: handTop - GAP - top };

  // Tray cards: a little over half a hand card on a phone, never under 46% of one on a tablet.
  const small = Math.max(Math.min(0.56, 76 / ch), 0.46);
  const trayH = Math.round(ch * small + 22);
  const pileFor = (area: Rect) => Math.floor(Math.min((area.w - 3 * GAP) / 2, (area.h - 16) / 1.406, 360));
  const actionsH = ACTIONS * u;

  if (!mine) {
    const size = Math.min(col.w, middle.h, 240 * u);
    if (size < 72 && !force) return null;
    const hero = { x: cx - size / 2, y: middle.y + middle.h / 2 - size / 2, w: size, h: size };
    return { landscape, unit: u, cw, ch, small, menu, switch: sw, status, hero, piles: null, trays: [], hits: null, hitClose: null, actions: null, hand, handRect };
  }

  // Your turn: the piles, the trays, the buttons; the trays and buttons beside the piles when wide.
  const half = (col.w - GAP) / 2;
  const rows = Math.min(input.hits ?? 0, MAX_HITS);
  let actions: Rect;
  let stage: Rect;
  let trayRow: Rect | null = null;
  let hits: Rect | null = null;
  if (landscape) {
    const right = { x: col.x + half + GAP, w: half };
    // The hit list's room is kept above the buttons, so they stay put when it opens.
    const workH = input.trays > 0 ? trayH : Math.max(listH(1, u), Math.min(listH(MAX_HITS, u), middle.h - GAP - actionsH));
    const block = workH + GAP + actionsH;
    const y0 = Math.max(middle.y, middle.y + middle.h / 2 - block / 2);
    actions = { x: right.x, y: y0 + workH + GAP, w: right.w, h: actionsH };
    if (input.trays > 0) trayRow = { x: right.x, y: y0, w: right.w, h: trayH };
    else if (rows > 0) {
      const h = Math.min(listH(rows, u), workH);
      hits = { x: right.x, y: actions.y - GAP - h, w: right.w, h };
    }
    stage = { x: col.x, y: middle.y, w: half, h: middle.h };
    if (actions.y + actionsH > handTop - GAP + 0.5 && !force) return null;
  } else {
    actions = { x: col.x, y: handTop - GAP - actionsH, w: col.w, h: actionsH };
    if (input.trays > 0) trayRow = { x: col.x, y: actions.y - GAP - trayH, w: col.w, h: trayH };
    stage = { x: col.x, y: top, w: col.w, h: (trayRow ? trayRow.y : actions.y) - GAP - top };
    if (rows > 0) {
      const h = Math.min(listH(rows, u), stage.h * 0.75);
      hits = { x: col.x, y: stage.y + stage.h - h, w: col.w, h };
    }
  }
  const pileW = pileFor(stage);
  if (pileW < cw * 0.9 && !force) return null;

  const trays: Rect[] = [];
  if (trayRow) {
    const each = Math.min((trayRow.w - GAP * (input.trays - 1)) / input.trays, cw * 4.6, 360 * u);
    const used = each * input.trays + GAP * (input.trays - 1);
    const left = trayRow.x + (trayRow.w - used) / 2;
    for (let i = 0; i < input.trays; i++) trays.push({ x: left + i * (each + GAP), y: trayRow.y, w: each, h: trayH });
  }
  const x = 32 * u;
  const hitClose = hits ? { x: hits.x + hits.w - 8 - x, y: hits.y + 8 + (HIT_ROW * u - x) / 2, w: x, h: x } : null;

  const s = pileW / cw;
  const pileH = ch * s;
  const pileGap = Math.max(GAP * 1.6, pileW * 0.18);
  const pcx = stage.x + stage.w / 2;
  // The deck's count hangs 8 px off its corner: the pair sits that much high.
  const pcy = stage.y + stage.h / 2 - 4;
  const deckRect = { x: pcx - pileGap / 2 - pileW, y: pcy - pileH / 2, w: pileW, h: pileH };
  const discardRect = { x: pcx + pileGap / 2, y: pcy - pileH / 2, w: pileW, h: pileH };
  const pose = (r: Rect, z: number): Pose => ({ x: r.x + r.w / 2 - cw / 2, y: r.y + r.h / 2 - ch / 2, r: 0, s, z });
  return {
    landscape,
    unit: u,
    cw,
    ch,
    small,
    menu,
    switch: sw,
    status,
    hero: null,
    piles: { deck: pose(deckRect, 5), discard: pose(discardRect, 6), deckRect, discardRect },
    trays,
    hits,
    hitClose,
    actions,
    hand,
    handRect,
  };
}
