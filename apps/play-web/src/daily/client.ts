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
import { api, ApiError } from "../net/api";

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

// ---------------------------------------------------------------------------------------------
// The implementation.


export type RunDeps = {
  /** An authenticated call (`api.call`): throws `ApiError` for anything but a 2xx. */
  call: (method: string, path: string, body?: unknown) => Promise<Response>;
  /** The person playing (`?person=`). */
  person: string;
  now?: () => number;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  /** How long a move may wait for its batch (1 s). */
  batchMs?: number;
};

/** A path with the person's `?person=`. */
export const dailyPath = (path: string, person: string): string => `${path}${path.includes("?") ? "&" : "?"}person=${encodeURIComponent(person)}`;

const HINT_MS = 30_000;
const MAX_BATCH = 100;
const BACKOFF = [250, 500, 1000, 2000, 4000];
const TOO_SOON_MS = 500;

type Waiter<R> = (reveal: R | null) => void;
type Batch<M, R> = { from: number; moves: M[]; waiters: Waiter<R>[] };

export class Run<P = unknown, S = unknown, M = unknown, R = unknown> implements RunSession<P, S, M, R> {
  readonly game: DailyGameId;
  result: DailyResult | null;
  hints: number;
  private seq: number;
  private readonly offset: number;
  private readonly listeners = new Set<(e: RunEvent<S, R>) => void>();
  private queue: { move: M; waiter: Waiter<R> }[] = [];
  private inflight: Batch<M, R> | null = null;
  private timer: unknown = null;
  private urgent = false;
  private failures = 0;
  private retrying = false;
  private idle: (() => void)[] = [];
  private readonly now: () => number;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;

  constructor(
    public start: StartAnswer<P, S>,
    private readonly deps: RunDeps,
  ) {
    this.game = start.game;
    this.result = start.result;
    this.hints = start.hints;
    this.seq = start.seq;
    this.now = deps.now ?? (() => Date.now());
    this.setTimer = deps.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = deps.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
    this.offset = start.now - this.now();
    if (typeof window !== "undefined" && !deps.setTimer) window.addEventListener("online", () => this.retryNow());
  }

  subscribe(listener: (event: RunEvent<S, R>) => void): () => void {
    this.listeners.add(listener);
    return () => void this.listeners.delete(listener);
  }

  serverNow(): number {
    return this.now() + this.offset;
  }

  elapsedMs(): number {
    if (this.result) return this.result.timeMs;
    return Math.max(0, this.serverNow() - this.start.startedAt) + this.hints * HINT_MS;
  }

  send(move: M, options: SendOptions = {}): Promise<R | null> {
    if (this.result) return Promise.resolve(null);
    return new Promise<R | null>((waiter) => {
      this.queue.push({ move, waiter });
      if (options.urgent) {
        this.urgent = true;
        this.cancelTimer();
        this.pump();
      } else if (!this.inflight && this.timer === null) {
        this.timer = this.setTimer(() => {
          this.timer = null;
          this.pump();
        }, this.deps.batchMs ?? 1000);
      }
    });
  }

  flush(): Promise<void> {
    if (!this.inflight && this.queue.length === 0) return Promise.resolve();
    const done = new Promise<void>((r) => this.idle.push(r));
    this.urgent = true;
    this.cancelTimer();
    this.pump();
    return done;
  }

  async hint(): Promise<R | null> {
    await this.flush();
    if (this.result) return null;
    // The count so far makes a resend safe: asked again with the same count, the server answers
    // the same hint and charges nothing more. So a dropped hint is asked again, a few times.
    const body = { hints: this.hints };
    let answer: MovesAnswer<R> | null = null;
    for (let attempt = 0; !answer && attempt < BACKOFF.length; attempt++) {
      answer = await this.post<MovesAnswer<R>>("hint", body).catch(() => null);
      if (!answer) await new Promise<void>((r) => this.setTimer(r, BACKOFF[attempt] as number));
    }
    if (!answer) return null;
    if (!answer.ok) {
      if (answer.error !== "illegal") await this.resync();
      return null;
    }
    const reveal = answer.reveals[0] ?? null;
    if (reveal !== null) {
      this.hints += 1;
      this.emit({ kind: "hint", reveal, hints: this.hints });
    }
    this.end(answer.result);
    return reveal;
  }

