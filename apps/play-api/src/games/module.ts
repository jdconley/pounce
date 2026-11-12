import type { Seat } from "../rules/engine";
import type { Rng, Seed } from "../rules/rng";

/** Where a game stands, as a room sees it: being played, between two deals, or finished. */
export type GamePhase = "playing" | "between" | "over";

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
  /** True when `seat`'s action `a`, which produced `events`, ended its turn: what a streak counts (§6.1). */
  endsTurn(a: A, events: readonly E[], seat: Seat): boolean;
  /**
   * A client's `action` as it came off the wire, fully validated, or null when it is not one of
   * this game's actions. The only guard in front of `apply`, which trusts the shape it is given.
   */
  parseAction(raw: unknown): A | null;
  phase(s: S): GamePhase;
  /** What the room applies, for seat 0, once the game has sat `between` for a moment; null for a game that never is. */
  betweenAction: A | null;
  /** Leaving for good. A room applies it for a stalled seat its tablemates retire. */
  forfeitAction: A;
  /** Per seat: out of the game for good. */
  forfeited(s: S): readonly boolean[];
  /** Tells one turn from the next, together with the room's own count of turn starts. */
  turnKey(s: S): string;
  /** True for an event that begins a turn. */
  startsTurn(e: E): boolean;
  /** A plain legal action for the seat on the move, for when `botAction`'s is refused. */
  fallbackAction(s: S, seat: Seat): A;
  /** Per seat, how far along it is, for the live table. What the number means is `progressKind`. */
  progress(s: S): number[];
  /** `shelf`: the phase a seat is on, counting up. `pieces`: what is left on its rack, counting down. */
  progressKind: "shelf" | "pieces";
}
