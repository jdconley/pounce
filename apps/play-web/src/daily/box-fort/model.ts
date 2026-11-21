/**
 * Box Fort's play state in the browser: each placement shows at once with the server's own rules
 * (`@pounce/play-api/daily/box-fort/rules`), goes to the run, and the next set waits for the
 * server to deal it. Plain values in, plain values out; the screen keeps the latest one.
 *
 * A placement checks one spot and a "does anything fit" is a few thousand cell checks, far under
 * a millisecond, so nothing here needs a worker.
 */
import { anyFits, deal, start, step } from "@pounce/play-api/daily/box-fort/rules";

import type { BoxFortPublicPuzzle, BoxFortPublicState, BoxFortReveal } from "@pounce/play-api/daily/box-fort/module";

export type Burst = { id: number; boxes: [index: number, tint: number][]; lines: number };
export type Gain = { id: number; points: number; at: { x: number; y: number }; combo: number };

export type Play = {
  state: BoxFortPublicState;
  /** The set is placed and the next one is on its way from the server. */
  waiting: boolean;
  /** Which tray pieces fit anywhere; a stuck one dims. */
  fits: boolean[];
  burst: Burst | null;
  gain: Gain | null;
  /** Counts the sets dealt, so the tray can bounce a new one in. */
  dealt: number;
  /** Counts placements, for the animations' ids. */
  count: number;
};

export function fitsBySlot(s: BoxFortPublicState): boolean[] {
  return s.placed.map((placed, i) => placed || anyFits(s.rug, [s.pieces[i]!]));
}

export function startPlay(puzzle: BoxFortPublicPuzzle): Play {
  const state = { ...start(puzzle.rug, puzzle.sets), pieces: puzzle.pieces };
  return { state, waiting: false, fits: fitsBySlot(state), burst: null, gain: null, dealt: 0, count: 0 };
}

/** The piece in `slot` placed at (`row`, `col`), or null when it can't go there now. */
export function placePiece(p: Play, slot: number, row: number, col: number): Play | null {
  if (p.waiting || !p.state.pieces[slot]) return null;
  const piece = p.state.pieces[slot];
  const out = step(p.state, p.state.pieces, slot, row, col);
  if (out === null) return null;
  const count = p.count + 1;
  let state: BoxFortPublicState = { ...out.state, pieces: p.state.pieces };
  let waiting = false;
  if (out.setDone) {
    if (state.set + 1 === state.sets) state = { ...deal(state, null), pieces: state.pieces };
    else waiting = true;
  }
  const lines = out.cleared.rows.length + out.cleared.cols.length;
  let burst = p.burst;
  if (lines > 0) {
    // The boxes as they were the moment the piece landed, before the lines went.
    const landed = [...p.state.rug];
    for (const [r, c] of piece.cells) landed[(row + r) * 8 + col + c] = piece.tint;
    const spots = new Set<number>();
    for (const r of out.cleared.rows) for (let c = 0; c < 8; c++) spots.add(r * 8 + c);
    for (const c of out.cleared.cols) for (let r = 0; r < 8; r++) spots.add(r * 8 + c);
    burst = { id: count, boxes: [...spots].map((i) => [i, landed[i]!]), lines };
  }
  const rows = Math.max(...piece.cells.map(([r]) => r)) + 1;
  const cols = Math.max(...piece.cells.map(([, c]) => c)) + 1;
  return {
    state,
    waiting,
    fits: fitsBySlot(state),
    burst,
    gain: { id: count, points: state.points - p.state.points, at: { x: col + cols / 2, y: row + rows / 2 }, combo: state.combo },
    dealt: p.dealt,
    count,
  };
}

/** The server dealt the next set. Anything else (a late or repeated reveal) changes nothing. */
export function receiveReveal(p: Play, reveal: BoxFortReveal): Play {
  if (!p.waiting || reveal.set !== p.state.set + 1) return p;
  const state = { ...deal(p.state, reveal.pieces), pieces: reveal.pieces };
  return { ...p, state, waiting: false, fits: fitsBySlot(state), dealt: p.dealt + 1 };
}

/** The server's own state (a resume, or a correction): it wins. */
export function resync(p: Play, state: BoxFortPublicState): Play {
  return { ...p, state, waiting: false, fits: fitsBySlot(state) };
}
