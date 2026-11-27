/**
 * Draws a Toy Tumble box on a canvas, at any cell size (spec §3, §5.2): round plush cushions in
 * the Tuna Tiles toy colours, each stitched with its toy's silhouette; fluffy grey hairball rows;
 * glowing trick badges; the dashed paw-print outline where the toy will land; and the junk meter
 * beside the box. Settled cells are drawn once onto an offscreen canvas per box and copied each
 * frame; only the falling toy and the meter are drawn live.
 */
import { JUNK, TRICKS, W, type Box, type Trick } from "@pounce/play-api/tumble/box";
import { toyCells, TOY_INDEX, type Rot, type ToyId } from "@pounce/play-api/tumble/toys";

import { art } from "../lib/art";

import { COLS, ROWS } from "./layout";

export type Suit = "fish" | "mouse" | "feather" | "bell";
type Look = { top: string; base: string; side: string; suit: Suit };

const LOOKS: Record<Suit, Look> = {
  fish: { top: "#4ff2e4", base: "#00d1c1", side: "#008f8a", suit: "fish" },
  mouse: { top: "#9d63ff", base: "#7b2fff", side: "#4e13c4", suit: "mouse" },
  feather: { top: "#ffae3d", base: "#ff8a00", side: "#c85a00", suit: "feather" },
  bell: { top: "#ffe66b", base: "#ffd21f", side: "#d99a00", suit: "bell" },
};

/**
 * Each toy's colour, by its index in `TOY_IDS` (i3, v3, i4, o4, t4, l4, j4, p5, u5). Four colours
 * across nine shapes, so no shape-to-colour pairing echoes the classic game's (spec §3).
 */
export const TOY_SUIT: readonly Suit[] = ["fish", "bell", "feather", "mouse", "fish", "bell", "mouse", "feather", "fish"];
export const toySuit = (id: ToyId): Suit => TOY_SUIT[TOY_INDEX[id]] as Suit;

/** Each trick's badge colour, in `TRICKS` order. */
export const TRICK_COLOR: Record<Trick, string> = {
  hairball: "#a7a9be",
  swipe: "#ff8a00",
  catnip: "#5fe04a",
  scoop: "#00d1c1",
  settle: "#2eb8ff",
  nap: "#9d63ff",
  swap: "#ff2e9a",
  bath: "#7fd8ff",
};

const INK = "#1b0a3c";
const BOX_FLOOR = "#2a1262";
const BOX_LINE = "rgba(255,255,255,0.05)";
const FUR = "#9a9bb0";
const FUR_LIGHT = "#c9cadb";
const FUR_DARK = "#6d6e86";

