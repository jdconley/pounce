/**
 * Asks the ink worker (purr-ink.worker.ts) to raster a drawing or replay a whole turn's ink, so
 * neither runs on the rendering thread. One worker, made the first time it is needed. Where a
 * browser has no OffscreenCanvas, `raster` answers null and the easel draws on the page instead.
 */
import { Picture, type InkOp, type Stroke } from "../table/purr-ink";

export type InkRequest =
  | { id: number; kind: "raster"; strokes: readonly Stroke[]; w: number; h: number; scale: number }
  | { id: number; kind: "replay"; ops: readonly InkOp[]; w: number; h: number; scale: number };
export type InkAnswer = { id: number; image: ImageBitmap | null; strokes?: Stroke[]; lastId?: number };

let worker: Worker | null = null;
let broken = false;
let next = 0;
const waiting = new Map<number, (a: InkAnswer) => void>();

const canWork = (): boolean => !broken && typeof Worker !== "undefined" && typeof OffscreenCanvas !== "undefined";

function ask(request: InkRequest): Promise<InkAnswer> {
  if (!worker) {
    worker = new Worker(new URL("./purr-ink.worker.ts", import.meta.url), { type: "module", name: "purr-ink" });
    worker.onmessage = (e: MessageEvent<InkAnswer>) => {
      waiting.get(e.data.id)?.(e.data);
      waiting.delete(e.data.id);
    };
    worker.onerror = () => {
      broken = true;
      for (const [id, done] of waiting) done({ id, image: null });
      waiting.clear();
    };
  }
  return new Promise((resolve) => {
    waiting.set(request.id, resolve);
    worker!.postMessage(request);
  });
}

/** The strokes as an image `w` x `h` device pixels, or null (no worker here: draw on the page). */
export async function rasterInk(strokes: readonly Stroke[], w: number, h: number, scale: number): Promise<ImageBitmap | null> {
  if (!canWork()) return null;
  return (await ask({ id: ++next, kind: "raster", strokes, w, h, scale })).image;
}

/**
 * A whole turn's ink decoded into strokes (and, given a size, rastered too). Without a worker it is
 * decoded here: a browser that old gets the same picture, a little later in its frame.
 */
export async function replayInk(ops: readonly InkOp[], w = 0, h = 0, scale = 1): Promise<{ strokes: Stroke[]; lastId: number; image: ImageBitmap | null }> {
  if (canWork()) {
    const a = await ask({ id: ++next, kind: "replay", ops, w, h, scale });
    if (a.strokes) return { strokes: a.strokes, lastId: a.lastId ?? -1, image: a.image };
  }
  const picture = new Picture();
  picture.applyAll(ops);
  return { strokes: picture.strokes, lastId: picture.lastId, image: null };
}
