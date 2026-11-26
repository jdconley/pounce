/**
 * The easel on a canvas (design §7), for the drawer's phone and the TV alike. Two layers: a bitmap
 * of the finished strokes, and a live layer for the stroke in progress, the only one redrawn as it
 * grows. A frame's cost stays flat however much is on the easel. Lines are smoothed with quadratic
 * curves through the midpoints of their points.
 *
 * When the bitmap has to be drawn again from scratch (an undo, a resize, a whole drawing arriving
 * at once), the raster worker draws it off the main thread and hands back an image; until then the
 * old bitmap stays up, and strokes finished meanwhile are drawn over the new one when it lands.
 */
import { COLOURS, EASEL_H, EASEL_W, WIDTHS, type Stroke } from "./purr-ink";

/** What a stroke needs from a 2D context: the page's canvas and the worker's OffscreenCanvas both have it. */
export type Pen = {
  beginPath(): void;
  moveTo(x: number, y: number): void;
  lineTo(x: number, y: number): void;
  quadraticCurveTo(cx: number, cy: number, x: number, y: number): void;
  arc(x: number, y: number, r: number, a0: number, a1: number): void;
  stroke(): void;
  fill(): void;
  lineWidth: number;
  lineCap: CanvasLineCap;
  lineJoin: CanvasLineJoin;
  strokeStyle: string | CanvasGradient | CanvasPattern;
  fillStyle: string | CanvasGradient | CanvasPattern;
};

export type Surface = Pen & {
  setTransform(a: number, b: number, c: number, d: number, e: number, f: number): void;
  clearRect(x: number, y: number, w: number, h: number): void;
  drawImage(image: CanvasImageSource, x: number, y: number): void;
};

/** One stroke, in grid units (the context is already scaled to the grid). */
export function traceStroke(pen: Pen, s: Stroke): void {
  const p = s.points;
  const n = p.length / 2;
  if (n === 0) return;
  const colour = COLOURS[s.colour] ?? COLOURS[0];
  const width = WIDTHS[s.width] ?? WIDTHS[0];
  if (n === 1) {
    pen.fillStyle = colour;
    pen.beginPath();
    pen.arc(p[0]!, p[1]!, width / 2, 0, Math.PI * 2);
    pen.fill();
    return;
  }
  pen.strokeStyle = colour;
  pen.lineWidth = width;
  pen.lineCap = "round";
  pen.lineJoin = "round";
  pen.beginPath();
  pen.moveTo(p[0]!, p[1]!);
  if (n === 2) {
    pen.lineTo(p[2]!, p[3]!);
  } else {
    // Through the midpoints: each point is the control of the curve between its neighbours' midpoints.
    for (let i = 1; i < n - 1; i++) {
      const x = p[i * 2]!;
      const y = p[i * 2 + 1]!;
      pen.quadraticCurveTo(x, y, (x + p[i * 2 + 2]!) / 2, (y + p[i * 2 + 3]!) / 2);
    }
    pen.lineTo(p[(n - 1) * 2]!, p[(n - 1) * 2 + 1]!);
  }
  pen.stroke();
}

/** Every stroke onto a cleared surface of `w` x `h` device pixels, `scale` device pixels per grid unit. */
export function paint(surface: Surface, strokes: readonly Stroke[], w: number, h: number, scale: number): void {
  surface.setTransform(1, 0, 0, 1, 0, 0);
  surface.clearRect(0, 0, w, h);
  surface.setTransform(scale, 0, 0, scale, 0, 0);
  for (const s of strokes) traceStroke(surface, s);
}

/** Draws strokes into an image off the main thread (the worker), or says it can't (null). */
export type Rasterizer = (strokes: readonly Stroke[], w: number, h: number, scale: number) => Promise<CanvasImageSource | null>;

/** What the easel shows: the finished strokes in order, and the one in progress. */
export type EaselSource = { finished: readonly Stroke[]; live: Stroke | null };

/** The easel's size in CSS pixels that fits a box, at 3:4. */
export function fitEasel(boxW: number, boxH: number): { width: number; height: number } {
  const width = Math.max(0, Math.min(boxW, (boxH * EASEL_W) / EASEL_H));
  return { width: Math.floor(width), height: Math.floor((width * EASEL_H) / EASEL_W) };
}

type Drawn = { stroke: Stroke; length: number };

export type EaselOptions = {
  base: Surface;
  live: Surface;
  /** Sets both canvases' pixel size (a canvas resized is cleared). */
  resize: (w: number, h: number) => void;
  raster?: Rasterizer;
  /** Next animation frame; tests run frames by hand. */
  request?: (fn: (t: number) => void) => number;
  cancel?: (id: number) => void;
};