  async giveUp(): Promise<DailyResult | null> {
    await this.flush();
    if (this.result) return this.result;
    const answer = await this.post<MovesAnswer<R>>("giveup");
    if (!answer) return null;
    if (!answer.ok) {
      await this.resync();
      return this.result;
    }
    this.end(answer.result);
    return this.result;
  }

  // -- internals --

  private emit(e: RunEvent<S, R>): void {
    for (const l of [...this.listeners]) l(e);
  }

  private cancelTimer(): void {
    if (this.timer !== null) this.clearTimer(this.timer);
    this.timer = null;
  }

  private settleIdle(): void {
    if (this.inflight || this.queue.length > 0) return;
    const waiting = this.idle;
    this.idle = [];
    for (const r of waiting) r();
  }

  /** Sends the next batch when nothing is in flight. */
  private pump(): void {
    if (this.inflight || this.queue.length === 0) return this.settleIdle();
    const taken = this.queue.splice(0, MAX_BATCH);
    this.urgent = this.urgent && this.queue.length > 0;
    this.inflight = { from: this.seq, moves: taken.map((t) => t.move), waiters: taken.map((t) => t.waiter) };
    void this.sendBatch(this.inflight);
  }

  /** After a batch: what waits goes now if it was urgent, else within the second. */
  private next(): void {
    this.inflight = null;
    if (this.queue.length === 0) return this.settleIdle();
    if (this.urgent) return this.pump();
    if (this.timer === null) {
      this.timer = this.setTimer(() => {
        this.timer = null;
        this.pump();
      }, this.deps.batchMs ?? 1000);
    }
  }

  private retryNow(): void {
    if (this.retryTimer === null) return;
    this.clearTimer(this.retryTimer);
    this.retryTimer = null;
    this.retryFn?.();
  }

  private retryTimer: unknown = null;
  private retryFn: (() => void) | null = null;

  private later(fn: () => void, ms: number): void {
    this.retryFn = fn;
    this.retryTimer = this.setTimer(() => {
      this.retryTimer = null;
      this.retryFn = null;
      fn();
    }, ms);
  }

  /** A call that may fail on the network: null when it did (the caller decides whether to retry). */
  private async post<T>(what: "moves" | "hint" | "giveup", body?: unknown): Promise<T | null> {
    try {
      const res = await this.deps.call("POST", dailyPath(`/v1/daily/runs/${this.start.run}/${what}`, this.deps.person), body);
      if (this.retrying) {
        this.retrying = false;
        this.emit({ kind: "link", status: "ok" });
      }
      this.failures = 0;
      return (await res.json()) as T;
    } catch (error) {
      if (error instanceof ApiError && error.status !== 0 && error.status !== 429 && error.status < 500) throw error;
      return null;
    }
  }

