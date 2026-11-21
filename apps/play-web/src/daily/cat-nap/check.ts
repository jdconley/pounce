/** The rules' read of a board, for the views: clashes, whether every cat is in, and progress. */
import { catsPlaced, clashes, complete, type NapState, type Quilt } from "@pounce/play-api/daily/cat-nap/rules";

import type { Check } from "./quilt";

/** Microseconds on a 9 by 9 quilt (tests/cat-nap.test.ts measures it), so it runs where it's drawn. */
export function checkBoard(q: Quilt, s: NapState): Check {
  return { clashes: clashes(q, s), complete: complete(q, s), placed: catsPlaced(q, s) };
}
