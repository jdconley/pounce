import { DurableObject } from "cloudflare:workers";

import { streakBlock } from "../notify/pushes";

import {
  advance,
  drainEvents,
  facts,
  nextWakeAt,
  openGift,
  pause,
  pauseDays,
  repoint,
  report,
  setPerson,
  unlockedFor,
  unpause,
  view,
  type Facts,
  type PairPerson,
  type PairState,
  type StreakView,
  type TableReport,
} from "./pair-core";
import { notifyPair, type PairNotice, type PairTarget } from "./pairs";
import { streaksOn } from "./profile";

import type { Env } from "../env";

/**
 * One instance per pair of players (named by pair id): the pair's streak as
 * one JSON row, and an alarm at the next settlement (§13.2). All the rules
 * live in `pair-core`; this class loads, saves, re-arms, and hands what
 * happened to the notification glue.
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

  /**
   * Saves and re-arms, then hands settlement events (and, with `notify`, a
   * pause or a turn) to the notification glue (§12.1, §11.2). Never fatal.
   */
  private async save(now = Date.now(), notify: PairNotice = {}): Promise<void> {
    const s = this.state as PairState;
    const events = drainEvents(s);
    this.ctx.storage.sql.exec(
      "INSERT INTO pair (id, json) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET json = excluded.json",
      JSON.stringify(s),
    );
    const at = nextWakeAt(s);
    if (at === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(at);
    if (!streaksOn(this.env) || (events.length === 0 && !notify.paused && (notify.widgets ?? []).length === 0)) return;
    const targets: PairTarget[] = s.people.map((p) => ({
      id: p.id,
      face: { name: p.name, cat: p.cat },
      partner: (s.people.find((q) => q.id !== p.id) as PairPerson).name,
      shared: Object.keys(s.moves),
      streak: streakBlock(view(s, p.id, now)),
    }));
    this.ctx.waitUntil(
      notifyPair(this.env, { pair: s.id, events, targets, ...notify }, now).catch(() => {
        console.error("pair_notify_failed");
      }),
    );
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

  /**
   * A room's report; both people's views after it. `awake` are the players
   * looking at that table: a milestone isn't pushed to them (§12.1).
   */
  async report(r: TableReport, now: number, awake: string[] = []): Promise<Record<string, StreakView> | null> {
    const s = this.state;
    if (!s) return null;
    report(s, r, now);
    // The other person's half landed: their widgets reload, unless the move is now theirs (an alert does it).
    const byMember = s.people.some((p) => p.id === r.by);
    const other = byMember ? s.people.find((p) => p.id !== r.by) : undefined;
    await this.save(now, { awake, widgets: other && r.holder !== other.id ? [other.id] : [] });
    return Object.fromEntries(s.people.map((p) => [p.id, view(s, p.id, now)]));
  }

  /** A person's view, and the latest turn for sorting (which never goes to a client: §14). */
  async view(playerId: string, now: number): Promise<{ view: StreakView; lastTurnAt: number } | null> {
    const s = this.state;
    if (!s || !s.people.some((p) => p.id === playerId)) return null;
    const v = view(s, playerId, now);
    await this.save(now);
    return { view: v, lastTurnAt: s.lastTurnAt };
  }

  /** What a reminder needs to know (§12.1); server only. */
  async facts(playerId: string, now: number): Promise<Facts | null> {
    const s = this.state;
    if (!s || !s.people.some((p) => p.id === playerId)) return null;
    const f = facts(s, playerId, now);
    await this.save(now);
    return f;
  }

  async pause(by: string, days: number, now: number): Promise<boolean> {
    const s = this.state;
    if (!s) return false;
    advance(s, now);
    const ok = pause(s, by, days, now);
    await this.save(now, ok ? { paused: { by, days: pauseDays(s, by, now) }, widgets: s.people.map((p) => p.id) } : {});
    return ok;
  }

  async unpause(by: string, now: number): Promise<void> {
    const s = this.state;
    if (!s) return;
    advance(s, now);
    unpause(s, by, now);
    await this.save(now, { widgets: s.people.map((p) => p.id) });
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
    await this.save(now);
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
    const s = this.state;
    if (!s) return;
    const before = s.lastSettled;
    advance(s, now);
    // Rollover changed both widgets (§11.2).
    await this.save(now, s.lastSettled !== before ? { widgets: s.people.map((p) => p.id) } : {});
  }

  async alarm(): Promise<void> {
    await this.settle(Date.now());
  }
}
