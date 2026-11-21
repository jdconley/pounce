/**
 * Box Fort's drawing, shared by the play screen and the TV's watch view, the same as the app's
 * `BoxFortArt`: a woven rug with a fringe, toy boxes in loud paint with packing tape, and cats
 * napping in the boxes that were there first. All of it on a 2D canvas, so a rug is one layer.
 */
import type { Piece } from "@pounce/play-api/daily/box-fort/pieces";

const INK = "#1b0b3a";
const CLUTTER = 7;
const PAINT: Record<number, string> = { 1: "#ff2e9a", 2: "#00d1c1", 3: "#ff8a00", 4: "#2eb8ff", 5: "#9be22e", 6: "#ffd21f", 7: "#b57bff" };
const COATS = ["#ff9a3c", "#a7b0c8", "#ffffff", "#4b3a78"];

export const paint = (tint: number): string => PAINT[tint] ?? PAINT[CLUTTER]!;

/** A cat looks out of about one box in nine, fixed by its spot and paint. */
export const peeks = (index: number, tint: number): boolean => tint !== CLUTTER && (index * 5 + tint * 3) % 9 === 0;

/** A canvas sized to `w` by `h` CSS pixels, sharp on the screen's pixel ratio. */
export function sizeCanvas(canvas: HTMLCanvasElement, w: number, h: number): CanvasRenderingContext2D {
  const dpr = Math.min(3, window.devicePixelRatio || 1);
  const pw = Math.round(w * dpr);
  const ph = Math.round(h * dpr);
  if (canvas.width !== pw || canvas.height !== ph) {
    canvas.width = pw;
    canvas.height = ph;
  }
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  const ctx = canvas.getContext("2d") as CanvasRenderingContext2D;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  return ctx;
}

/** The rug under the 8 by 8 spots starting at (`x`, `y`). */
export function drawRug(ctx: CanvasRenderingContext2D, x: number, y: number, cell: number): void {
  const side = cell * 8;
  const border = cell * 0.22;
  const ox = x - border;
  const oy = y - border;
  const ow = side + 2 * border;
  const tassels = 18;
  const step = ow / tassels;
  ctx.fillStyle = "#ffd21f";
  ctx.strokeStyle = INK;
  ctx.lineWidth = Math.max(1, cell * 0.035);
  for (let i = 0; i < tassels; i++) {
    const tx = ox + (i + 0.5) * step;
    const w = step * 0.36;
    const h = cell * 0.36;
    for (const ty of [oy - cell * 0.26, oy + ow - cell * 0.1]) {
      ctx.beginPath();
      ctx.roundRect(tx - w / 2, ty, w, h, w / 2);
      ctx.fill();
      ctx.stroke();
    }
  }
  ctx.beginPath();
  ctx.roundRect(ox, oy, ow, ow, cell * 0.3);
  ctx.fillStyle = "#ff2e9a";
  ctx.fill();
  ctx.lineWidth = Math.max(2, cell * 0.08);
  ctx.stroke();
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(x, y, side, side, cell * 0.12);
  ctx.clip();
  ctx.fillStyle = "#3b1680";
  ctx.fillRect(x, y, side, side);
  ctx.fillStyle = "#4a1f9c";
  for (let r = 0; r < 8; r++) for (let c = r % 2; c < 8; c += 2) ctx.fillRect(x + c * cell, y + r * cell, cell, cell);
  ctx.restore();
}

