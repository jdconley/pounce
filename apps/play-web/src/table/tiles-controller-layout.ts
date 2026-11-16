/**
 * Where everything sits on a phone that is a Tuna Tiles controller off turn (the table is on a
 * TV): the Cards/Table switch, whose turn it is and the menu along the top, as Cat Tower's
 * controller has them (controllerBar); the toy box, big, with its count; the sort button; and the
 * rack along the bottom, as big as fits, in even rows. Pure geometry, tested at every size it
 * runs on.
 */
import { controllerBar, type Frame } from "./ct-controller-layout";

import type { Insets } from "./ct-layout";
import type { Point, Rect } from "./drag";
import type { Pose } from "./motion";

export type TclInput = { width: number; height: number; insets: Insets; rack: number };

export type TclLayout = {
  landscape: boolean;
  /** How much bigger than a phone's the top bar and the buttons are: 1 to 1.6. */
  unit: number;
  /** A rack piece. */
  pw: number;
  ph: number;
  menu: Rect;
  switch: Rect;
  status: Rect;
  /** The toy box (square) and the box it draws in with its count hanging off the corner. */
  pool: { x: number; y: number; size: number };
  poolRect: Rect;
  sort: Rect;
  rack: Pose[];
  /** The rack and its margin: drops here reorder it. */
  rackRect: Rect;
  /** The place in the rack a piece held at `p` goes: before the piece it is over the left half of. */
  indexAt: (p: Point) => number;
};

const EDGE = 8;
const PAD = 8;
const GAP = 10;
/** A piece's step across, and down to the next row, in piece widths. */
const STEP = 1.06;
const ROW_GAP = 0.12;
const RATIO = 1.2;
/** The rack's margin, inside its rect. */
const MARGIN = 6;
/** Rows read as runs: at least this many pieces to a row. */
const MIN_COLS = 4;
/** Fewer rows win unless more rows make pieces bigger by more than this. */
const FEWER_ROWS = 0.85;
/** At unit 1 (a phone). */
const MAX_PW = 80;
const SORT = 46;
const POOL_MIN = 72;
const POOL_MAX = 240;
/** The count hangs this far off the toy box's corner (`.pile-count`). */
const COUNT = 8;

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

/** A grid of `rows` rows of `n` pieces: its height, in piece widths. */
const heightIn = (rows: number) => rows * RATIO + (rows - 1) * ROW_GAP;

export function tilesControllerLayout(input: TclInput): TclLayout {
  const { width: W, height: H, insets } = input;
  const f: Frame = { l: insets.left, r: W - insets.right, t: insets.top, b: H - insets.bottom };
  const fw = f.r - f.l;
  const fh = f.b - f.t;
  const landscape = W > H * 1.15;
  const unit = Math.round(clamp(Math.min(fw, fh) / 512, 1, 1.6) * 100) / 100;
  const bar = controllerBar(f, unit);
  const colW = Math.min(fw - 2 * PAD, 1000);
  const cx = (f.l + f.r) / 2;
  const bottom = f.b - EDGE;
  const sortSize = SORT * unit;

  // The rack: the biggest pieces that fit, in as few rows as reads well.
  const n = input.rack;
  const room = bottom - bar.top - (sortSize + GAP) - (POOL_MIN * unit + 2 * COUNT + GAP) - 2 * MARGIN;
  const across = colW - 2 * MARGIN;
  const cap = MAX_PW * unit;
  const options: { rows: number; cols: number; pw: number }[] = [];
  // From one long row down to rows of MIN_COLS; each count of rows once, with its fewest columns.
  for (let cols = Math.max(n, 1); cols >= Math.min(MIN_COLS, Math.max(n, 1)); cols--) {
    const rows = Math.ceil(Math.max(n, 1) / cols);
    const last = options[options.length - 1];
    if (last?.rows === rows) {
      last.cols = cols;
      continue;
    }
    options.push({ rows, cols, pw: 0 });
  }
  for (const o of options) o.pw = Math.floor(Math.min(across / (o.cols * STEP - (STEP - 1)), room / heightIn(o.rows), cap));
  const best = Math.max(...options.map((o) => o.pw));
  const pick = options.find((o) => o.pw >= best * FEWER_ROWS)!;
  const { cols } = pick;
  const rows = n === 0 ? 0 : pick.rows;
  const pw = pick.pw;
  const ph = Math.round(pw * RATIO);
  const step = pw * STEP;
  const rowGap = Math.round(pw * ROW_GAP);
  const gridH = rows === 0 ? 0 : rows * ph + (rows - 1) * rowGap;
  const rackRect = { x: cx - colW / 2, y: bottom - gridH - 2 * MARGIN, w: colW, h: gridH + 2 * MARGIN };
  const rack: Pose[] = [];
  const rowLeft: number[] = [];
  for (let r = 0; r < rows; r++) {
    const inRow = Math.min(cols, n - r * cols);
    rowLeft.push(cx - (step * inRow - (step - pw)) / 2);
  }
  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / cols);
    rack.push({ x: rowLeft[r]! + (i % cols) * step, y: rackRect.y + MARGIN + r * (ph + rowGap), r: 0, s: 1, z: 200 + i });
  }

  // The sort button over the rack's right end; the toy box in the room left above.
  const gridRight = cx + (step * Math.min(cols, Math.max(n, 1)) - (step - pw)) / 2;
  const sort = { x: Math.min(gridRight, cx + colW / 2) - sortSize, y: rackRect.y - GAP - sortSize, w: sortSize, h: sortSize };
  const area = { y: bar.top, h: sort.y - GAP - bar.top };
  const size = Math.floor(Math.min(area.h - 2 * COUNT, colW * 0.6, POOL_MAX * unit));
  const pool = { x: cx - size / 2, y: area.y + (area.h - size) / 2 - COUNT / 2, size };
  const poolRect = { x: pool.x, y: pool.y, w: size + COUNT, h: size + COUNT };

  const indexAt = (p: Point): number => {
    if (rows === 0) return 0;
    const r = clamp(Math.floor((p.y - rackRect.y - MARGIN + rowGap / 2) / (ph + rowGap)), 0, rows - 1);
    const start = r * cols;
    const inRow = Math.min(cols, n - start);
    const k = Math.floor((p.x - rowLeft[r]! + step - pw / 2) / step);
    return start + clamp(k, 0, inRow);
  };

  return { landscape, unit, pw, ph, menu: bar.menu, switch: bar.switch, status: bar.status, pool, poolRect, sort, rack, rackRect, indexAt };
}
