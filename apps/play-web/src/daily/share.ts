/**
 * Sharing a daily result (spec §7 "Share"): a card image, the text "Sniff 12: 4 of 6" and the
 * Dish's link. The image is drawn and encoded in a Web Worker on an OffscreenCanvas
 * (`workers/share-card.worker.ts`), never on the rendering thread. Web Share where the browser has
 * it (with the image when it can share files), else the text and link are copied.
 *
 * Kittens never share: the caller doesn't offer it (no links out from an under-13's device).
 */
import { puzzleName, shareText, SHARE_URL } from "./format";

import type { ShareGrid } from "./host";
import type { DailyResult } from "@pounce/play-api/daily/module";

/** What the worker draws. Plain values only. */
export type CardRequest = {
  id: number;
  /** "Sniff 12", or "Sniff" before launch day (`puzzleName`). */
  title: string;
  words: string;
  hints: number;
  color: string;
  deep: string;
  grid: ShareGrid | null;
  font: string;
};
export type CardAnswer = { id: number; png: Blob | null };

/** The card's layout: 1080 square, the grid's cells as big as fit under the words. */
export function cardLayout(grid: ShareGrid | null): { cell: number; gap: number; top: number; left: number[] } {
  const rows = grid?.length ?? 0;
  const cols = Math.max(0, ...(grid ?? []).map((r) => r.length));
  if (rows === 0 || cols === 0) return { cell: 0, gap: 0, top: 0, left: [] };
  const gap = 14;
  const cell = Math.floor(Math.min((760 - gap * (cols - 1)) / cols, (440 - gap * (rows - 1)) / rows, 110));
  const width = cols * cell + (cols - 1) * gap;
  const top = 500 + Math.max(0, (440 - (rows * cell + (rows - 1) * gap)) / 2);
  return { cell, gap, top, left: Array.from({ length: cols }, (_, c) => (1080 - width) / 2 + c * (cell + gap)) };
}

let worker: Worker | null = null;
let next = 0;
const waiting = new Map<number, (png: Blob | null) => void>();

/** The card as a PNG, drawn off the rendering thread; null where the browser can't (no OffscreenCanvas). */
export function renderCard(card: Omit<CardRequest, "id" | "font" | "title"> & { title: string; number: number }): Promise<Blob | null> {
  if (typeof Worker === "undefined" || typeof OffscreenCanvas === "undefined") return Promise.resolve(null);
  if (!worker) {
    worker = new Worker(new URL("../workers/share-card.worker.ts", import.meta.url), { type: "module", name: "share-card" });
    worker.onmessage = (e: MessageEvent<CardAnswer>) => {
      waiting.get(e.data.id)?.(e.data.png);
      waiting.delete(e.data.id);
    };
    worker.onerror = () => {
      for (const done of waiting.values()) done(null);
      waiting.clear();
    };
  }
  const id = ++next;
  const font = new URL("@fontsource/nunito/files/nunito-latin-900-normal.woff2", import.meta.url).href;
  return new Promise((resolve) => {
    waiting.set(id, resolve);
    const { number, ...rest } = card;
    worker!.postMessage({ ...rest, title: puzzleName(card.title, number), id, font } satisfies CardRequest);
  });
}

export type ShareNav = Pick<Navigator, "share" | "canShare" | "clipboard">;

/**
 * Shares `result` with its card when `png` is given: "shared", "copied", or "cancelled" (the
 * person closed the share sheet), or "failed".
 */
export async function shareResult(
  title: string,
  result: DailyResult,
  png: Blob | null,
  nav: Partial<ShareNav> = typeof navigator === "undefined" ? {} : navigator,
): Promise<"shared" | "copied" | "cancelled" | "failed"> {
  const text = shareText(title, result);
  if (typeof nav.share === "function") {
    const file = png ? new File([png], `${puzzleName(title, result.number).toLowerCase().replace(/\s+/g, "-")}.png`, { type: "image/png" }) : null;
    const withFile = file && typeof nav.canShare === "function" && nav.canShare({ files: [file] }) ? { files: [file] } : {};
    try {
      await nav.share({ text, url: SHARE_URL, ...withFile });
      return "shared";
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return "cancelled";
      // Fall through to copying.
    }
  }
  try {
    await nav.clipboard?.writeText(`${text} ${SHARE_URL}`);
    return nav.clipboard ? "copied" : "failed";
  } catch {
    return "failed";
  }
}
