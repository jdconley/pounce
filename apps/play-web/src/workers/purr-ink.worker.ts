/// <reference lib="webworker" />
/**
 * Purrtrait's easel, drawn off the rendering thread (docs/main-thread.md): a whole drawing
 * rastered into an image (an undo, a resize), and a whole turn's ink (`inkSync`) decoded into
 * strokes and rastered at once. The page gets plain strokes and an ImageBitmap back.
 */
import { paint } from "../table/purr-easel";
import { Picture } from "../table/purr-ink";

import type { InkRequest, InkAnswer } from "./purr-ink";

const scope = self as unknown as DedicatedWorkerGlobalScope;

function raster(strokes: Parameters<typeof paint>[1], w: number, h: number, scale: number): ImageBitmap | null {
  if (typeof OffscreenCanvas === "undefined") return null;
  const canvas = new OffscreenCanvas(w, h);
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;
  paint(ctx, strokes, w, h, scale);
  return canvas.transferToImageBitmap();
}

scope.onmessage = (e: MessageEvent<InkRequest>) => {
  const r = e.data;
  let answer: InkAnswer;
  try {
    if (r.kind === "raster") {
      answer = { id: r.id, image: raster(r.strokes, r.w, r.h, r.scale) };
    } else {
      const picture = new Picture();
      picture.applyAll(r.ops);
      answer = { id: r.id, image: r.w > 0 ? raster(picture.strokes, r.w, r.h, r.scale) : null, strokes: picture.strokes, lastId: picture.lastId };
    }
  } catch {
    answer = { id: r.id, image: null };
  }
  scope.postMessage(answer, answer.image ? [answer.image] : []);
};
