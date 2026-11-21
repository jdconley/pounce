/**
 * Box Fort and its run: what a placement sends, and what each answer from the server does to the
 * screen's state. Pure, so the Dish's `RunSession` wiring (`dish.tsx`) stays a few lines.
 */
import { resync, placePiece, receiveReveal, startPlay, type Play } from "./model";

import type { BoxFortPublicPuzzle, BoxFortPublicState, BoxFortReveal, Place } from "@pounce/play-api/daily/box-fort/module";

/** What the run's subscribers hear that Box Fort cares about (the host's `RunEvent`, narrowed). */
export type BoxFortEvent =
  | { kind: "accepted"; reveals: BoxFortReveal[] }
  | { kind: "resync"; state: BoxFortPublicState }
  | { kind: string };

/** The screen's state for a run the server started or resumed: its puzzle and its public state. */
export function playFor(puzzle: BoxFortPublicPuzzle, state: BoxFortPublicState): Play {
  return resync(startPlay(puzzle), state);
}

/**
 * A placement: the screen's next state, the move to send, and whether to send it now. The last
 * piece of a set goes at once, so the next set comes straight back; so does the run's last move.
 */
export function placement(play: Play, slot: number, row: number, col: number): { play: Play; move: Place; urgent: boolean } | null {
  const next = placePiece(play, slot, row, col);
  if (next === null) return null;
  return { play: next, move: { k: "place", slot, row, col }, urgent: next.waiting || next.state.over !== null };
}

/** An answer from the server: the next set dealt, or the server's state taking over. */
export function onRunEvent(play: Play, event: BoxFortEvent): Play {
  if (event.kind === "accepted" && "reveals" in event) return event.reveals.reduce(receiveReveal, play);
  if (event.kind === "resync" && "state" in event) return resync(play, event.state);
  return play;
}
