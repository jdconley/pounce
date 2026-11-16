/// <reference lib="webworker" />
/**
 * The Tuna Tiles hint, off the rendering thread (docs/main-thread.md): the House Cat's own move
 * search (play-api `bots/house-cat-tiles`) for this device's view of the table. It can look at
 * many arrangements, so it never runs where a frame is drawn.
 */
import { chooseAction } from "@pounce/play-api/bots/house-cat-tiles";
import { createRng } from "@pounce/play-api/rules/rng";

import type { HintRequest, HintAnswer } from "./hint";

const scope = self as unknown as DedicatedWorkerGlobalScope;

scope.onmessage = (e: MessageEvent<HintRequest>) => {
  const { id, view, seat, seed } = e.data;
  let answer: HintAnswer;
  try {
    answer = { id, action: chooseAction(view, seat, createRng(seed)) };
  } catch {
    answer = { id, action: null };
  }
  scope.postMessage(answer);
};