export class Easel {
  /** Read every frame: the drawer's writer, or the TV's picture. */
  source: () => EaselSource = () => ({ finished: [], live: null });
  private w = 0;
  private h = 0;
  /** Device pixels per grid unit. */
  private scale = 1;
  /** The finished strokes the bitmap holds (or will, once a rebuild lands), with how many points each had. */
  private onBase: Drawn[] = [];
  private liveShown: { stroke: Stroke | null; length: number; colour: number; width: number } = { stroke: null, length: 0, colour: -1, width: -1 };
  private gen = 0;
  /** A rebuild in flight: how many of `onBase` it covers. */
  private rebuilding: { gen: number; covers: number } | null = null;
  private frame: number | null = null;
  private stopped = false;
  private readonly request: (fn: (t: number) => void) => number;
  private readonly cancel: (id: number) => void;

  constructor(private readonly o: EaselOptions) {
    this.request = o.request ?? ((fn) => requestAnimationFrame(fn));
    this.cancel = o.cancel ?? ((id) => cancelAnimationFrame(id));
  }

  /** The easel's CSS size and the screen's pixel ratio. A new size draws the bitmap again. */
  setSize(cssW: number, cssH: number, dpr: number): void {
    const w = Math.max(1, Math.round(cssW * dpr));
    const h = Math.max(1, Math.round(cssH * dpr));
    if (w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    this.scale = w / EASEL_W;
    this.o.resize(w, h);
    this.liveShown = { stroke: null, length: 0, colour: -1, width: -1 };
    this.rebuild(this.source().finished);
    this.invalidate();
  }

  /** Something changed: draw it on the next frame (once, however many changes come before it). */
  invalidate(): void {
    if (this.frame !== null || this.stopped || this.w === 0) return;
    this.frame = this.request(() => {
      this.frame = null;
      this.draw();
    });
  }

  stop(): void {
    this.stopped = true;
    if (this.frame !== null) this.cancel(this.frame);
    this.frame = null;
  }

  /** One frame: new finished strokes onto the bitmap (or a rebuild), and the live stroke. */
  draw(): void {
    if (this.w === 0) return;
    const { finished, live } = this.source();
    if (!this.prefixHolds(finished)) this.rebuild(finished);
    else if (finished.length > this.onBase.length) {
      const base = this.o.base;
      base.setTransform(this.scale, 0, 0, this.scale, 0, 0);
      for (let i = this.onBase.length; i < finished.length; i++) {
        const stroke = finished[i]!;
        traceStroke(base, stroke);
        this.onBase.push({ stroke, length: stroke.points.length });
      }
    }
    const shown = this.liveShown;
    const length = live?.points.length ?? 0;
    if (shown.stroke !== live || shown.length !== length || (live && (shown.colour !== live.colour || shown.width !== live.width))) {
      const layer = this.o.live;
      layer.setTransform(1, 0, 0, 1, 0, 0);
      layer.clearRect(0, 0, this.w, this.h);
      if (live) {
        layer.setTransform(this.scale, 0, 0, this.scale, 0, 0);
        traceStroke(layer, live);
      }
      this.liveShown = { stroke: live, length, colour: live?.colour ?? -1, width: live?.width ?? -1 };
    }
  }

  /** The bitmap still shows the start of `finished`, unchanged. */
  private prefixHolds(finished: readonly Stroke[]): boolean {
    if (finished.length < this.onBase.length) return false;
    for (let i = 0; i < this.onBase.length; i++) {
      const d = this.onBase[i]!;
      if (finished[i] !== d.stroke || d.stroke.points.length !== d.length) return false;
    }
    return true;
  }

  /** The bitmap from scratch: cleared at once when empty, else rastered off the main thread. */
  private rebuild(finished: readonly Stroke[]): void {
    const gen = ++this.gen;
    this.onBase = finished.map((stroke) => ({ stroke, length: stroke.points.length }));
    if (finished.length === 0 || !this.o.raster) {
      this.rebuilding = null;
      paint(this.o.base, finished, this.w, this.h, this.scale);
      return;
    }
    this.rebuilding = { gen, covers: finished.length };
    const copy = finished.map((s) => ({ ...s, points: s.points.slice() }));
    const [w, h, scale] = [this.w, this.h, this.scale];
    void this.o.raster(copy, w, h, scale).then((image) => {
      if (this.stopped || gen !== this.gen || w !== this.w || h !== this.h) return;
      const covers = this.rebuilding?.covers ?? 0;
      this.rebuilding = null;
      const base = this.o.base;
      if (!image) {
        paint(base, this.onBase.map((d) => d.stroke), this.w, this.h, this.scale);
        return;
      }
      base.setTransform(1, 0, 0, 1, 0, 0);
      base.clearRect(0, 0, this.w, this.h);
      base.drawImage(image, 0, 0);
      // Strokes finished while it was drawn go on top.
      base.setTransform(this.scale, 0, 0, this.scale, 0, 0);
      for (let i = covers; i < this.onBase.length; i++) traceStroke(base, this.onBase[i]!.stroke);
      (image as { close?: () => void }).close?.();
    });
  }
}
