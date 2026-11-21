/**
 * A Cat Nap board as a player works it, as plain values: the marks so far and a drag in progress.
 * The same input as the app's `NapPlay`: a tap cycles a cell; a drag from an empty cell marks
 * "no cat" on every empty cell it crosses, one from a "no cat" clears them; cats and hinted cats
 * are never touched by a drag. Every change is a move for the server, which applies the same rules.
 */
import {
  applyHint,
  applyMark,
  dragMove,
  dragPaint,
  emptyState,
  tapMove,
  type NapMove,
  type NapState,
  type Quilt,
} from "@pounce/play-api/daily/cat-nap/rules";

export type NapPlay = { quilt: Quilt; state: NapState; drag: { paint: "x" | "clear"; passed: number[] } | null };
export type Out = { play: NapPlay; move: NapMove | null };

const inside = (p: NapPlay, cell: number) => Number.isInteger(cell) && cell >= 0 && cell < p.quilt.n * p.quilt.n;

export function start(quilt: Quilt, state?: NapState): NapPlay {
  return { quilt, state: state ?? emptyState(quilt), drag: null };
}

/** The board to draw: the marks, with a drag in progress painted on. */
export function shown(p: NapPlay): NapState {
  const m = p.drag && dragMove(p.state, p.drag.paint, p.drag.passed);
  return (m && applyMark(p.quilt, p.state, m)) ?? p.state;
}

export function tap(p: NapPlay, cell: number): Out {
  const m = !p.drag && inside(p, cell) ? tapMove(p.state, cell) : null;
  const next = m && applyMark(p.quilt, p.state, m);
  return next ? { play: { ...p, state: next }, move: m } : { play: p, move: null };
}

/** A drag starting at `cell`, or null when none can start there (a cat, a hinted cat, off the quilt). */
export function begin(p: NapPlay, cell: number): NapPlay | null {
  const paint = inside(p, cell) ? dragPaint(p.state, cell) : null;
  return paint ? { ...p, drag: { paint, passed: [cell] } } : null;
}

/** The drag crossed `cells`, in order. */
export function move(p: NapPlay, cells: number[]): NapPlay {
  if (!p.drag) return p;
  const fresh = cells.filter((c) => inside(p, c) && !p.drag!.passed.includes(c));
  return fresh.length ? { ...p, drag: { ...p.drag, passed: [...p.drag.passed, ...new Set(fresh)] } } : p;
}

export function end(p: NapPlay): Out {
  if (!p.drag) return { play: p, move: null };
  const m = dragMove(p.state, p.drag.paint, p.drag.passed);
  const next = m && applyMark(p.quilt, p.state, m);
  return { play: { ...p, state: next ?? p.state, drag: null }, move: next ? m : null };
}

export function cancel(p: NapPlay): NapPlay {
  return { ...p, drag: null };
}

/** The server's hint: its cat locked at `cell`. */
export function hint(p: NapPlay, cell: number): NapPlay {
  return inside(p, cell) ? { ...p, state: applyHint(p.quilt, p.state, cell) } : p;
}

/** The server's board (a resumed run): it replaces ours. */
export function load(p: NapPlay, server: NapState): NapPlay {
  return server.cells.length === p.quilt.n * p.quilt.n ? { ...p, state: server, drag: null } : p;
}
