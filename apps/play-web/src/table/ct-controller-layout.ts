/**
 * Where everything sits on a phone that is a Cat Tower controller (the table is on a TV): the
 * Cards/Table switch and the menu along the top, whose turn it is, the two piles on your turn (or
 * the cat whose turn it is), the trays or the list of places to hit, the buttons, and the hand,
 * big, along the bottom. Pure geometry, tested at every size it runs on.
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
  /** The phase's trays while not laid down; 0 once laid down (the hit list takes their place). */
  trays: number;
  step: CtlStep;
};

export type CtlLayout = {
  landscape: boolean;
  /** A hand card at scale 1. */
  cw: number;
  ch: number;
  /** Scale for cards in a tray. */
  small: number;
  /** The table menu's paw (drawn by the table screen): kept clear. */
  menu: Rect;
  switch: Rect;
  /** "Your turn" or "<Name>'s turn": a row of its own, or between the switch and the menu where there is room. */
  status: Rect;
  /** Off turn: the cat whose turn it is. */
  hero: Rect | null;
  /** Your turn: the deck and the discard, as big as fit. Each pose is a hand card's, scaled. */
  piles: { deck: Pose; discard: Pose; deckRect: Rect; discardRect: Rect } | null;
  /** Your turn: the trays' row, or (laid down) the list of places to hit. */
  work: Rect | null;
  trays: Rect[];
  /** Your turn: the row of buttons (Lay down, Discard, Hit). */
  actions: Rect | null;
  hand: Pose[];
  /** The hand and the room a picked card rises into: drops here reorder. */
  handRect: Rect;
};

const EDGE = 8;
const PAD = 8;
const GAP = 10;
const BAR = 44;
const STATUS_ROW = 48;
const ACTIONS = 48;
const SWITCH_W = 164;
/** Room the status needs to share the top bar: "Great Aunt Josephine's turn" and a cat. */
const STATUS_INLINE = 340;
/** A hand card shows at least this much of itself under the next. */
const SHOWS = 0.42;
/** The outermost card's turn, in degrees. */
const TILT = 8;
const LIFT = 0.18;
const MAX_CW = 132;
const MIN_CW = 40;
/** The hit list: three rows of 44 with a little room. */
const HIT_LIST = 3 * 44 + 2 * 6 + 16;

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
  // The biggest cards with which everything else still fits.
  for (let cw = first; cw > MIN_CW; cw -= 2) {
    const L = layoutAt(input, cw);
    if (L) return L;
  }
  return layoutAt(input, MIN_CW, true)!;
}

const frameOf = (input: CtlInput) => {
  const { width: W, height: H, insets } = input;
  return { l: insets.left, r: W - insets.right, t: insets.top, b: H - insets.bottom };
};

const columnOf = (input: CtlInput) => {
  const f = frameOf(input);
  const w = Math.min(f.r - f.l - 2 * PAD, 920);
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

/** The hand takes no more than a fifth of a tall screen, or under a third of a wide one. */
function heightCap(input: CtlInput): number {
  const f = frameOf(input);
  return ((f.b - f.t) * (landscapeOf(input) ? 0.3 : 0.2)) / 1.406;
}

function layoutAt(input: CtlInput, cw: number, force = false): CtlLayout | null {
  const f = frameOf(input);
  const col = columnOf(input);
  const landscape = landscapeOf(input);
  const ch = Math.round(cw * 1.406);
  const cx = col.x + col.w / 2;
  const mine = input.step !== "off";

  // The top bar.
  const menu = { x: f.r - EDGE - 44, y: f.t + EDGE, w: 44, h: 44 };
  const sw = { x: f.l + EDGE, y: f.t + EDGE, w: SWITCH_W, h: BAR };
  const between = menu.x - GAP - (sw.x + sw.w + GAP);
  const status = between >= STATUS_INLINE ? { x: sw.x + sw.w + GAP, y: sw.y, w: between, h: BAR } : { x: col.x, y: sw.y + BAR + GAP, w: col.w, h: STATUS_ROW };
  const top = status.y + status.h + GAP;

  // The hand along the bottom.
  const baseY = f.b - EDGE;
  const hand = controllerFan(input.handCount, cx, baseY, cw, ch, col.w);
  const sized = controllerFan(Math.max(input.handCount, 11), cx, baseY, cw, ch, col.w);
  const highest = Math.min(...sized.map((p) => p.y - reach(p.r ?? 0, cw, ch).y));
  const handTop = highest - ch * LIFT;
  const handRect = { x: col.x, y: handTop, w: col.w, h: baseY - handTop };
  const middle = { y: top, h: handTop - GAP - top };

  const small = Math.min(0.56, 76 / ch);
  const trayH = Math.round(ch * small + 22);
  const pileFor = (area: Rect) => Math.floor(Math.min((area.w - 3 * GAP) / 2, (area.h - 16) / 1.406, cw * 1.7, 240));

  if (!mine) {
    const size = Math.min(col.w, middle.h, 240);
    if (size < 72 && !force) return null;
    const hero = { x: cx - size / 2, y: middle.y + middle.h / 2 - size / 2, w: size, h: size };
    return { landscape, cw, ch, small, menu, switch: sw, status, hero, piles: null, work: null, trays: [], actions: null, hand, handRect };
  }

  // Your turn: the piles, then the trays or the hit list, then the buttons; side by side when wide.
  const half = (col.w - GAP) / 2;
  const right = landscape ? { x: col.x + half + GAP, w: half } : { x: col.x, w: col.w };
  let actions: Rect;
  let work: Rect;
  let stage: Rect;
  if (landscape) {
    const workH = input.trays > 0 ? trayH : Math.min(HIT_LIST + 60, middle.h - ACTIONS - GAP);
    const block = workH + GAP + ACTIONS;
    const y0 = Math.max(middle.y, middle.y + middle.h / 2 - block / 2);
    work = { x: right.x, y: y0, w: right.w, h: workH };
    actions = { x: right.x, y: y0 + workH + GAP, w: right.w, h: ACTIONS };
    stage = { x: col.x, y: middle.y, w: half, h: middle.h };
    if (actions.y + ACTIONS > handTop - GAP + 0.5 && !force) return null;
  } else {
    actions = { x: col.x, y: handTop - GAP - ACTIONS, w: col.w, h: ACTIONS };
    const above = actions.y - GAP - top;
    // The piles keep at least a hand card's size; the hit list takes up to three rows of the rest.
    const workH = input.trays > 0 ? trayH : Math.min(HIT_LIST, above - GAP - (Math.ceil(cw * 0.9) * 1.406 + 18));
    work = { x: col.x, y: actions.y - GAP - workH, w: col.w, h: workH };
    stage = { x: col.x, y: top, w: col.w, h: work.y - GAP - top };
  }
  const pileW = pileFor(stage);
  if ((pileW < cw * 0.9 || work.h < (input.trays > 0 ? trayH : 56)) && !force) return null;

  const trays: Rect[] = [];
  if (input.trays > 0) {
    const each = Math.min((work.w - GAP * (input.trays - 1)) / input.trays, cw * 4.6, 360);
    const used = each * input.trays + GAP * (input.trays - 1);
    const left = work.x + (work.w - used) / 2;
    for (let i = 0; i < input.trays; i++) trays.push({ x: left + i * (each + GAP), y: work.y, w: each, h: trayH });
  }

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
    cw,
    ch,
    small,
    menu,
    switch: sw,
    status,
    hero: null,
    piles: { deck: pose(deckRect, 5), discard: pose(discardRect, 6), deckRect, discardRect },
    work,
    trays,
    actions,
    hand,
    handRect,
  };
}
