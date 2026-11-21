import { DurableObject } from "cloudflare:workers";

import { devSpeed } from "../env";
import { player } from "../players/accounts";

import { closesAt } from "./days";
import { dailyModule } from "./games";
import { close, countsForStreak, giveUp, moves, newRun, startView, useHint, type Answer, type RunState, type StartView } from "./run-core";

import type { DailyGameId, DailyModule, DailyResult } from "./module";
import type { Env } from "../env";
import type { DailyEvent } from "./messages";
import type { Day } from "../streaks/clock";

type Stored = { run: RunState; puzzle: unknown };

/** A run is forgotten this long after its day ends. */
const FORGET_AFTER_MS = 2 * 86_400_000;
/** How long before a failed report to the player is tried again. */
const REPORT_RETRY_MS = 60_000;

/**
 * One player's run at one game on one date, named by its run id (`runId`: the HMAC of
 * `${playerId}:${game}:${date}`), so ids can't be guessed (spec §3, "A run"). It keeps the run and
 * its puzzle, referees every call with `run-core`, closes the run at its day's end by alarm, and
 * reports an ended run to its player. Calls from anyone but the run's player are answered null,
 * which the routes turn into a 404.
 */
export class DailyRun extends DurableObject<Env> {
  private stored: Stored | null = null;
  /** The boards hear this run's events in order, one after another. */
  private told: Promise<unknown> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS run (id INTEGER PRIMARY KEY CHECK (id = 1), run TEXT, puzzle TEXT)");
      const row = this.ctx.storage.sql.exec<{ run: string; puzzle: string }>("SELECT run, puzzle FROM run WHERE id = 1").toArray()[0];
      this.stored = row ? { run: JSON.parse(row.run) as RunState, puzzle: JSON.parse(row.puzzle) } : null;
    });
  }

  private module(game: DailyGameId): DailyModule {
    const m = dailyModule(game, this.env);
    if (!m) throw new Error("daily_game_unlisted");
    return m;
  }

  private save(): void {
    const { run, puzzle } = this.stored as Stored;
    this.ctx.storage.sql.exec(
      "INSERT INTO run (id, run, puzzle) VALUES (1, ?, ?) ON CONFLICT (id) DO UPDATE SET run = excluded.run",
      JSON.stringify(run),
      JSON.stringify(puzzle),
    );
  }

  private view(now: number): StartView {
    const { run, puzzle } = this.stored as Stored;
    return startView(this.module(run.game), puzzle, run, now);
  }

  /** Starts the run, or returns it as it stands: one run per player, game and date. */
  async start(a: { id: string; playerId: string; game: DailyGameId; date: Day; zone: string; now: number }): Promise<StartView> {
    if (!this.stored) {
      // Two devices starting at once: the second waits here and gets the first's run.
      await this.ctx.blockConcurrencyWhile(async () => {
        if (this.stored) return;
        const m = this.module(a.game);
        const puzzle = await this.env.DAILY_PUZZLES.get(this.env.DAILY_PUZZLES.idFromName(`${a.game}:${a.date}`)).get(a.game, a.date);
        this.stored = { run: newRun(m, puzzle, a), puzzle };
        this.save();
        await this.ctx.storage.setAlarm(closesAt(a.date, a.zone));
      });
    }
    return this.view(a.now);
  }

  /** The run's player's call, refereed; null for anyone else, or no run. */
  private act(playerId: string, now: number, call: (m: DailyModule, s: Stored) => Answer): Answer | null {
    const s = this.stored;
    if (!s || s.run.playerId !== playerId) return null;
    const wasOpen = s.run.ended === null;
    const before = { seq: s.run.seq, hints: s.run.hints };
    const m = this.module(s.run.game);
    const answer = call(m, s);
    this.save();
    const moved = answer.ok && (s.run.seq !== before.seq || s.run.hints !== before.hints);
    if (moved && s.run.ended === null) {
      // The boards see how far it got; a TV watching sees the state itself.
      this.tell({ k: "progress", game: s.run.game, date: s.run.date, progress: answer.progress }, now);
      if (s.run.tv) this.tell({ k: "watch", game: s.run.game, puzzle: m.publicPuzzle(s.puzzle), state: m.publicState(s.puzzle, s.run.state) }, now);
    }
    if (wasOpen && s.run.ended !== null) this.ended(now);
    return answer;
  }

  /** Hands an event to the player's boards, after the ones before it. Never fatal. */
  private tell(e: DailyEvent, now: number): void {
    const { playerId } = (this.stored as Stored).run;
    this.told = this.told
      .then(() => player(this.env, playerId).dailyEvent(e, now))
      .catch(() => {
        console.error("daily_event_failed");
      });
    this.ctx.waitUntil(this.told);
  }

  async moves(playerId: string, from: number, raw: unknown[], now: number): Promise<Answer | null> {
    return this.act(playerId, now, (m, s) => moves(m, s.puzzle, s.run, from, raw, now));
  }

  /** `seen`: the hints the client had used when it asked, so a resent hint is answered once. */
  async hint(playerId: string, now: number, seen?: number): Promise<Answer | null> {
    return this.act(playerId, now, (m, s) => useHint(m, s.puzzle, s.run, now, seen));
  }

  async giveUp(playerId: string, now: number): Promise<Answer | null> {
    return this.act(playerId, now, (m, s) => giveUp(m, s.puzzle, s.run, now));
  }

  /**
   * Show on TV (spec §8, "Watching a puzzle"). Turned on while the run is open, every TV showing
   * a board the player is on is offered it and gets a frame of its public state at once, then
   * one each move; turned off, they're told it ended (with no result). False: not this player's run.
   */
  async setTv(playerId: string, on: boolean): Promise<boolean> {
    const s = this.stored;
    if (!s || s.run.playerId !== playerId) return false;
    const was = s.run.tv;
    s.run.tv = on;
    this.save();
    if (s.run.ended === null && on !== was) {
      const now = Date.now();
      if (on) {
        this.tell({ k: "watchOffer", game: s.run.game }, now);
        const m = this.module(s.run.game);
        this.tell({ k: "watch", game: s.run.game, puzzle: m.publicPuzzle(s.puzzle), state: m.publicState(s.puzzle, s.run.state) }, now);
      } else {
        this.tell({ k: "watchEnd", game: s.run.game, result: null }, now);
      }
    }
    return true;
  }

  /** The run as stored (tests). */
  async exportState(): Promise<RunState | null> {
    return this.stored?.run ?? null;
  }

  /**
   * The day ended: an open run closes, unsolved. Two days later the run is forgotten: its result
   * lives on with the player and their connections.
   */
  async alarm(): Promise<void> {
    const s = this.stored;
    if (!s) return;
    const now = Date.now();
    const end = closesAt(s.run.date, s.run.zone);
    if (!s.run.ended) {
      if (close(this.module(s.run.game), s.puzzle, s.run, now) === null) {
        // Woken early: wait for the day's end.
        await this.ctx.storage.setAlarm(end);
        return;
      }
      this.save();
      if (s.run.tv) this.tell({ k: "watchEnd", game: s.run.game, result: s.run.result }, now);
    }
    // An ended run reaches its player before it is forgotten, however long that takes.
    if (!s.run.reported && !(await this.report())) {
      await this.ctx.storage.setAlarm(now + this.retryMs());
      return;
    }
    if (now >= end + FORGET_AFTER_MS) {
      await this.ctx.storage.deleteAll();
      this.stored = null;
      return;
    }
    await this.ctx.storage.setAlarm(end + FORGET_AFTER_MS);
  }

  /** Reports the ended run to its player, with one retry, never fatal (spec §5, "The reporting path"). */
  private ended(now: number): void {
    const { run } = this.stored as Stored;
    if (run.tv) this.tell({ k: "watchEnd", game: run.game, result: run.result }, now);
    this.ctx.waitUntil(
      this.report().then(async (ok) => {
        // The alarm tries again until it lands (`recordDaily` is idempotent).
        if (!ok) await this.ctx.storage.setAlarm(Date.now() + this.retryMs());
      }),
    );
  }

  /** Hands the ended run's result to its player; true once it landed (and is marked so). */
  private async report(): Promise<boolean> {
    const s = this.stored;
    if (!s || !s.run.ended || !s.run.result) return true;
    const { run } = s;
    const at = s.run.ended.at;
    try {
      await player(this.env, run.playerId).recordDaily(run.result as DailyResult, countsForStreak(run), at);
    } catch {
      console.error("daily_report_failed");
      return false;
    }
    run.reported = true;
    this.save();
    return true;
  }

  /** How long before a report that failed is tried again; shorter on a fast dev server. */
  private retryMs(): number {
    return REPORT_RETRY_MS / devSpeed(this.env);
  }
}
