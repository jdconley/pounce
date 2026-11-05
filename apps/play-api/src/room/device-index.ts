import { DurableObject } from "cloudflare:workers";

import { endBody, type LiveState, type LiveTokens } from "../live/live";
import { nightBlocked, pushBlocked } from "../players/age";
import { pushAlert, pushDismiss, pushLive, pushWidget, pushYourTurn } from "../push/apns";

import { createTables, listTables, removeTable, upsertTable, type TableEntry } from "./tables";

import type { Env } from "../env";
import type { DismissIntent, YourTurnIntent } from "./core";
import type { Level } from "../notify/policy";
import type { AgeBand } from "../players/parse";

export type { TableEntry } from "./tables";

/**
 * One instance per device (named by deviceId): its APNs token, the rooms it
 * sits in as each room reports them, and who it speaks for: the players of
 * the people on it, and the account it is signed in to.
 */
export class DeviceIndex extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS people (person_id TEXT PRIMARY KEY, player_id TEXT)");
      createTables(this.ctx.storage.sql);
    });
  }

  private getMeta(k: string): string | null {
    return this.ctx.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = ?", k).toArray()[0]?.v ?? null;
  }

  private setMeta(k: string, v: string | null): void {
    if (v === null) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = ?", k);
    else this.ctx.storage.sql.exec("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v", k, v);
  }

  setApnsToken(token: string): void {
    this.setMeta("apns_token", token);
  }

  /**
   * Stores the device's time zone, its owner's age band and its people's
   * players (the whole list: people no longer on the device are dropped).
   * Returns the device's tables that aren't over, so the caller can
   * backfill them (every upload: a room that missed one catches up).
   */
  setProfile(p: { timeZone: string; ageBand: AgeBand | null; people: Record<string, string> }): { tables: string[] } {
    const { sql } = this.ctx.storage;
    this.setMeta("time_zone", p.timeZone);
    this.setMeta("age_band", p.ageBand);
    sql.exec("DELETE FROM people");
    for (const [person, player] of Object.entries(p.people)) {
      sql.exec("INSERT INTO people (person_id, player_id) VALUES (?, ?)", person, player);
    }
    return { tables: listTables(sql).filter((t) => t.status !== "over").map((t) => t.code) };
  }

  /** The device owner's age band, from the last profile. */
  ageBand(): AgeBand | null {
    return this.getMeta("age_band") as AgeBand | null;
  }

  private people(): Record<string, string> {
    return Object.fromEntries(
      this.ctx.storage.sql
        .exec<{ person_id: string; player_id: string }>("SELECT person_id, player_id FROM people")
        .toArray()
        .map((r) => [r.person_id, r.player_id]),
    );
  }

  setAccount(playerId: string | null): void {
    this.setMeta("account", playerId);
  }

  players(): { people: Record<string, string>; account: string | null } {
    return { people: this.people(), account: this.getMeta("account") };
  }

  /** Stops speaking for a player: its people mappings go, and the account if it is that player. */
  forgetPlayer(playerId: string): string[] {
    const { sql } = this.ctx.storage;
    const removed = sql
      .exec<{ person_id: string }>("SELECT person_id FROM people WHERE player_id = ?", playerId)
      .toArray()
      .map((r) => r.person_id);
    sql.exec("DELETE FROM people WHERE player_id = ?", playerId);
    if (this.getMeta("account") === playerId) this.setAccount(null);
    return removed;
  }

  /** After a merge: `from`'s people and account now mean `to`. */
  repointPlayer(from: string, to: string): void {
    this.ctx.storage.sql.exec("UPDATE people SET player_id = ? WHERE player_id = ?", to, from);
    if (this.getMeta("account") === from) this.setAccount(to);
  }

  upsertTable(entry: TableEntry): void {
    upsertTable(this.ctx.storage.sql, entry);
  }

  removeTable(code: string): void {
    removeTable(this.ctx.storage.sql, code);
  }

  listTables(): TableEntry[] {
    return listTables(this.ctx.storage.sql);
  }

  /**
   * Sends a push, and forgets a token APNs says is dead. Only that token: the
   * device may have registered a new one while the push was in flight. A
   * kitten's device gets nothing, and a teen's nothing overnight (§14.1).
   */
  async push(intent: YourTurnIntent | DismissIntent): Promise<{ sent: boolean }> {
    const band = this.ageBand();
    if (pushBlocked(band) || nightBlocked(band, this.getMeta("time_zone"), Date.now())) return { sent: false };
    // The live table shows the move already (§11.3, §12.1).
    if (intent.kind === "your_turn" && this.liveRunning(intent.code)) return { sent: false };
    const token = this.getMeta("apns_token");
    const { sent, unregistered } =
      intent.kind === "your_turn"
        ? await pushYourTurn(this.env, token, intent)
        : await pushDismiss(this.env, token, intent.code);
    if (unregistered) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = 'apns_token' AND v = ?", token);
    return { sent };
  }

  /** The device's owner may get nothing now: a kitten never, a teen not overnight (§14.1). */
  private silenced(now: number): boolean {
    const band = this.ageBand();
    return pushBlocked(band) || nightBlocked(band, this.getMeta("time_zone"), now);
  }

  /** Sends a built alert (§12.7); the caller has applied the player's own rules. */
  async pushAlert(body: Record<string, unknown>, collapseId: string, level: Level): Promise<{ sent: boolean }> {
    const now = Date.now();
    if (this.silenced(now)) return { sent: false };
    // While this device's live table can show the move, "your move" stays quiet (§11.3, §12.1).
    if (body.kind === "your_move" && typeof body.code === "string" && this.liveRunning(body.code)) return { sent: false };
    const token = this.getMeta("apns_token");
    const { sent, unregistered } = await pushAlert(this.env, token, body, collapseId, level);
    if (unregistered) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = 'apns_token' AND v = ?", token);
    if (sent) this.setMeta("last_alert_at", String(now));
    return { sent };
  }

  /** The widget extension's WidgetKit push token (§11.2). */
  setWidgetToken(token: string): void {
    this.setMeta("widget_token", token);
  }

  /**
   * Asks the widgets to reload (§11.2): at most once every 15 minutes, and
   * not right after an alert, whose Notification Service Extension already
   * refreshed them.
   */
  async pokeWidget(now: number): Promise<{ sent: boolean }> {
    if (this.silenced(now)) return { sent: false };
    const last = Number(this.getMeta("widget_at") ?? -Infinity);
    const alerted = Number(this.getMeta("last_alert_at") ?? -Infinity);
    if (now - last < WIDGET_EVERY_MS || now - alerted < ALERT_REFRESHED_MS) return { sent: false };
    const token = this.getMeta("widget_token");
    const { sent, unregistered } = await pushWidget(this.env, token);
    if (unregistered) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = 'widget_token' AND v = ?", token);
    if (sent) this.setMeta("widget_at", String(now));
    return { sent };
  }

  // MARK: the live table (§11.3). At most one per device: `live_code` is its table,
  // `live_token` its activity's update token once the app sends it, `live_state` the
  // content it last showed (an end needs one).

  /** The live table's tokens from the app. A kitten's device keeps none (§14.1). */
  setLiveTokens(t: LiveTokens): void {
    if (pushBlocked(this.ageBand())) return;
    if (t.pushToStart !== undefined) this.setMeta("live_start_token", t.pushToStart);
    for (const a of t.activities ?? []) {
      if (a.code !== this.getMeta("live_code")) continue;
      // Null: the activity ended on the device (swiped away): stop holding "your move" back.
      if (a.token === null) this.clearLive();
      else this.setMeta("live_token", a.token);
    }
  }

  /** This device's live table for `code` can be updated: its "your move" is held back. */
  liveRunning(code: string): boolean {
    return this.getMeta("live_code") === code && this.getMeta("live_token") !== null;
  }

  private clearLive(): void {
    for (const k of ["live_code", "live_token", "live_state"]) this.setMeta(k, null);
  }

  private forgetLiveToken(key: "live_start_token" | "live_token", token: string): void {
    this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = ? AND v = ?", key, token);
  }

  /**
   * Push-to-start (§11.3). A newer table replaces the older one, which is
   * ended first with the state it last showed. Nothing for a kitten, or a
   * teen overnight, or without a push-to-start token.
   */
  async liveStart(code: string, body: Record<string, unknown>, state: LiveState, now: number): Promise<{ sent: boolean }> {
    if (this.silenced(now)) return { sent: false };
    const start = this.getMeta("live_start_token");
    if (!start) return { sent: false };
    const old = this.getMeta("live_code");
    const oldState = this.getMeta("live_state");
    if (old !== null && oldState !== null) await this.liveEnd(old, endBody(JSON.parse(oldState) as LiveState, now), now);
    this.setMeta("live_code", code);
    this.setMeta("live_token", null);
    this.setMeta("live_state", JSON.stringify(state));
    const { sent, unregistered } = await pushLive(this.env, start, body, 10);
    if (unregistered) this.forgetLiveToken("live_start_token", start);
    if (!sent) this.clearLive();
    return { sent };
  }

  /** A turn change for this device's live table; ignored for any other table, or before its token arrived. */
  async liveUpdate(code: string, body: Record<string, unknown>, state: LiveState, priority: 5 | 10, now: number): Promise<{ sent: boolean }> {
    if (this.getMeta("live_code") !== code) return { sent: false };
    this.setMeta("live_state", JSON.stringify(state));
    const token = this.getMeta("live_token");
    if (!token || this.silenced(now)) return { sent: false };
    const { sent, unregistered } = await pushLive(this.env, token, body, priority);
    if (unregistered) this.clearLive();
    return { sent };
  }

  /** Ends this device's live table for `code`: forgotten here at once, the push only when it may go. */
  async liveEnd(code: string, body: Record<string, unknown>, now: number): Promise<{ sent: boolean }> {
    if (this.getMeta("live_code") !== code) return { sent: false };
    const token = this.getMeta("live_token");
    this.clearLive();
    if (!token || this.silenced(now)) return { sent: false };
    const { sent, unregistered } = await pushLive(this.env, token, body, 10);
    if (unregistered) this.forgetLiveToken("live_token", token);
    return { sent };
  }
}

const WIDGET_EVERY_MS = 15 * 60_000;
const ALERT_REFRESHED_MS = 60_000;
