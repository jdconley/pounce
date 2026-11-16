/**
 * Asks the hint worker (hint.worker.ts) for a move, so the search never runs on the rendering
 * thread. One worker, made the first time a hint is asked for.
 */
import type { Seed } from "@pounce/play-api/rules/rng";
import type { TilesAction } from "@pounce/play-api/tiles/engine";
import type { TilesView } from "@pounce/play-api/tiles/view";

export type HintRequest = { id: number; view: TilesView; seat: number; seed: Seed };
export type HintAnswer = { id: number; action: TilesAction | null };

let worker: Worker | null = null;
let next = 0;
const waiting = new Map<number, (a: TilesAction | null) => void>();

export function hint(view: TilesView, seat: number): Promise<TilesAction | null> {
  if (!worker) {
    worker = new Worker(new URL("./hint.worker.ts", import.meta.url), { type: "module", name: "hint" });
    worker.onmessage = (e: MessageEvent<HintAnswer>) => {
      waiting.get(e.data.id)?.(e.data.action);
      waiting.delete(e.data.id);
    };
    worker.onerror = () => {
      for (const done of waiting.values()) done(null);
      waiting.clear();
    };
  }
  const id = ++next;
  const seed: Seed = [id, seat + 1, view.turns + 1, (performance.timeOrigin + performance.now()) >>> 0];
  return new Promise((resolve) => {
    waiting.set(id, resolve);
    worker!.postMessage({ id, view, seat, seed } satisfies HintRequest);
  });
}
