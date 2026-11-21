import { DurableObject } from "cloudflare:workers";

import { createRng } from "../rules/rng";
import { addDays, type Day } from "../streaks/clock";

import { levelFor } from "./days";
import { dailyModule } from "./games";
import { dailySeed } from "./seed";

import type { DailyGameId } from "./module";
import type { Env } from "../env";

const DAY_MS = 86_400_000;
/** 03:00 UTC on D: before the first zone (UTC+14) reaches 04:00 on D + 1, at 14:00 UTC. */
const WARM_UTC_MS = 3 * 3_600_000;
/** A puzzle is forgotten this long after its date starts in UTC: every run on it has closed. */
const KEEP_MS = 3 * DAY_MS;

type Made = { game: DailyGameId; date: Day; json: string };

/**
 * One day's puzzle for one game, named `${game}:${date}` (spec §3, "Puzzles"): made once from the
 * day's seed and kept, so every run that day plays the same one. Its alarm makes the next date's
 * puzzle ahead of time (a cache warm only: `get` always makes on a miss), then forgets this one
 * once every run on it has closed.
 */
export class DailyPuzzle extends DurableObject<Env> {
  private puzzle: Made | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS puzzle (id INTEGER PRIMARY KEY CHECK (id = 1), game TEXT, date TEXT, json TEXT)");
      this.puzzle = this.ctx.storage.sql.exec<Made>("SELECT game, date, json FROM puzzle WHERE id = 1").toArray()[0] ?? null;
    });
  }

  /** The whole puzzle, solution included: for the server's referee only, never a client. */
  async get(game: DailyGameId, date: Day): Promise<unknown> {
    if (!this.puzzle) {
      // Made inside the gate, so two first readers can't make it twice.
      await this.ctx.blockConcurrencyWhile(async () => {
        if (this.puzzle) return;
        const module = dailyModule(game, this.env);
        const secret = this.env.TOKEN_SECRET;
        if (!module || !secret) throw new Error("daily_puzzle_unavailable");
        const puzzle = module.make(createRng(await dailySeed(secret, game, date)), levelFor(date));
        const made = { game, date, json: JSON.stringify(puzzle) };
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO puzzle (id, game, date, json) VALUES (1, ?, ?, ?)", made.game, made.date, made.json);
        this.puzzle = made;
        await this.arm(Date.now());
      });
    }
    return JSON.parse((this.puzzle as Made).json);
  }

  /** Whether this puzzle is made (the warm's test hook). */
  async made(): Promise<boolean> {
    return this.puzzle !== null;
  }

  /** The next alarm: the warm while it is ahead, else the forgetting. */
  private async arm(now: number): Promise<void> {
    const start = Date.parse(`${(this.puzzle as Made).date}T00:00:00Z`);
    const at = [start + WARM_UTC_MS, start + KEEP_MS].find((t) => t > now);
    if (at === undefined) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(at);
  }

  async alarm(): Promise<void> {
    if (!this.puzzle) return;
    const now = Date.now();
    if (now >= Date.parse(`${this.puzzle.date}T00:00:00Z`) + KEEP_MS) {
      await this.ctx.storage.deleteAll();
      this.puzzle = null;
      return;
    }
    await this.warm(now);
  }

  /** Makes the next date's puzzle, then waits to forget this one. */
  async warm(now = Date.now()): Promise<void> {
    if (!this.puzzle) return;
    const { game, date } = this.puzzle;
    const next = addDays(date, 1);
    await this.env.DAILY_PUZZLES.get(this.env.DAILY_PUZZLES.idFromName(`${game}:${next}`)).get(game, next);
    await this.arm(Math.max(now, Date.parse(`${date}T00:00:00Z`) + WARM_UTC_MS));
  }
}
