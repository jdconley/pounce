/**
 * One daily run, as the web player plays it (docs/daily-protocol.md "A run"). A game screen gets a
 * `RunSession` from the Dish's host (`host.tsx`) and only ever talks to the server through it:
 *
 * - `start` is the server's start answer: the puzzle, the state to draw, the clock, the result.
 * - `send(move)` shows nothing and blocks nothing: the game has already drawn the move. Moves go
 *   out in batches at most once a second, or at once for an urgent move (a Sniff guess, Box Fort's
 *   last piece of a set). One batch is in flight at a time; a dropped connection resends the same
 *   `from`, which the server answers once and never applies twice.
 * - `hint()` and `giveUp()` flush waiting moves first, then ask.
 * - `subscribe` hears every authoritative answer: accepted batches and their reveals, hints, a
 *   resync (the server's state wins: redraw from it), and the result.
 * - The clock is the server's: `elapsedMs()` counts from `startedAt`, corrected by the server's
 *   `now` at start, plus 30 seconds a hint, as the result's `timeMs` will.
 *
 * Network calls are fetches (never blocking); timers live here, in net code, never in screens.
 */
import type { DailyGameId, DailyResult } from "@pounce/play-api/daily/module";

/** `POST /v1/daily/{game}/start`, 200. */
export type StartAnswer<P = unknown, S = unknown> = {
  run: string;
  game: DailyGameId;
  date: string;
  number: number;
  level: number;
  startedAt: number;
  now: number;
  puzzle: P;
  state: S;
  seq: number;
  hints: number;
  result: DailyResult | null;
  closesAt: number;
};

/** `POST /v1/daily/runs/{run}/moves` (and hint, give up), 200. */
export type MovesAnswer<R = unknown> =
  | { ok: true; seq: number; reveals: R[]; progress: number; result: DailyResult | null }
  | { ok: false; error: "illegal" | "too_soon" | "bad_message" | "stale" | "over"; at: number; seq: number };

/** What a run's subscribers hear, in order. */
export type RunEvent<S = unknown, R = unknown> =
  /** The server took a batch: `reveals` in move order, for the moves that reveal something. */
  | { kind: "accepted"; seq: number; reveals: R[]; progress: number }
  /** A hint: what it revealed (a cell, a cat). `hints` is the run's count now. */
  | { kind: "hint"; reveal: R; hints: number }
  /** The server's state replaces the game's (a refused move, a stale batch): redraw from it. */
  | { kind: "resync"; state: S; seq: number }
  /** The run ended. The host shows the end screen. */
  | { kind: "result"; result: DailyResult }
  /** The link to the server: "retrying" while a batch waits on a dropped connection. */
  | { kind: "link"; status: "ok" | "retrying" };

export type SendOptions = {
  /** Send now, with whatever is waiting: a Sniff guess, Box Fort's last piece of a set. */
  urgent?: boolean;
};

/**
 * A run in progress. `P` is the game's public puzzle, `S` its public state, `M` its move and `R`
 * what a move or hint reveals (each game's `module.ts` in `@pounce/play-api/daily/<game>/`).
 */
export interface RunSession<P = unknown, S = unknown, M = unknown, R = unknown> {
  /** The start answer, as the server sent it (a resumed run carries its state and `seq`). */
  readonly start: StartAnswer<P, S>;
  readonly game: DailyGameId;
  /** The run's result once it has ended, else null. */
  readonly result: DailyResult | null;
  /** Hints used so far. */
  readonly hints: number;
  /**
   * Queue a move the game has already drawn. Resolves with what the server revealed for the batch
   * that carried it (the batch's last reveal: Sniff's marks, Box Fort's next set), or null when the
   * batch revealed nothing or was refused (a `resync` follows a refusal). Never await it in a
   * click handler for anything but a Sniff guess or Box Fort's next set.
   */
  send(move: M, options?: SendOptions): Promise<R | null>;
  /** Send whatever is waiting now; resolves once the server has answered it. */
  flush(): Promise<void>;
  /** Flush, then ask for a hint: what it revealed, or null (no hint left, or this game has none). */
  hint(): Promise<R | null>;
  /** Flush, then give up. Resolves with the result (also sent to subscribers), or null offline. */
  giveUp(): Promise<DailyResult | null>;
  /** Hear every authoritative answer. Returns the unsubscribe. */
  subscribe(listener: (event: RunEvent<S, R>) => void): () => void;
  /** The server's clock now, in epoch ms. */
  serverNow(): number;
  /** The run's time so far, as the server will count it: since `startedAt`, plus 30 s a hint. */
  elapsedMs(): number;
}
