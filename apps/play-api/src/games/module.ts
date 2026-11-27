import type { GameAim } from "../protocol";
import type { Seat } from "../rules/engine";
import type { Rng, Seed } from "../rules/rng";

/** Where a game stands, as a room sees it: being played, between two deals, or finished. */
export type GamePhase = "playing" | "between" | "over";

/** What the room knows of the device a view is for, beyond which seats it controls (Purrtrait's drawer's device and kittens). */
export type ViewerInfo = { drawerDevice: boolean; easyOnly: boolean };

/** What the room knows of the device acting, beyond its seat. */
export type ApplyContext = { easyOnly: boolean };

/**
 * A game's live stream (Purrtrait's ink, design §6): what a room needs to relay it with its
 * `LiveStream`. `Op` is one update and `Tally` the game's checking state; the checks and the
 * compaction are the game's, who may send (the device that owns the turn) is the room's.
 * Methods, not properties, so a game's own op and tally types fit the room's `unknown`.
 */
export type LiveRules<S, Op = unknown, Tally = unknown> = {
  /** Messages one device may send in a second. */
  perSecond: number;
  /** Who hears each message: the screens and the sender's own device (the default), or every connected device. */
  audience?: "screens+owner" | "all";
  /** The key (the turn) messages are taken for now, or null while nobody may send. */
  key(s: S): string | null;
  /** A fresh tally. `rebuilt`: it stands in for a log the room lost. */
  start(rebuilt: boolean): Tally;
  check(ops: readonly Op[], tally: Tally): { ok: true; tally: Tally } | { ok: false; full: boolean };
  compact(ops: readonly Op[]): Op[];
  /** The batch begins again from nothing (a clear), so it can stand in for a lost log. */
  wipes(ops: readonly Op[]): boolean;
};

/** What a room needs from a game. Rooms hold no game-specific logic. */
export interface GameModule<S, A, V, E, Err extends string = string, O = never> {
  id: string;
  minSeats: number;
  maxSeats: number;
  /** `options`: what the table chose in the lobby (`parseOptions`); a game with none ignores it. */
  create(seats: number, seed: Seed, options?: O): S;
  /** What a new table of this game starts with, for its lobby to change. Absent: the game has no options. */
  defaultOptions?: O;
  /** A lobby's `setOptions` off the wire, fully validated, or null. Absent: the game has no options. */
  parseOptions?(raw: unknown): O | null;
  /**
   * A seat that leaves (its own forfeit, or retired) goes to a House Cat for the rest of the game,
   * and the room ends the game only once no person is left, by applying `forfeitAction` then.
   * Absent: the seat is out, as the game's own forfeit has it.
   */
  leaveTakeover?: boolean;
  apply(
    s: S,
    seat: Seat,
    a: A,
    /** What the room knows of the acting device. A game with no use for it ignores it. */
    ctx?: ApplyContext,
  ): { ok: true; state: S; events: E[] } | { ok: false; error: Err };
  /**
   * The game changes for a kitten's device (Purrtrait offers it two Easy words): the room looks up
   * each device's age band and passes `easyOnly` to `view` and `apply`. Absent: it never asks.
   */
  kittenAware?: boolean;
  /**
   * Same room only (Purrtrait, design §5): only a screen makes such a table, it has one screen,
   * which a host's link swaps, and a device that isn't yet a member joins only with the screen's
   * near key. Absent: any device with the code may join, and a table may have several screens.
   */
  sameRoom?: boolean;
  /**
   * The game takes a live stream (`ink` messages; Purrtrait, design §6). The room keeps it in
   * memory only, relays it to its `audience`, and the device that first acts for the seat on the
   * move owns the turn: only it streams and acts for the seat until the turn ends. Absent: `ink`
   * is `not_allowed`.
   */
  stream?: LiveRules<S>;
  /** `viewer`: what the room knows of the device asking. A game with no use for it ignores it. */
  view(s: S, controlled: readonly Seat[], viewer?: ViewerInfo): V;
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
  /**
   * A client's live `aim` as it came off the wire, fully validated, or null when it is not this
   * game's kind of aim. Whether it points at real things is `aimAllowed`'s to say.
   */
  parseAim(raw: unknown): GameAim | null;
  /** True when `aim` points only at things every seat can see (never at another seat's hand or the pool). */
  aimAllowed(s: S, seat: Seat, aim: GameAim): boolean;
  phase(s: S): GamePhase;
  /**
   * How long the phase may last, ms, or null when it has no clock. The room keeps the deadline,
   * stops it while the screen is away, and applies `timeUpAction` when it passes. Absent: no clocks.
   */
  turnLimitMs?(s: S): number | null;
  /** What the room applies, for the seat on the move, when `turnLimitMs` runs out. */
  timeUpAction?: A | null;
  /**
   * The game ended by the room, for a table whose screen stayed away too long: the final state and
   * events, applied like any action's result. Absent: such a table never ends that way.
   */
  stall?(s: S): { state: S; events: E[] };
  /**
   * An action only the room sends (a clock's `timeUp`): refused from a client as `not_allowed`.
   * Absent: every action is a client's.
   */
  parseRoomAction?(raw: unknown): A | null;
  isRoomOnly?(a: A): boolean;
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
  /**
   * `shelf`: the phase a seat is on, counting up. `pieces`: what is left on its rack, counting
   * down. `score`: its side's score.
   */
  progressKind: "shelf" | "pieces" | "score";
}
