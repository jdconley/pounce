import { DurableObject } from "cloudflare:workers";

import {
  advance,
  nextSettleAt,
  openGift,
  pause,
  repoint,
  report,
  setPerson,
  unlockedFor,
  unpause,
  view,
  type PairPerson,
  type PairState,
  type StreakView,
  type TableReport,
} from "./pair-core";

import type { Env } from "../env";

/**
 * One instance per pair of players (named by pair id): the pair's streak as
 * one JSON row, and an alarm at the next settlement (§13.2). All the rules
 * live in `pair-core`; this class loads, saves and re-arms.
 */
export class Pair extends DurableObject<Env> {
  private state: PairState | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS pair (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT)");
      const row = this.ctx.storage.sql.exec<{ json: string }>("SELECT json FROM pair WHERE id = 1").toArray()[0];
      this.state = row ? (JSON.parse(row.json) as PairState) : null;
    });
  }

  private async save(): Promise<void> {
    const s = this.state as PairState;
    this.ctx.storage.sql.exec(
      "INSERT INTO pair (id, json) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET json = excluded.json",
      JSON.stringify(s),
    );
    const at = nextSettleAt(s);
    if (at === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(at);
  }

  /** Creates the pair; false if it already exists. */
  async init(state: PairState): Promise<boolean> {
    if (this.state) return false;
    this.state = state;
    await this.save();
    return true;
  }

  members(): string[] | null {
    return this.state ? this.state.people.map((p) => p.id) : null;
  }

  /** A room's report; both people's views after it. */
  async report(r: TableReport, now: number): Promise<Record<string, StreakView> | null> {
    const s = this.state;
    if (!s) return null;
    report(s, r, now);
    await this.save();
    return Object.fromEntries(s.people.map((p) => [p.id, view(s, p.id, now)]));
  }

  async view(playerId: string, now: number): Promise<StreakView | null> {
    const s = this.state;
    if (!s || !s.people.some((p) => p.id === playerId)) return null;
    const v = view(s, playerId, now);
    await this.save();
    return v;
  }

  async pause(by: string, days: number, now: number): Promise<boolean> {
    const s = this.state;
    if (!s) return false;
    advance(s, now);
    const ok = pause(s, by, days, now);
    await this.save();
    return ok;
  }

  async unpause(by: string, now: number): Promise<void> {
    const s = this.state;
    if (!s) return;
    advance(s, now);
    unpause(s, by, now);
    await this.save();
  }

  async openGift(by: string, giftId: string): Promise<boolean> {
    const s = this.state;
    if (!s) return false;
    const ok = openGift(s, by, giftId);
    await this.save();
    return ok;
  }

  async setPerson(p: PairPerson, now: number): Promise<void> {
    const s = this.state;
    if (!s) return;
    setPerson(s, p, now);
    await this.save();
  }

  unlocked(playerId: string): { backs: string[]; rugs: string[] } | null {
    return this.state ? unlockedFor(this.state, playerId) : null;
  }

  exportState(): PairState | null {
    return this.state;
  }

  /** A merged pair's state takes this one's place (§13.1). */
  async replace(state: PairState): Promise<void> {
    this.state = state;
    await this.save();
  }

  async repoint(from: string, to: string): Promise<void> {
    if (!this.state) return;
    repoint(this.state, from, to);
    await this.save();
  }

  /** Deletes the pair and its history (§14). */
  async destroy(): Promise<void> {
    this.state = null;
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS pair (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT)");
  }

  /** Settles whatever is due at `now`. The alarm calls it; so does a test hook. */
  async settle(now: number): Promise<void> {
    if (!this.state) return;
    advance(this.state, now);
    await this.save();
  }

  async alarm(): Promise<void> {
    await this.settle(Date.now());
  }
}
