/// <reference lib="webworker" />
/**
 * The Daily Dish's share card, off the rendering thread (docs/main-thread.md): drawn on an
 * OffscreenCanvas and encoded to PNG here. It shows the game, its number, the result and a grid of
 * marks that gives nothing away (no letters, no cells), with the Dish's address.
 */
import { cardLayout, type CardAnswer, type CardRequest } from "../daily/share";

const scope = self as unknown as DedicatedWorkerGlobalScope & { fonts?: FontFaceSet };
const INK = "#1b0b3a";
let fontReady: Promise<string> | null = null;

function loadFont(url: string): Promise<string> {
  fontReady ??= (async () => {
    try {
      const face = new FontFace("Nunito", `url(${url})`, { weight: "900" });
      await face.load();
      scope.fonts?.add(face);
      return "Nunito";
    } catch {
      return "sans-serif";
    }
  })();
  return fontReady;
}

/** One mark: a filled paw on yellow, an outlined paw on white, or a plain tile (never color alone). */
function paw(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number, s: number, mark: "full" | "half" | "none"): void {
  ctx.lineWidth = Math.max(3, s * 0.06);
  ctx.strokeStyle = INK;
  ctx.fillStyle = mark === "full" ? "#ffd21f" : mark === "half" ? "#fff" : "rgba(255,255,255,0.22)";
  ctx.beginPath();
  ctx.roundRect(x, y, s, s, s * 0.22);
  ctx.fill();
  ctx.stroke();
  if (mark === "none") return;
  const cx = x + s / 2;
  const cy = y + s / 2;
  const shapes: [number, number, number, number][] = [
    [0, 0.12, 0.17, 0.14],
    [-0.22, -0.06, 0.07, 0.085],
    [-0.08, -0.2, 0.07, 0.085],
    [0.08, -0.2, 0.07, 0.085],
    [0.22, -0.06, 0.07, 0.085],
  ];
  ctx.fillStyle = INK;
  ctx.lineWidth = Math.max(2, s * 0.045);
  for (const [dx, dy, rx, ry] of shapes) {
    ctx.beginPath();
    ctx.ellipse(cx + dx * s, cy + dy * s, rx * s, ry * s, 0, 0, Math.PI * 2);
    if (mark === "full") ctx.fill();
    else ctx.stroke();
  }
}

async function draw(req: CardRequest): Promise<Blob> {
  const family = await loadFont(req.font);
  const canvas = new OffscreenCanvas(1080, 1080);
  const ctx = canvas.getContext("2d") as OffscreenCanvasRenderingContext2D;
  const bg = ctx.createLinearGradient(0, 0, 0, 1080);
  bg.addColorStop(0, req.color);
  bg.addColorStop(1, req.deep);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 1080, 1080);
  // A sunburst of soft rays behind the words.
  ctx.save();
  ctx.translate(540, 300);
  ctx.fillStyle = "rgba(255,255,255,0.08)";
  for (let i = 0; i < 16; i++) {
    ctx.rotate(Math.PI / 8);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(-90, -900);
    ctx.lineTo(90, -900);
    ctx.fill();
  }
  ctx.restore();
  ctx.lineWidth = 16;
  ctx.strokeStyle = INK;
  ctx.strokeRect(8, 8, 1064, 1064);

  const outlined = (text: string, y: number, size: number) => {
    ctx.font = `900 ${size}px ${family}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineJoin = "round";
    ctx.lineWidth = size * 0.2;
    ctx.strokeStyle = INK;
    ctx.strokeText(text, 540, y, 980);
    ctx.fillStyle = "#fff";
    ctx.fillText(text, 540, y, 980);
  };
  outlined(`${req.title} ${req.number}`, 150, 110);
  outlined(req.words, 320, req.words.length > 12 ? 120 : 170);
  if (req.hints > 0) outlined(req.hints === 1 ? "1 hint" : `${req.hints} hints`, 440, 60);

  const layout = cardLayout(req.grid);
  req.grid?.forEach((row, r) =>
    row.forEach((mark, c) => paw(ctx, layout.left[c] as number, layout.top + r * (layout.cell + layout.gap), layout.cell, mark)),
  );

  ctx.font = `900 48px ${family}`;
  ctx.textAlign = "center";
  ctx.fillStyle = "#fff";
  ctx.lineWidth = 10;
  ctx.strokeStyle = INK;
  ctx.strokeText("play.conleychaos.com/daily", 540, 1010);
  ctx.fillText("play.conleychaos.com/daily", 540, 1010);
  return canvas.convertToBlob({ type: "image/png" });
}

scope.onmessage = async (e: MessageEvent<CardRequest>) => {
  let answer: CardAnswer;
  try {
    answer = { id: e.data.id, png: await draw(e.data) };
  } catch {
    answer = { id: e.data.id, png: null };
  }
  scope.postMessage(answer);
};
