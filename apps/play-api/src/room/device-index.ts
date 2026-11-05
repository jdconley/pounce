import { DurableObject } from "cloudflare:workers";

import { nightBlocked, pushBlocked } from "../players/age";
import { pushAlert, pushDismiss, pushWidget, pushYourTurn } from "../push/apns";

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
}

const WIDGET_EVERY_MS = 15 * 60_000;
const ALERT_REFRESHED_MS = 60_000;
