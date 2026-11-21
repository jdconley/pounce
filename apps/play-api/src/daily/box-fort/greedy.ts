/**
 * A plain greedy player for tests, the golden vectors and the end-to-end tests: of the pieces
 * left, the placement that clears the most lines, then the first such spot (top-left first).
 */
import { place, SIZE } from "./rules";

import type { Piece } from "./pieces";

export type Place = { k: "place"; slot: number; row: number; col: number };

export function greedyMove(rug: readonly number[], pieces: readonly Piece[], placed: readonly boolean[]): Place | null {
  let best: { move: Place; lines: number } | null = null;
  for (const [slot, piece] of pieces.entries()) {
    if (placed[slot]) continue;
    for (let row = 0; row < SIZE; row++) {
      for (let col = 0; col < SIZE; col++) {
        const out = place(rug, piece, row, col);
        if (out === null) continue;
        const lines = out.cleared.rows.length + out.cleared.cols.length;
        if (best === null || lines > best.lines) best = { move: { k: "place", slot, row, col }, lines };
      }
    }
  }
  return best?.move ?? null;
}
