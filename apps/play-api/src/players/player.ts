import { DurableObject } from "cloudflare:workers";

import { createTables, listTables, removeTable, upsertTable, type TableEntry } from "../room/tables";
import { leaveAllPairs } from "../streaks/pairs";
import { quietStartMinutes } from "../streaks/profile";

import { IDENTITIES_NAME } from "./identities";
import { mergeSection } from "./state";

import type { Env } from "../env";
import type { AgeBand, Json, Section, StatePatch } from "./parse";
import type { Look } from "../room/core";
import type { PairPerson } from "../streaks/pair-core";

export type PlayerMeta = {
  name: string;
  cat: number;
  ageBand: AgeBand | null;
  /** Set on a merged guest: the player it became. */
  forwardTo: string | null;
  /** Has an identity other than `device`. */
  signedIn: boolean;
};

export type IdentityRow = { provider: string; subjectHash: string; deviceId: string | null; secret: string | null };

/** A pass-and-play person listed on a signed-in owner's account, so they follow the owner to the iPad. */
export type HouseholdPerson = { personId: string; playerId: string; name: string; cat: number };

/** The player's name and cat, and when a device last changed them (client ms), so other devices can catch up. */
export type MeProfile = { name: string; cat: number; at: number };

export type MeState = {
  settings: Section;
  tutorial: Section;
  archive: Section;
  people: HouseholdPerson[];
  profile: MeProfile | null;
};

/** One of a player's pairs (§13.2): the partner, and whether it's pinned as the top pair. */
export type PairRow = { pairId: string; partnerId: string; pinned: boolean };

export type PlayerExport = {
  identities: IdentityRow[];
  devices: string[];
  tables: TableEntry[];
  settings: Section;
  tutorial: Section;
  archive: Section;
  household: (HouseholdPerson & { deviceId: string })[];
};

const DAY_MS = 24 * 60 * 60 * 1000;
/** A merged guest's forwarding stub lives this long (§14). */
const STUB_TTL_MS = 30 * DAY_MS;
/** A guest no device has touched for this long is deleted (§14, §14.1). */
const GUEST_TTL_MS = 90 * DAY_MS;
const SECTIONS = ["settings", "tutorial", "archive"] as const;

/**
 * One instance per player (named by playerId): name and cat, identities,
 * devices, household people, tables, and synced state. A player exists once
 * `touch` creates it; until then (or after `destroy`) room reports are ignored,
 * so a deleted player isn't brought back by a room that hasn't heard yet.
 */
