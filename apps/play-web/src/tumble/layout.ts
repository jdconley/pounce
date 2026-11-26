/**
 * Where everything goes on a Toy Tumble screen (spec §5.2, §5.6), from the viewport alone, so it
 * is tested without a page: your box leaning left with the cat on its rim, its junk meter, the
 * minis (chips at a TV table), the trick tray, and the corner the table menu keeps. Also the grid
 * of every box when watching, and the TV's row of boxes.
 */
export type Rect = { x: number; y: number; w: number; h: number };
export type BoxRect = Rect & { cell: number };
export type Insets = { top: number; right: number; bottom: number; left: number };

export const COLS = 12;
export const ROWS = 18;
/** The rows of hidden space above the box that a toy appears in, drawn faintly over the rim. */
const GAP = 8;
const RIM = 56;
const TRAY = 64;
const TRAY_BIG = 84;
const MENU = 56;
const METER_MIN = 14;
/** The junk meter's width, in cells. */
const METER = 0.8;
const RIM_MAX = 96;
/** A mini is at most this much of your box: yours leads. */
const MINI_MAX = 0.45;
/** A mini's name and wins strip. */
export const MINI_LABEL = 20;
const CHIP_H = 44;
const CHIP_H_NARROW = 64;
const CHIP_W = 160;
/** The minis' (or chips') column on a phone. */
const PHONE_SIDE = 72;
/** The largest a cell gets on a big screen: the box stays a box, not a wall. */
const CELL_MAX = 44;

export type PlayLayout = {
  box: BoxRect;
  /** Over the box: the cat holding the next toy, your number and wins. */
  rim: Rect;
  meter: Rect;
  minis: BoxRect[];
  chips: Rect[];
  tray: Rect;
  slots: Rect[];
  /** The table menu's corner, kept free. */
  menu: Rect;
  landscape: boolean;
};

export type PlayInput = { width: number; height: number; insets: Insets; others: number; chips: boolean };

/** The biggest mini cell for `n` minis in a region, and how they sit. */
function fitMinis(region: Rect, n: number, maxCell = Infinity): BoxRect[] {
  if (n === 0 || region.w <= 0 || region.h <= 0) return [];
  let best: { cell: number; cols: number } = { cell: 0, cols: 1 };
  for (let cols = 1; cols <= Math.min(3, n); cols++) {
    const rows = Math.ceil(n / cols);
    const colW = (region.w - GAP * (cols - 1)) / cols;
    const rowH = (region.h - GAP * (rows - 1)) / rows;
    const cell = Math.floor(Math.min(colW / COLS, (rowH - MINI_LABEL) / ROWS, maxCell) * 4) / 4;
    if (cell > best.cell) best = { cell, cols };
  }
  const { cell, cols } = best;
  const w = cell * COLS;
  const h = cell * ROWS + MINI_LABEL;
  const rows = Math.ceil(n / cols);
  const usedW = cols * w + (cols - 1) * GAP;
  const x0 = region.x + Math.max(0, (region.w - usedW) / 2);
  return Array.from({ length: n }, (_, i) => {
    const c = i % cols;
    const r = Math.floor(i / cols);
    return { x: x0 + c * (w + GAP), y: region.y + r * (h + GAP), w, h, cell };
  }).slice(0, rows * cols);
}

function chipsIn(region: Rect, n: number): Rect[] {
  const h = Math.min(region.w < 110 ? CHIP_H_NARROW : CHIP_H, (region.h - GAP * (n - 1)) / Math.max(1, n));
  return Array.from({ length: n }, (_, i) => ({ x: region.x, y: region.y + i * (h + GAP), w: region.w, h }));
}

