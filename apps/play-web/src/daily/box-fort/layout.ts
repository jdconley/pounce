/**
 * Where Box Fort's pieces go: the score row, the rug and the three tray slots, and the drag's
 * arithmetic. The same numbers as the app's `BoxFortLayout` (PounceKit), so a piece snaps the
 * same way on every screen. Phones stack the score, rug and tray; a wide space puts the tray in
 * a column beside the rug.
 */
export type Box = { x: number; y: number; w: number; h: number };
export type Point = { x: number; y: number };
export type Span = { rows: number; cols: number };
export type Spot = { row: number; col: number };

export type BoxFortLayout = {
  width: number;
  height: number;
  cell: number;
  trayCell: number;
  header: Box;
  rug: Box;
  slots: Box[];
  sideTray: boolean;
};

export const MAX_CELL = 76;
export const TRAY_SCALE = 0.5;
/** A lifted piece floats this many spots above the finger. */
export const LIFT = 1.1;
/** The rug's border and fringe reach this many spots past its spots, all round. */
export const FRINGE = 0.5;
const GUTTER = 16;
const GAP = 12;
const HEADER = 48;
const SLOT_PAD = 10;

export function boxFortLayout(width: number, height: number): BoxFortLayout {
  const sideTray = width > height * 1.15;
  const cell = Math.max(
    1,
    sideTray
      ? // Room under the rug for the finger: a piece going on the bottom row floats above a finger
        // LIFT spots below the rug (the stacked layout's tray gives it that room).
        Math.min(MAX_CELL, (height - HEADER - 2 * GAP) / (8 + FRINGE + LIFT), (width - 2 * GUTTER - GAP - 2 * SLOT_PAD) / (8 + 2 * FRINGE + 5 * TRAY_SCALE))
      : Math.min(MAX_CELL, (width - 2 * GUTTER) / 8, (height - HEADER - 3 * GAP - 2 * SLOT_PAD) / (8 + 2 * FRINGE + 5 * TRAY_SCALE)),
  );
  const side = 8 * cell;
  const depth = 5 * cell * TRAY_SCALE + 2 * SLOT_PAD;
  const fringe = FRINGE * cell;
  if (sideTray) {
    const total = side + 2 * fringe + GAP + depth;
    const left = (width - total) / 2;
    const top = HEADER + GAP + fringe + Math.max(0, (height - HEADER - GAP - fringe - side - LIFT * cell) / 2);
    const rug = { x: left + fringe, y: top, w: side, h: side };
    return {
      width,
      height,
      cell,
      trayCell: cell * TRAY_SCALE,
      sideTray,
      header: { x: left, y: 0, w: total, h: HEADER },
      rug,
      slots: [0, 1, 2].map((i) => ({ x: rug.x + side + fringe + GAP, y: top + (i * side) / 3, w: depth, h: side / 3 })),
    };
  }
  const total = HEADER + GAP + fringe + side + fringe + GAP + depth;
  const top = Math.max(0, (height - total) / 2);
  const left = (width - side) / 2;
  const rug = { x: left, y: top + HEADER + GAP + fringe, w: side, h: side };
  return {
    width,
    height,
    cell,
    trayCell: cell * TRAY_SCALE,
    sideTray,
    header: { x: left, y: top, w: side, h: HEADER },
    rug,
    slots: [0, 1, 2].map((i) => ({ x: left + (i * side) / 3, y: rug.y + side + fringe + GAP, w: side / 3, h: depth })),
  };
}

/** Rows and columns a piece's cells span. */
export const spanOf = (cells: readonly (readonly [number, number])[]): Span => ({
  rows: Math.max(...cells.map(([r]) => r)) + 1,
  cols: Math.max(...cells.map(([, c]) => c)) + 1,
});

/** Where a piece is drawn while a finger at `finger` holds it: centered across it, floating above. */
export const lifted = (l: BoxFortLayout, finger: Point, span: Span): Point => ({
  x: finger.x - (span.cols * l.cell) / 2,
  y: finger.y - span.rows * l.cell - LIFT * l.cell,
});

/** The spot a piece drawn at `origin` lands on, or null when it would hang off the rug. */
export function snap(l: BoxFortLayout, origin: Point, span: Span): Spot | null {
  // `|| 0`: a rounded -0.4 is -0, and a spot is a plain 0.
  const row = Math.round((origin.y - l.rug.y) / l.cell) || 0;
  const col = Math.round((origin.x - l.rug.x) / l.cell) || 0;
  if (row < 0 || col < 0 || row + span.rows > 8 || col + span.cols > 8) return null;
  return { row, col };
}

/** Top-left of a piece resting in tray `slot`, at tray scale. */
export function trayOrigin(l: BoxFortLayout, slot: number, span: Span): Point {
  const s = l.slots[slot] as Box;
  return { x: s.x + s.w / 2 - (span.cols * l.trayCell) / 2, y: s.y + s.h / 2 - (span.rows * l.trayCell) / 2 };
}

export function slotAt(l: BoxFortLayout, p: Point): number | null {
  const i = l.slots.findIndex((s) => p.x >= s.x && p.x <= s.x + s.w && p.y >= s.y && p.y <= s.y + s.h);
  return i < 0 ? null : i;
}