  private async sendBatch(batch: Batch<M, R>): Promise<void> {
    let answer: MovesAnswer<R> | null;
    try {
      answer = await this.post<MovesAnswer<R>>("moves", { from: batch.from, moves: batch.moves });
    } catch {
      // A 4xx (the run is gone, a body too big): nothing to resend; the server's state wins.
      this.drop(batch);
      return void this.resync();
    }
    if (answer === null) {
      // Offline, a 5xx or the limit: the same batch, from the same `from`, after a wait.
      if (!this.retrying) {
        this.retrying = true;
        this.emit({ kind: "link", status: "retrying" });
      }
      const wait = BACKOFF[Math.min(this.failures, BACKOFF.length - 1)] as number;
      this.failures += 1;
      return this.later(() => void this.sendBatch(batch), wait);
    }
    if (answer.ok) {
      this.seq = answer.seq;
      this.emit({ kind: "accepted", seq: answer.seq, reveals: answer.reveals, progress: answer.progress });
      const reveal = answer.reveals.at(-1) ?? null;
      for (const w of batch.waiters) w(reveal);
      if (answer.result) {
        this.inflight = null;
        this.drop();
        this.end(answer.result);
        return this.settleIdle();
      }
      return this.next();
    }
    const at = Math.max(0, Math.min(answer.at, batch.moves.length));
    switch (answer.error) {
      case "too_soon": {
        // The moves before `at` go now; the rest wait their turn.
        if (at > 0) {
          const rest = batch.moves.slice(at).map((move, i) => ({ move, waiter: batch.waiters[at + i] as Waiter<R> }));
          this.queue.unshift(...rest);
          batch.moves = batch.moves.slice(0, at);
          batch.waiters = batch.waiters.slice(0, at);
        }
        return this.later(() => void this.sendBatch(batch), TOO_SOON_MS);
      }
      case "illegal": {
        const legal = batch.moves.slice(0, at);
        const waiters = batch.waiters.slice(0, at);
        for (const w of batch.waiters.slice(at)) w(null);
        this.drop();
        if (legal.length > 0) {
          const prefix = { from: this.seq, moves: legal, waiters };
          this.inflight = prefix;
          const kept = await this.post<MovesAnswer<R>>("moves", { from: prefix.from, moves: legal }).catch(() => null);
          if (kept?.ok) {
            this.seq = kept.seq;
            this.emit({ kind: "accepted", seq: kept.seq, reveals: kept.reveals, progress: kept.progress });
            for (const w of waiters) w(kept.reveals.at(-1) ?? null);
          } else for (const w of waiters) w(null);
        }
        return void this.resync();
      }
      default:
        // bad_message (a bug), stale, over: start again for the server's state.
        this.drop(batch);
        return void this.resync();
    }
  }

  /** Forgets the batch and everything waiting: each send resolves null. */
  private drop(batch?: Batch<M, R>): void {
    for (const w of batch?.waiters ?? []) w(null);
    for (const q of this.queue) q.waiter(null);
    this.queue = [];
    this.urgent = false;
    this.cancelTimer();
  }

  private end(result: DailyResult | null): void {
    if (!result || this.result) return;
    this.result = result;
    this.emit({ kind: "result", result });
  }

  /** Start again: the server's state, `seq` and result replace ours. */
  private async resync(): Promise<void> {
    this.inflight = null;
    let fresh: StartAnswer<P, S> | null = null;
    for (let attempt = 0; !fresh && attempt < 6; attempt++) {
      try {
        const res = await this.deps.call("POST", dailyPath(`/v1/daily/${this.game}/start`, this.deps.person));
        fresh = (await res.json()) as StartAnswer<P, S>;
      } catch {
        await new Promise<void>((r) => this.setTimer(r, BACKOFF[Math.min(attempt, BACKOFF.length - 1)] as number));
      }
    }
    if (fresh) {
      this.seq = fresh.seq;
      this.hints = fresh.hints;
      this.emit({ kind: "resync", state: fresh.state, seq: fresh.seq });
      this.end(fresh.result);
    }
    this.settleIdle();
  }
}

/** Starts (or resumes) today's run of `game`: null when the server doesn't list it (404). */
export async function startRun<P, S, M, R>(
  game: DailyGameId,
  person: string,
  call: RunDeps["call"] = (m, p, b) => api.call(m, p, b),
): Promise<Run<P, S, M, R> | null> {
  try {
    const res = await call("POST", dailyPath(`/v1/daily/${game}/start`, person));
    return new Run<P, S, M, R>((await res.json()) as StartAnswer<P, S>, { call, person });
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) return null;
    throw error;
  }
}