export function playLayout(p: PlayInput): PlayLayout {
  const L = p.insets.left + GAP;
  const R = p.width - p.insets.right - GAP;
  const T = p.insets.top + GAP;
  const B = p.height - p.insets.bottom - GAP;
  const n = Math.max(0, Math.min(5, p.others));
  const landscape = p.width > p.height * 1.15 && n >= 2 && !p.chips;
  const menu = { x: p.width - p.insets.right - MENU, y: p.insets.top, w: MENU, h: MENU };

  // The tray along the bottom, the box sitting on it (the thumbs' end of the screen), the rim on
  // the box. The box's cells are what the height between the rim and the tray, and the width
  // beside the minis, allow.
  // A phone keeps the rim and tray slim, and gives its minis a slim column, so the box keeps
  // cells of 20 px or more. A big screen gives the rim and tray room.
  const narrow = R - L < 500;
  const trayH = narrow ? TRAY : TRAY_BIG;
  const rimWant = narrow ? RIM : Math.round(Math.min(RIM_MAX, Math.max(RIM, (B - T) * 0.09)));
  const trayTop = B - trayH;
  const cellByH = (trayTop - GAP - T - rimWant) / ROWS;
  const side = n === 0 ? 0 : narrow ? PHONE_SIDE : p.chips ? CHIP_W : landscape ? Math.max(120, (R - L) * 0.22) : Math.max(120, (R - L) * 0.24);
  const sides = landscape ? 2 : n === 0 ? 0 : 1;
  const cellByW = (R - L - side * sides - GAP * (sides + 1) - METER_MIN) / (COLS + METER);
  const cell = Math.max(4, Math.floor(Math.min(cellByH, cellByW, CELL_MAX)));
  const bw = cell * COLS;
  const bh = cell * ROWS;
  const meterW = Math.max(METER_MIN, Math.round(cell * METER));
  const boxTop = trayTop - GAP - bh;
  // The rim grows with the box, into the room above it.
  const rimH = Math.round(Math.max(RIM, Math.min(RIM_MAX, cell * 1.8, boxTop - T)));

  const boxX = landscape ? Math.round((p.width - bw - meterW - GAP) / 2) : L;
  const box = { x: boxX, y: boxTop, w: bw, h: bh, cell };
  const meter = { x: boxX + bw + GAP / 2, y: boxTop, w: meterW, h: bh };
  const rimY = boxTop - rimH;
  const rimW = rimY < menu.y + menu.h ? Math.min(bw + meterW, menu.x - GAP - boxX) : bw + meterW;
  const rim = { x: boxX, y: rimY, w: rimW, h: rimH - GAP };

  let minis: BoxRect[] = [];
  let chips: Rect[] = [];
  // The minis start under the menu's corner, and stop at the tray (portrait) or the bottom.
  const colTop = menu.y + menu.h + GAP;
  if (n > 0) {
    if (landscape) {
      const left = { x: L, y: colTop, w: boxX - GAP - L, h: B - colTop };
      const rightX = meter.x + meter.w + GAP;
      const right = { x: rightX, y: colTop, w: R - rightX, h: B - colTop };
      const nl = Math.ceil(n / 2);
      minis = [...fitMinis(left, nl, cell * MINI_MAX), ...fitMinis(right, n - nl, cell * MINI_MAX)];
    } else {
      const x = meter.x + meter.w + GAP;
      const region = { x, y: colTop, w: R - x, h: trayTop - GAP - colTop };
      if (p.chips) chips = chipsIn(region, n);
      else minis = fitMinis(region, n, cell * MINI_MAX);
    }
  }

  // Portrait: the tray spans the screen. Landscape: it sits under the box, between the minis.
  const trayRoom = landscape ? bw + GAP / 2 + meterW : R - L;
  const slotSize = Math.min(trayH - 8, (trayRoom - GAP * 5) / 6);
  const trayW = slotSize * 6 + GAP * 5;
  const trayX = landscape ? boxX + (bw + GAP / 2 + meterW - trayW) / 2 : L;
  const tray = { x: trayX, y: trayTop, w: trayW, h: trayH };
  const slots = Array.from({ length: 6 }, (_, i) => ({ x: trayX + i * (slotSize + GAP), y: trayTop + (trayH - slotSize) / 2, w: slotSize, h: slotSize }));
  return { box, rim, meter, minis, chips, tray, slots, menu, landscape };
}

/** Out of the round: every box big, in the grid that gives them the biggest cells. */
export function watchLayout(p: { width: number; height: number; insets: Insets; n: number; top?: number }): BoxRect[] {
  const region = {
    x: p.insets.left + GAP,
    y: p.insets.top + (p.top ?? MENU) + GAP,
    w: p.width - p.insets.left - p.insets.right - GAP * 2,
    h: p.height - p.insets.top - p.insets.bottom - (p.top ?? MENU) - GAP * 2,
  };
  return fitMinis(region, p.n);
}

/** The TV: up to six boxes in one row, sized to fill the screen, each with its name strip under it. */
export function tvLayout(p: { width: number; height: number; n: number; header: number; label: number }): BoxRect[] {
  const n = Math.max(1, p.n);
  const pad = Math.round(p.width * 0.025);
  const gap = Math.round(p.width * 0.018);
  const top = p.header;
  const availW = p.width - pad * 2 - gap * (n - 1);
  const availH = p.height - top - p.label - pad;
  const cell = Math.floor(Math.min(availW / n / (COLS + 1), availH / ROWS));
  const w = cell * COLS;
  const h = cell * ROWS;
  const used = n * w + (n - 1) * gap + n * cell;
  const x0 = Math.round((p.width - used) / 2);
  return Array.from({ length: n }, (_, i) => ({ x: x0 + i * (w + cell + gap), y: top + Math.max(0, Math.round((availH - h) / 2)), w, h, cell }));
}

export const overlaps = (a: Rect, b: Rect): boolean => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