const images = new Map<string, HTMLImageElement>();
/** A toy's silhouette, once it has loaded (the Tuna Tiles suit art). */
function silhouette(suit: Suit): HTMLImageElement | null {
  let img = images.get(suit);
  if (!img) {
    if (typeof Image === "undefined") return null;
    img = new Image();
    img.decoding = "async";
    img.src = art(`tile-${suit}`);
    images.set(suit, img);
  }
  return img.complete && img.naturalWidth > 0 ? img : null;
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** One plush cushion filling the cell at (px, py). */
export function cushion(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, suit: Suit, alpha = 1): void {
  const look = LOOKS[suit];
  const inset = Math.max(0.5, cell * 0.04);
  const s = cell - inset * 2;
  const r = s * 0.3;
  ctx.globalAlpha = alpha;
  const g = ctx.createLinearGradient(0, py, 0, py + cell);
  g.addColorStop(0, look.top);
  g.addColorStop(0.7, look.base);
  g.addColorStop(1, look.side);
  roundRect(ctx, px + inset, py + inset, s, s, r);
  ctx.fillStyle = g;
  ctx.fill();
  if (cell >= 8) {
    ctx.lineWidth = Math.max(1, cell * 0.06);
    ctx.strokeStyle = INK;
    ctx.stroke();
  }
  if (cell >= 14) {
    // The stitching, just inside the edge.
    roundRect(ctx, px + inset + cell * 0.12, py + inset + cell * 0.12, s - cell * 0.24, s - cell * 0.24, r * 0.6);
    ctx.setLineDash([cell * 0.09, cell * 0.07]);
    ctx.lineWidth = Math.max(1, cell * 0.035);
    ctx.strokeStyle = "rgba(255,255,255,0.7)";
    ctx.stroke();
    ctx.setLineDash([]);
    const img = silhouette(suit);
    if (img) {
      const is = cell * 0.5;
      ctx.globalAlpha = alpha * 0.4;
      ctx.drawImage(img, px + (cell - is) / 2, py + (cell - is) / 2, is, is);
    }
  }
  ctx.globalAlpha = 1;
}

/** A fluffy hairball filling the cell: round tufts of fur, never a block. */
export function hairball(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, scale = 1): void {
  const cx = px + cell / 2;
  const cy = py + cell / 2;
  const r = cell * 0.36 * scale;
  ctx.fillStyle = FUR_DARK;
  ctx.beginPath();
  ctx.arc(cx, cy + r * 0.15, r * 1.08, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = FUR;
  for (const [dx, dy, k] of [
    [-0.45, 0.1, 0.62],
    [0.45, 0.12, 0.6],
    [0, -0.35, 0.65],
    [0, 0.15, 0.8],
  ] as const) {
    ctx.beginPath();
    ctx.arc(cx + dx * r, cy + dy * r, r * k, 0, Math.PI * 2);
    ctx.fill();
  }
  if (cell >= 10) {
    ctx.fillStyle = FUR_LIGHT;
    ctx.beginPath();
    ctx.arc(cx - r * 0.25, cy - r * 0.35, r * 0.28, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** A trick's glowing badge, on the cell it sits on. */
function badge(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, trick: Trick): void {
  const cx = px + cell / 2;
  const cy = py + cell / 2;
  const r = cell * 0.3;
  ctx.save();
  ctx.shadowColor = "#fff6a8";
  ctx.shadowBlur = cell * 0.5;
  ctx.fillStyle = TRICK_COLOR[trick];
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  ctx.lineWidth = Math.max(1, cell * 0.07);
  ctx.strokeStyle = "#ffffff";
  ctx.stroke();
  // A four-point sparkle.
  const s = r * 0.7;
  ctx.fillStyle = "#ffffff";
  ctx.beginPath();
  ctx.moveTo(cx, cy - s);
  ctx.quadraticCurveTo(cx, cy, cx + s, cy);
  ctx.quadraticCurveTo(cx, cy, cx, cy + s);
  ctx.quadraticCurveTo(cx, cy, cx - s, cy);
  ctx.quadraticCurveTo(cx, cy, cx, cy - s);
  ctx.fill();
}

/** A paw print, faint, in the middle of a cell of the landing outline. */
function paw(ctx: CanvasRenderingContext2D, cx: number, cy: number, s: number): void {
  ctx.beginPath();
  ctx.ellipse(cx, cy + s * 0.18, s * 0.32, s * 0.26, 0, 0, Math.PI * 2);
  for (const [dx, dy] of [
    [-0.36, -0.2],
    [0, -0.36],
    [0.36, -0.2],
  ] as const) {
    ctx.moveTo(cx + dx * s + s * 0.13, cy + dy * s);
    ctx.arc(cx + dx * s, cy + dy * s, s * 0.13, 0, Math.PI * 2);
  }
  ctx.fill();
}

const cellY = (y: number, cell: number): number => (ROWS - 1 - y) * cell;

/** The box floor and every settled cell, for the offscreen copy. */
function drawSettled(ctx: CanvasRenderingContext2D, box: Pick<Box, "cells" | "tricks">, cell: number): void {
  const w = COLS * cell;
  const h = ROWS * cell;
  ctx.fillStyle = BOX_FLOOR;
  ctx.fillRect(0, 0, w, h);
  if (cell >= 10) {
    ctx.strokeStyle = BOX_LINE;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 1; x < COLS; x++) {
      ctx.moveTo(x * cell + 0.5, 0);
      ctx.lineTo(x * cell + 0.5, h);
    }
    ctx.stroke();
  }
  for (let y = 0; y < ROWS; y++) {
    for (let x = 0; x < W; x++) {
      const v = box.cells[y * W + x] ?? 0;
      if (v === 0) continue;
      const px = x * cell;
      const py = cellY(y, cell);
      if (v === JUNK) hairball(ctx, px, py, cell);
      else cushion(ctx, px, py, cell, TOY_SUIT[v - 1] ?? "fish");
      const t = box.tricks[y * W + x] ?? 0;
      if (t > 0 && cell >= 5) badge(ctx, px, py, cell, TRICKS[t - 1] as Trick);
    }
  }
}

export type PaintView = {
  box: Box;
  toy: { id: ToyId; rot: Rot; x: number; y: number } | null;
  landing: number;
  waiting: { rows: number; leftMs: number }[];
};

/**
 * One box's painter on one canvas, sized `COLS * cell` wide (plus the meter, when it has one) and
 * `ROWS * cell` high, at the device's pixel ratio.
 */
export class BoxPainter {
  private settled: HTMLCanvasElement | null = null;
  private key: { cells: number[] | null; tricks: number[] | null; cell: number; dpr: number } = { cells: null, tricks: null, cell: 0, dpr: 0 };
  private readonly ctx: CanvasRenderingContext2D | null;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.ctx = canvas.getContext?.("2d") ?? null;
  }

  /** Paints `v` (null: an empty box). `meter`: the junk meter's width to the right of the box, with a gap. */
  paint(v: PaintView | null, o: { cell: number; meter?: number; gap?: number; landing?: boolean; dpr?: number }): void {
    const ctx = this.ctx;
    if (!ctx) return;
    const dpr = o.dpr ?? (typeof devicePixelRatio === "number" ? devicePixelRatio : 1);
    const cell = o.cell;
    const bw = COLS * cell;
    const bh = ROWS * cell;
    const meterW = o.meter ?? 0;
    const gap = meterW > 0 ? (o.gap ?? 4) : 0;
    const cssW = bw + gap + meterW;
    const pw = Math.round(cssW * dpr);
    const ph = Math.round(bh * dpr);
    if (this.canvas.width !== pw || this.canvas.height !== ph) {
      this.canvas.width = pw;
      this.canvas.height = ph;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, bh);
    const box = v?.box ?? null;
    this.copySettled(ctx, box, cell, dpr);
    if (v?.toy && box && !box.out) {
      const suit = toySuit(v.toy.id);
      const cells = toyCells(v.toy.id, v.toy.rot);
      if (o.landing !== false && v.landing < v.toy.y && cell >= 6) {
        ctx.save();
        ctx.setLineDash([cell * 0.16, cell * 0.12]);
        ctx.lineWidth = Math.max(1, cell * 0.07);
        ctx.strokeStyle = "rgba(255,255,255,0.75)";
        ctx.fillStyle = "rgba(255,255,255,0.28)";
        for (const [cx, cy] of cells) {
          const y = v.landing + cy;
          if (y >= ROWS) continue;
          const px = (v.toy.x + cx) * cell;
          const py = cellY(y, cell);
          roundRect(ctx, px + cell * 0.1, py + cell * 0.1, cell * 0.8, cell * 0.8, cell * 0.24);
          ctx.stroke();
          if (cell >= 12) paw(ctx, px + cell / 2, py + cell / 2, cell * 0.5);
        }
        ctx.restore();
      }
      for (const [cx, cy] of cells) {
        const y = v.toy.y + cy;
        if (y >= ROWS + 0.999) continue;
        cushion(ctx, (v.toy.x + cx) * cell, cellY(y, cell), cell, suit);
      }
    }
    if (meterW > 0) this.meter(ctx, v?.waiting ?? [], bw + gap, meterW, bh);
  }

  private copySettled(ctx: CanvasRenderingContext2D, box: Box | null, cell: number, dpr: number): void {
    const cells = box?.cells ?? null;
    const tricks = box?.tricks ?? null;
    const k = this.key;
    if (!this.settled || k.cells !== cells || k.tricks !== tricks || k.cell !== cell || k.dpr !== dpr) {
      const off = this.settled ?? document.createElement("canvas");
      off.width = Math.round(COLS * cell * dpr);
      off.height = Math.round(ROWS * cell * dpr);
      const octx = off.getContext("2d");
      if (!octx) return;
      octx.setTransform(dpr, 0, 0, dpr, 0, 0);
      drawSettled(octx, box ?? { cells: [], tricks: [] }, cell);
      this.settled = off;
      this.key = { cells, tricks, cell, dpr };
    }
    ctx.drawImage(this.settled, 0, 0, COLS * cell, ROWS * cell);
  }

  /** Waiting junk, a hairball per row from the bottom up, each shrinking as its 2 seconds run out. */
  private meter(ctx: CanvasRenderingContext2D, waiting: { rows: number; leftMs: number }[], x: number, w: number, h: number): void {
    ctx.fillStyle = "rgba(27,10,60,0.55)";
    roundRect(ctx, x, 0, w, h, w / 2);
    ctx.fill();
    let y = h;
    for (const j of waiting) {
      const scale = 0.45 + 0.55 * Math.min(1, j.leftMs / 2000);
      for (let i = 0; i < j.rows && y >= w; i++) {
        hairball(ctx, x, y - w, w, scale);
        y -= w * 0.9;
      }
    }
  }
}

/** A toy on its own (the next one, on the cat's paw), centred in a `size` square. */
export function paintToy(canvas: HTMLCanvasElement, id: ToyId | null, size: number, dpr = typeof devicePixelRatio === "number" ? devicePixelRatio : 1): void {
  const ctx = canvas.getContext?.("2d");
  if (!ctx) return;
  const pw = Math.round(size * dpr);
  if (canvas.width !== pw || canvas.height !== pw) canvas.width = canvas.height = pw;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, size, size);
  if (!id) return;
  const cells = toyCells(id, 0);
  const xs = cells.map(([x]) => x);
  const ys = cells.map(([, y]) => y);
  const cw = Math.max(...xs) - Math.min(...xs) + 1;
  const ch = Math.max(...ys) - Math.min(...ys) + 1;
  const cell = Math.floor(size / Math.max(cw, ch, 3));
  const ox = (size - cw * cell) / 2;
  const oy = (size - ch * cell) / 2;
  const top = Math.max(...ys);
  for (const [x, y] of cells) cushion(ctx, ox + (x - Math.min(...xs)) * cell, oy + (top - y) * cell, cell, toySuit(id));
}