/** One box in the spot at (`x`, `y`), `s` wide. */
export function drawBox(ctx: CanvasRenderingContext2D, x: number, y: number, s: number, tint: number, peek = false, coat = 0): void {
  const inset = s * 0.045;
  const rx = x + inset;
  const ry = y + inset;
  const rs = s - 2 * inset;
  const line = Math.max(1.5, s * 0.07);
  const color = paint(tint);
  const napping = tint === CLUTTER;
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(rx, ry, rs, rs, s * 0.14);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.clip();
  if (!napping && !peek) {
    ctx.fillStyle = "rgba(27, 11, 58, 0.22)";
    ctx.fillRect(rx, ry + rs * 0.76, rs, rs * 0.24);
    ctx.fillStyle = "rgba(255, 255, 255, 0.32)";
    ctx.fillRect(rx, ry, rs, rs * 0.2);
    ctx.fillStyle = "rgba(255, 255, 255, 0.5)";
    ctx.fillRect(rx + rs * 0.41, ry, rs * 0.18, rs * 0.56);
  } else {
    ctx.fillStyle = "rgba(27, 11, 58, 0.45)";
    ctx.fillRect(rx, ry, rs, rs);
    drawCat(ctx, rx, ry, rs, COATS[coat % COATS.length]!, !napping, line * 0.8);
    const fy = ry + rs * 0.62;
    ctx.fillStyle = color;
    ctx.fillRect(rx, fy, rs, rs * 0.38);
    ctx.fillStyle = "rgba(255, 255, 255, 0.3)";
    ctx.fillRect(rx, fy, rs, rs * 0.38 * 0.28);
    ctx.beginPath();
    ctx.moveTo(rx, fy);
    ctx.lineTo(rx + rs, fy);
    ctx.strokeStyle = INK;
    ctx.lineWidth = line * 0.8;
    ctx.stroke();
  }
  ctx.restore();
  ctx.beginPath();
  ctx.roundRect(rx, ry, rs, rs, s * 0.14);
  ctx.strokeStyle = INK;
  ctx.lineWidth = line;
  ctx.stroke();
}

/** A cat's head rising out of a box: outlined as one shape (strokes first, fills over them). */
function drawCat(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, coat: string, awake: boolean, line: number): void {
  const cx = x + w / 2;
  const cy = y + w * 0.47;
  const radius = w * 0.29;
  const shape = new Path2D();
  shape.ellipse(cx, cy, radius, radius * 0.9, 0, 0, Math.PI * 2);
  for (const dir of [-1, 1]) {
    const ear = new Path2D();
    ear.moveTo(cx + dir * radius * 0.98, cy - radius * 0.05);
    ear.lineTo(cx + dir * radius * 0.9, cy - radius * 1.35);
    ear.lineTo(cx + dir * radius * 0.15, cy - radius * 0.7);
    ear.closePath();
    shape.addPath(ear);
  }
  ctx.strokeStyle = INK;
  ctx.lineWidth = line * 2;
  ctx.lineJoin = "round";
  ctx.stroke(shape);
  ctx.fillStyle = coat;
  ctx.fill(shape, "nonzero");
  const eyeY = cy - radius * 0.12;
  const eye = coat === COATS[3] ? "#ffffff" : INK;
  for (const dx of [-0.42, 0.42]) {
    const ex = cx + dx * radius;
    if (awake) {
      ctx.beginPath();
      ctx.ellipse(ex, eyeY, w * 0.06, w * 0.075, 0, 0, Math.PI * 2);
      ctx.fillStyle = eye;
      ctx.fill();
    } else {
      ctx.beginPath();
      ctx.moveTo(ex - w * 0.08, eyeY);
      ctx.quadraticCurveTo(ex, eyeY + w * 0.08, ex + w * 0.08, eyeY);
      ctx.strokeStyle = eye;
      ctx.lineWidth = Math.max(1, w * 0.05);
      ctx.lineCap = "round";
      ctx.stroke();
    }
  }
}

/** Every box on `rug`, its spots starting at (`x`, `y`). */
export function drawBoxes(ctx: CanvasRenderingContext2D, rug: readonly number[], x: number, y: number, cell: number): void {
  rug.forEach((tint, i) => {
    if (tint !== 0) drawBox(ctx, x + (i % 8) * cell, y + Math.floor(i / 8) * cell, cell, tint, peeks(i, tint), i * 3 + tint);
  });
}

export function drawPiece(ctx: CanvasRenderingContext2D, piece: Piece, x: number, y: number, cell: number): void {
  for (const [r, c] of piece.cells) drawBox(ctx, x + c * cell, y + r * cell, cell, piece.tint);
}
