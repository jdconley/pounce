import type { TilesEvent, TilesState } from "./engine";
import type { TileId } from "./pieces";
import type { Seat } from "../rules/engine";

/** What one device may see: the table, the counts, and the racks it controls. */
export type TilesView = {
  status: TilesState["status"];
  turn: Seat;
  /** Completed turns so far. */
  turns: number;
  table: TileId[][];
  poolCount: number;
  rackCounts: number[];
  /** Only the seats this device controls. */
  racks: Record<Seat, TileId[]>;
  opened: boolean[];
  /** Seats that passed since the last piece was played (only once the pool is empty). */
  passed: boolean[];
  winners: Seat[];
  scores: number[];
  /** Seats that forfeited: out of the game, last place. */
  forfeited: boolean[];
  /** Only on a finished game; see `TilesState.endReason`. */
  endReason?: TilesState["endReason"];
};

/**
 * Builds a device's view. Every array is a fresh copy, never a reference into
 * `state`. The pool's order, the set-aside pieces and every other rack stay on
 * the server, during the game and after it.
 */
export function viewFor(state: TilesState, controlled: readonly Seat[]): TilesView {
  const racks: Record<Seat, TileId[]> = {};
  for (const seat of controlled) {
    const rack = Number.isInteger(seat) ? state.racks[seat] : undefined;
    if (rack) racks[seat] = [...rack];
  }
  return {
    status: state.status,
    turn: state.turn,
    turns: state.turns,
    table: state.table.map((set) => [...set]),
    poolCount: state.pool.length,
    rackCounts: state.racks.map((rack) => rack.length),
    racks,
    opened: [...state.opened],
    passed: [...state.passed],
    winners: [...state.winners],
    scores: [...state.scores],
    forfeited: [...state.forfeited],
    ...(state.endReason === undefined ? {} : { endReason: state.endReason }),
  };
}

/**
 * Returns a copy of `event` safe to send to a device controlling `controlled`.
 * A drawn piece is private to the drawer, so the `tile` key is omitted for
 * everyone else. Every other event carries only what is on the table or
 * already public.
 */
export function eventFor(event: TilesEvent, controlled: readonly Seat[]): TilesEvent {
  const copy = structuredClone(event);
  if (copy.kind === "drew" && !controlled.includes(copy.seat)) delete copy.tile;
  return copy;
}
