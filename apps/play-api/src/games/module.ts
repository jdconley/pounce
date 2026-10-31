import type { Seat } from "../rules/engine";
import type { Rng, Seed } from "../rules/rng";

/** What a room needs from a game. Rooms hold no game-specific logic. */
export interface GameModule<S, A, V, E, Err extends string = string> {
  id: string;
  minSeats: number;
  maxSeats: number;
  create(seats: number, seed: Seed): S;
  apply(
    s: S,
    seat: Seat,
    a: A,
  ): { ok: true; state: S; events: E[] } | { ok: false; error: Err };
  view(s: S, controlled: readonly Seat[]): V;
  filterEvent(e: E, controlled: readonly Seat[]): E;
  /** The seat that must act next, or null when nobody is to act. */
  currentActor(s: S): Seat | null;
  botAction(s: S, seat: Seat, rng: Rng): A;
}
