/**
 * The Daily Dish's puzzle host on the web: the contract every daily game plugs into (map plan
 * "The contracts" §2; the iOS twin is `Pounce/Daily/DailyGameHost.swift`).
 *
 * The host draws the top bar, the clock, Show on TV, give up, the end screen and share. A game
 * draws only its board and its own controls (Nine Lives' and Cat Nap's Hint buttons included), and
 * talks to the server only through the `RunSession` it is given (`client.ts`).
 *
 * A game's web entry, `src/daily/<game>/dish.tsx`, default-exports a `DailyGame`; its TV view,
 * `src/daily/<game>/watch.tsx`, default-exports a `DailyWatchView`. The game adds one line to
 * `registry.ts`, so each loads in its own chunk:
 *
 * ```ts
 * import type { DailyGame } from "../host";
 * const sniff: DailyGame<SniffPublic, SniffView, SniffMove, SniffReveal> = { id: "sniff", Screen, share };
 * export default sniff;
 * ```
 */
import type { RunSession } from "./client";
import type { DailyGameId, DailyResult } from "@pounce/play-api/daily/module";
import type { ComponentType } from "preact";

/** The props of a game being played. */
export type DailyGameScreenProps<P = unknown, S = unknown, M = unknown, R = unknown> = {
  /**
   * The run: `session.start.puzzle` and `session.start.state` to draw from (a resumed run's state
   * is the server's), `send` for each move, `hint`, and `subscribe` for reveals and resyncs.
   */
  session: RunSession<P, S, M, R>;
  /**
   * False once the run has ended (the host keeps the board on screen under the end for a moment):
   * take no more input.
   */
  playing: boolean;
};

/**
 * A game's board and controls, filling the box the host gives it (the host's CSS gives it the
 * space between the top bar and the safe area: `display: flex`, `min-height: 0`). Sizes itself to
 * that box from iPhone SE to a laptop, in both orientations.
 */
export type DailyGameScreen<P = unknown, S = unknown, M = unknown, R = unknown> = ComponentType<DailyGameScreenProps<P, S, M, R>>;

/**
 * A run as a TV watches it (spec §8): read only, drawn from one `{ t: "watch", puzzle, state }`
 * frame: the run's public puzzle (as start gives it: Nine Lives' givens, Cat Nap's quilt) and its
 * public state. No notes, no selection.
 */
export type DailyWatchView<P = unknown, S = unknown> = ComponentType<{ puzzle: P; state: S }>;

/** One mark on a share card: a filled paw, an outlined paw, or plain (spec §7 "Share"). */
export type ShareMark = "full" | "half" | "none";

/**
 * A share card's grid, which gives nothing away: Sniff's marks with no letters. Games whose share
 * card shows only the time and hints (Nine Lives, Cat Nap) or points (Box Fort) return null.
 */
export type ShareGrid = ShareMark[][];

/**
 * A daily game being played, as its `dish.tsx` default-exports it. Its watch view is its own
 * module (`watch.tsx`, default-exporting a `DailyWatchView`), so a TV loads it alone.
 */
export interface DailyGame<P = unknown, S = unknown, M = unknown, R = unknown> {
  id: DailyGameId;
  Screen: DailyGameScreen<P, S, M, R>;
  /** The share card's grid for an ended run, from its final public state. Leave out for none. */
  share?: (state: S, result: DailyResult) => ShareGrid | null;
}