export class Player extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => this.schema());
  }

  private schema(): void {
    const { sql } = this.ctx.storage;
    sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
    sql.exec(
      `CREATE TABLE IF NOT EXISTS identities (provider TEXT, subject_hash TEXT, device_id TEXT, secret TEXT,
         PRIMARY KEY (provider, subject_hash))`,
    );
    sql.exec("CREATE TABLE IF NOT EXISTS devices (device_id TEXT PRIMARY KEY, attached_at INTEGER)");
    sql.exec(
      `CREATE TABLE IF NOT EXISTS household (device_id TEXT, person_id TEXT, player_id TEXT, name TEXT, cat INTEGER,
         PRIMARY KEY (device_id, person_id))`,
    );
    sql.exec("CREATE TABLE IF NOT EXISTS state (section TEXT, key TEXT, v TEXT, at INTEGER, PRIMARY KEY (section, key))");
    sql.exec("CREATE TABLE IF NOT EXISTS pairs (pair_id TEXT PRIMARY KEY, partner_id TEXT UNIQUE, pinned INTEGER, created_at INTEGER)");
    // Tombstones (§14): partners whose streak this player left, so it doesn't re-form.
    sql.exec("CREATE TABLE IF NOT EXISTS left_pairs (partner_id TEXT PRIMARY KEY, at INTEGER)");
    createTables(sql);
  }

  private getMeta(k: string): string | null {
    return this.ctx.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = ?", k).toArray()[0]?.v ?? null;
  }

  private setMeta(k: string, v: string | number | null): void {
    if (v === null) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = ?", k);
    else this.ctx.storage.sql.exec("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v", k, String(v));
  }

  private exists(): boolean {
    return this.getMeta("name") !== null;
  }

  private isSignedIn(): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 FROM identities WHERE provider != 'device' LIMIT 1").toArray().length > 0;
  }

  /**
   * Creates the player or refreshes it from a device's profile. Name and cat
   * are last writer wins by `at`, so two devices that disagree settle.
   */
  async touch(t: {
    playerId: string;
    deviceId: string;
    name: string;
    cat: number;
    ageBand?: AgeBand;
    /** The device's time zone: a player's zone is the latest any of their devices reported (§6.3). */
    timeZone?: string;
    at: number;
    now: number;
  }): Promise<void> {
    if (this.getMeta("forward_to") !== null) return;
    this.setMeta("id", t.playerId);
    const nameAt = Number(this.getMeta("name_at") ?? -1);
    if (!this.exists() || t.at > nameAt) {
      this.setMeta("name", t.name);
      this.setMeta("cat", t.cat);
      this.setMeta("name_at", t.at);
    }
    if (t.ageBand) this.setMeta("age_band", t.ageBand);
    if (t.timeZone) this.setMeta("time_zone", t.timeZone);
    this.setMeta("last_touch", t.now);
    this.attachDevice(t.deviceId, t.now);
    await this.arm(t.now);
  }

  meta(): PlayerMeta | null {
    if (!this.exists()) return null;
    return {
      name: this.getMeta("name") as string,
      cat: Number(this.getMeta("cat")),
      ageBand: this.getMeta("age_band") as AgeBand | null,
      forwardTo: this.getMeta("forward_to"),
      signedIn: this.isSignedIn(),
    };
  }

  addIdentity(row: IdentityRow): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO identities (provider, subject_hash, device_id, secret) VALUES (?, ?, ?, ?)
       ON CONFLICT (provider, subject_hash) DO UPDATE SET device_id = excluded.device_id,
         secret = COALESCE(excluded.secret, identities.secret)`,
      row.provider,
      row.subjectHash,
      row.deviceId,
      row.secret,
    );
  }

  identities(): IdentityRow[] {
    return this.ctx.storage.sql
      .exec<{ provider: string; subject_hash: string; device_id: string | null; secret: string | null }>(
        "SELECT provider, subject_hash, device_id, secret FROM identities",
      )
      .toArray()
      .map((r) => ({ provider: r.provider, subjectHash: r.subject_hash, deviceId: r.device_id, secret: r.secret }));
  }

  /** Removes a provider's identities (only those bound by `deviceId`, when given) and returns them. */
  removeIdentities(provider: string, deviceId?: string): IdentityRow[] {
    const removed = this.identities().filter(
      (r) => r.provider === provider && (deviceId === undefined || r.deviceId === deviceId),
    );
    for (const r of removed) {
      this.ctx.storage.sql.exec("DELETE FROM identities WHERE provider = ? AND subject_hash = ?", r.provider, r.subjectHash);
    }
    return removed;
  }

  attachDevice(deviceId: string, now: number): void {
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO devices (device_id, attached_at) VALUES (?, ?)", deviceId, now);
  }

  detachDevice(deviceId: string): void {
    this.ctx.storage.sql.exec("DELETE FROM devices WHERE device_id = ?", deviceId);
    this.ctx.storage.sql.exec("DELETE FROM household WHERE device_id = ?", deviceId);
  }

  deviceIds(): string[] {
    return this.ctx.storage.sql
      .exec<{ device_id: string }>("SELECT device_id FROM devices")
      .toArray()
      .map((r) => r.device_id);
  }

  /** Replaces the household people one device lists for this (signed-in) player. */
  setHousehold(deviceId: string, people: HouseholdPerson[]): void {
    const { sql } = this.ctx.storage;
    sql.exec("DELETE FROM household WHERE device_id = ?", deviceId);
    for (const p of people) {
      sql.exec(
        "INSERT INTO household (device_id, person_id, player_id, name, cat) VALUES (?, ?, ?, ?, ?)",
        deviceId,
        p.personId,
        p.playerId,
        p.name,
        p.cat,
      );
    }
  }

  /** Every device's household people, once per person. */
  household(): HouseholdPerson[] {
    const rows = this.ctx.storage.sql
      .exec<{ person_id: string; player_id: string; name: string; cat: number }>(
        "SELECT person_id, player_id, name, cat FROM household ORDER BY person_id",
      )
      .toArray();
    const byPerson = new Map(rows.map((r) => [r.person_id, { personId: r.person_id, playerId: r.player_id, name: r.name, cat: r.cat }]));
    return [...byPerson.values()];
  }

  upsertTable(entry: TableEntry): void {
    if (this.exists() && this.getMeta("forward_to") === null) upsertTable(this.ctx.storage.sql, entry);
  }

  removeTable(code: string): void {
    removeTable(this.ctx.storage.sql, code);
  }

  listTables(): TableEntry[] {
    return listTables(this.ctx.storage.sql);
  }

  private section(name: string): Section {
    const rows = this.ctx.storage.sql
      .exec<{ key: string; v: string; at: number }>("SELECT key, v, at FROM state WHERE section = ?", name)
      .toArray();
    return Object.fromEntries(rows.map((r) => [r.key, { v: JSON.parse(r.v) as Json, at: r.at }]));
  }

  private writeSection(name: string, patch: Section, now: number): void {
    const merged = mergeSection(this.section(name), patch, now);
    for (const [key, entry] of Object.entries(merged)) {
      this.ctx.storage.sql.exec(
        `INSERT INTO state (section, key, v, at) VALUES (?, ?, ?, ?)
         ON CONFLICT (section, key) DO UPDATE SET v = excluded.v, at = excluded.at`,
        name,
        key,
        JSON.stringify(entry.v),
        entry.at,
      );
    }
  }

  getState(): MeState {
    return {
      settings: this.section("settings"),
      tutorial: this.section("tutorial"),
      archive: this.section("archive"),
      people: this.household(),
      profile: this.exists()
        ? { name: this.getMeta("name") as string, cat: Number(this.getMeta("cat")), at: Number(this.getMeta("name_at") ?? 0) }
        : null,
    };
  }

  patchState(patch: StatePatch, now: number): void {
    if (!this.exists()) return;
    for (const name of SECTIONS) {
      const section = patch[name];
      if (section) this.writeSection(name, section, now);
    }
  }

  exportForMerge(): PlayerExport {
    return {
      identities: this.identities(),
      devices: this.deviceIds(),
      tables: this.listTables(),
      settings: this.section("settings"),
      tutorial: this.section("tutorial"),
      archive: this.section("archive"),
      household: this.ctx.storage.sql
        .exec<{ device_id: string; person_id: string; player_id: string; name: string; cat: number }>(
          "SELECT device_id, person_id, player_id, name, cat FROM household",
        )
        .toArray()
        .map((r) => ({ deviceId: r.device_id, personId: r.person_id, playerId: r.player_id, name: r.name, cat: r.cat })),
    };
  }

  /** Takes in a merged player's data. This player keeps its own name and cat. */
  absorb(e: PlayerExport, now: number): void {
    const { sql } = this.ctx.storage;
    for (const row of e.identities) {
      // Keep whichever side holds the refresh token: revoking needs it.
      sql.exec(
        `INSERT INTO identities (provider, subject_hash, device_id, secret) VALUES (?, ?, ?, ?)
         ON CONFLICT (provider, subject_hash) DO UPDATE SET secret = COALESCE(identities.secret, excluded.secret)`,
        row.provider,
        row.subjectHash,
        row.deviceId,
        row.secret,
      );
    }
    for (const deviceId of e.devices) this.attachDevice(deviceId, now);
    for (const table of e.tables) upsertTable(sql, table);
    for (const name of SECTIONS) this.writeSection(name, e[name], now);
    for (const p of e.household) {
      sql.exec(
        "INSERT OR IGNORE INTO household (device_id, person_id, player_id, name, cat) VALUES (?, ?, ?, ?, ?)",
        p.deviceId,
        p.personId,
        p.playerId,
        p.name,
        p.cat,
      );
    }
  }

  /** Empties a merged player, leaving a pointer to `to` for 30 days. */
  async becomeStub(to: string, now: number): Promise<void> {
    const id = this.getMeta("id");
    const { name, cat } = { name: this.getMeta("name"), cat: this.getMeta("cat") };
    await this.ctx.storage.deleteAll();
    this.schema();
    if (id) this.setMeta("id", id);
    if (name !== null) this.setMeta("name", name);
    if (cat !== null) this.setMeta("cat", cat);
    this.setMeta("forward_to", to);
    this.setMeta("stub_at", now);
    await this.ctx.storage.setAlarm(now + STUB_TTL_MS);
  }

  /** Can be in pairs: exists, isn't merged away, and isn't being deleted or merged (`retire`). */
  private live(): boolean {
    return this.exists() && this.getMeta("forward_to") === null && this.getMeta("retiring") === null;
  }

  /**
   * Stops this player forming pairs, before its pairs are left or merged: a
   * room's report already in flight can't make a new one with a player on
   * the way out.
   */
  retire(): void {
    this.setMeta("retiring", 1);
  }

  private hasLeft(partnerId: string): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 FROM left_pairs WHERE partner_id = ?", partnerId).toArray().length > 0;
  }

  pairList(): PairRow[] {
    return this.ctx.storage.sql
      .exec<{ pair_id: string; partner_id: string; pinned: number }>("SELECT pair_id, partner_id, pinned FROM pairs ORDER BY created_at")
      .toArray()
      .map((r) => ({ pairId: r.pair_id, partnerId: r.partner_id, pinned: r.pinned === 1 }));
  }

  pairWith(partnerId: string): string | null {
    return (
      this.ctx.storage.sql
        .exec<{ pair_id: string }>("SELECT pair_id FROM pairs WHERE partner_id = ?", partnerId)
        .toArray()[0]?.pair_id ?? null
    );
  }

  /**
   * This player (the one with the smaller id: the pair's coordinator) makes
   * the pair with `partnerId`, or returns the one it has. Check and insert run
   * with no await between, so two rooms can't make two pairs. Null when this
   * player is gone or merged, left that partner, or is that partner.
   */
  createPair(partnerId: string, pairId: string, now: number): { pairId: string; created: boolean } | null {
    const existing = this.pairWith(partnerId);
    if (existing) return { pairId: existing, created: false };
    if (!this.storePair(pairId, partnerId, now)) return null;
    return { pairId, created: true };
  }

  /** Records a pair this player is in; false when it can't be (gone, merged, left that partner, or themself). */
  storePair(pairId: string, partnerId: string, now: number): boolean {
    if (!this.live() || partnerId === this.getMeta("id") || this.hasLeft(partnerId)) return false;
    const existing = this.pairWith(partnerId);
    if (existing) return existing === pairId;
    this.ctx.storage.sql.exec(
      "INSERT OR IGNORE INTO pairs (pair_id, partner_id, pinned, created_at) VALUES (?, ?, 0, ?)",
      pairId,
      partnerId,
      now,
    );
    return true;
  }

  dropPair(pairId: string): void {
    this.ctx.storage.sql.exec("DELETE FROM pairs WHERE pair_id = ?", pairId);
  }

  /** Leaves a pair (§14) and remembers the partner, so it doesn't re-form. Returns the partner. */
  leavePair(pairId: string, now: number): string | null {
    const row = this.pairList().find((r) => r.pairId === pairId);
    if (!row) return null;
    this.dropPair(pairId);
    this.ctx.storage.sql.exec(
      "INSERT INTO left_pairs (partner_id, at) VALUES (?, ?) ON CONFLICT (partner_id) DO UPDATE SET at = excluded.at",
      row.partnerId,
      now,
    );
    return row.partnerId;
  }

  /** After a merge: the partner `from` is now `to`. */
  repointPair(pairId: string, to: string): void {
    this.ctx.storage.sql.exec("UPDATE pairs SET partner_id = ? WHERE pair_id = ?", to, pairId);
  }

  /** Pins one pair as the top pair (§7); false if it isn't this player's. */
  pin(pairId: string): boolean {
    if (!this.pairList().some((r) => r.pairId === pairId)) return false;
    this.ctx.storage.sql.exec("UPDATE pairs SET pinned = CASE WHEN pair_id = ? THEN 1 ELSE 0 END", pairId);
    return true;
  }

  tombstones(): string[] {
    return this.ctx.storage.sql
      .exec<{ partner_id: string }>("SELECT partner_id FROM left_pairs")
      .toArray()
      .map((r) => r.partner_id);
  }

  addTombstones(partnerIds: string[], now: number): void {
    for (const id of partnerIds) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO left_pairs (partner_id, at) VALUES (?, ?)", id, now);
    }
  }

  /** What a pair needs to know about this player: name, cat, time zone and quiet hours. */
  streakProfile(): PairPerson | null {
    if (!this.live()) return null;
    return {
      id: this.getMeta("id") as string,
      name: this.getMeta("name") as string,
      cat: Number(this.getMeta("cat")),
      zone: this.getMeta("time_zone"),
      quietStart: quietStartMinutes(this.section("settings"), this.getMeta("age_band") as AgeBand | null),
    };
  }

  /** The look this player last put on a table: a new table starts with it (§9.4). */
  setLastLook(look: Look): void {
    if (this.live()) this.setMeta("last_look", JSON.stringify(look));
  }

  lastLook(): Look | null {
    const v = this.getMeta("last_look");
    return v === null ? null : (JSON.parse(v) as Look);
  }

  async destroy(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.schema();
  }

  private async arm(now: number): Promise<void> {
    if (this.isSignedIn()) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(now + GUEST_TTL_MS);
  }

  /** Retention (§14): a stub after 30 days, a guest nobody has touched for 90. */
  async alarm(): Promise<void> {
    const now = Date.now();
    const stubAt = this.getMeta("stub_at");
    if (stubAt !== null) {
      if (now >= Number(stubAt) + STUB_TTL_MS) await this.destroy();
      return;
    }
    if (this.isSignedIn()) return;
    const lastTouch = Number(this.getMeta("last_touch") ?? 0);
    if (now < lastTouch + GUEST_TTL_MS) {
      await this.ctx.storage.setAlarm(lastTouch + GUEST_TTL_MS);
      return;
    }
    await this.expire();
  }

  /**
   * Deletes an expired guest, as account deletion does: its seats go back to
   * their devices, its devices and identities forget it.
   */
  async expire(): Promise<void> {
    const id = this.getMeta("id");
    this.retire();
    if (id) {
      const { env } = this;
      await Promise.all([
        ...this.listTables().map((t) => env.ROOMS.get(env.ROOMS.idFromName(t.code)).adopt({ from: id, to: null })),
        ...this.deviceIds().map((d) => env.DEVICES.get(env.DEVICES.idFromName(d)).forgetPlayer(id)),
        env.IDENTITIES.get(env.IDENTITIES.idFromName(IDENTITIES_NAME)).removePlayer(id),
      ]);
      await leaveAllPairs(env, id, this.pairList());
    }
    await this.destroy();
  }
}
