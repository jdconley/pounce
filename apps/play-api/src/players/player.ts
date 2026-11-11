import { DurableObject } from "cloudflare:workers";

import { endKitten } from "../kittens/kittens";
import { forgetLinks } from "../links/links";
import { deliverToPlayer, type PushProfile } from "../notify/deliver";
import { gate } from "../notify/policy";
import { streakBlock } from "../notify/pushes";
import { decide, dueSlots, emptyNotifyState, nextWake, noteSent, noteTurn, type NotifyState, type PairFacts, type ReminderInput } from "../notify/reminders";
import { notifySettings, type NotifySettings } from "../notify/settings";
import { claimAnswer, KEEP_MS, restingUntil, type Answer, type PounceRow, type Target } from "../pounce/limits";
import { createTables, listTables, removeTable, upsertTable, type TableEntry } from "../room/tables";
import { FALLBACK_ZONE } from "../streaks/clock";
import { leaveAllPairs } from "../streaks/pairs";
import { mergePersonal, ownView, recordTurn, type OwnStreak, type Personal } from "../streaks/personal";
import { notifyOn, quietStartMinutes, trophyOn } from "../streaks/profile";

import { IDENTITIES_NAME } from "./identities";
import { mergeSection } from "./state";

import type { Env } from "../env";
import type { AgeBand, Json, Section, StatePatch } from "./parse";
import type { Outgoing } from "../notify/types";
import type { Look } from "../room/core";
import type { PairPerson, StreakView } from "../streaks/pair-core";

/** A sent pounce as the sender keeps it: the link token while unanswered, and who sent it from where (to seat them). */
export type StoredPounce = PounceRow & { link: string | null; fromPerson: string; fromDevice: string };
const POUNCE_KEEP_MS = KEEP_MS;

/** A push held back by spacing or a teen's night (§12.1, §14.1), and when it may go. */
type Pending = { at: number; o: Outgoing };
/** How a streak push gets its title (§12.2): the one shared table's name, else the partner's. */
export type StatusTitle = { shared: string[]; partner: string };
const MAX_PENDING = 8;

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
  /** Your own streak and the longest pair streak seen (trophy room design §2, §3). Absent from older exports. */
  personal?: Personal | null;
  pairBest?: number;
  /** The players this one blocked. Absent from older exports. */
  blocks?: BlockRow[];
};

/** A player this one blocked: their id, the person and name they had at the table, and when. */
export type BlockRow = { playerId: string; personId: string; name: string; at: number };
/** More blocks than anyone needs; the oldest go first. */
const MAX_BLOCKS = 200;

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
    // Pounces this player sent (§13.2), kept 7 days.
    sql.exec(
      `CREATE TABLE IF NOT EXISTS pounces (id TEXT PRIMARY KEY, to_id TEXT, target TEXT, at INTEGER, answer TEXT,
         answered_at INTEGER, code TEXT, quiet INTEGER, link TEXT, from_person TEXT, from_device TEXT)`,
    );
    // The old pair id of each tombstone: the handle the leaver's ghosted cat undoes it by.
    sql.exec("CREATE TABLE IF NOT EXISTS left_handles (pair_id TEXT PRIMARY KEY, partner_id TEXT UNIQUE)");
    // Players this one blocked: their pounces and nudges are dropped, and they can't join its tables.
    sql.exec("CREATE TABLE IF NOT EXISTS blocks (player_id TEXT PRIMARY KEY, person_id TEXT, name TEXT, at INTEGER)");
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
  }): Promise<{ previousBand: AgeBand | null }> {
    const previousBand = this.getMeta("age_band") as AgeBand | null;
    if (this.getMeta("forward_to") !== null) return { previousBand };
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
    return { previousBand };
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

  async patchState(patch: StatePatch, now: number): Promise<void> {
    if (!this.exists()) return;
    for (const name of SECTIONS) {
      const section = patch[name];
      if (section) this.writeSection(name, section, now);
    }
    // Reminder times and quiet hours may have moved (§12.6).
    if (patch.settings && notifyOn(this.env)) await this.arm(now);
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
      personal: this.personal(),
      pairBest: this.pairBest(),
      blocks: this.blocks(),
    };
  }

  // MARK: blocks

  /** Blocks `row.playerId` (never itself). False when this player doesn't exist. */
  block(row: BlockRow): boolean {
    if (!this.exists() || row.playerId === this.getMeta("id")) return false;
    const { sql } = this.ctx.storage;
    sql.exec(
      `INSERT INTO blocks (player_id, person_id, name, at) VALUES (?, ?, ?, ?)
       ON CONFLICT (player_id) DO UPDATE SET person_id = excluded.person_id, name = excluded.name`,
      row.playerId,
      row.personId,
      row.name,
      row.at,
    );
    sql.exec("DELETE FROM blocks WHERE player_id NOT IN (SELECT player_id FROM blocks ORDER BY at DESC LIMIT ?)", MAX_BLOCKS);
    return true;
  }

  unblock(playerId: string): void {
    this.ctx.storage.sql.exec("DELETE FROM blocks WHERE player_id = ?", playerId);
  }

  /** Newest first. */
  blocks(): BlockRow[] {
    return this.ctx.storage.sql
      .exec<{ player_id: string; person_id: string; name: string; at: number }>(
        "SELECT player_id, person_id, name, at FROM blocks ORDER BY at DESC",
      )
      .toArray()
      .map((r) => ({ playerId: r.player_id, personId: r.person_id, name: r.name, at: r.at }));
  }

  /** Whether this player blocked any of `playerIds`. */
  blocksAny(playerIds: string[]): boolean {
    const blocked = new Set(this.blocks().map((b) => b.playerId));
    return playerIds.some((id) => blocked.has(id));
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
    // Your own streak merges as pairs do (§13.1): the longer current streak wins, the lifetime numbers take the maximum.
    const merged = mergePersonal(this.personal(), e.personal ?? null, this.zone(), now);
    if (merged) this.setMeta("personal", JSON.stringify(merged));
    if ((e.pairBest ?? 0) > this.pairBest()) this.setMeta("pair_best", e.pairBest as number);
    for (const row of e.blocks ?? []) this.block(row);
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
    this.ctx.storage.sql.exec(
      "INSERT INTO left_handles (pair_id, partner_id) VALUES (?, ?) ON CONFLICT (partner_id) DO UPDATE SET pair_id = excluded.pair_id",
      pairId,
      row.partnerId,
    );
    return row.partnerId;
  }

  /** The streaks this player left that can still be undone: old pair id and partner (§14's ghosted cat). */
  leftHandles(): { pairId: string; partnerId: string }[] {
    return this.ctx.storage.sql
      .exec<{ pair_id: string; partner_id: string }>(
        "SELECT h.pair_id, h.partner_id FROM left_handles h JOIN left_pairs l ON l.partner_id = h.partner_id ORDER BY l.at",
      )
      .toArray()
      .map((r) => ({ pairId: r.pair_id, partnerId: r.partner_id }));
  }

  /** Undoes the leave of `pairId` (only the leaver can): the tombstone goes. Returns the partner, or null. */
  rejoin(pairId: string): string | null {
    const row = this.leftHandles().find((r) => r.pairId === pairId);
    if (!row) return null;
    this.ctx.storage.sql.exec("DELETE FROM left_handles WHERE pair_id = ?", pairId);
    this.ctx.storage.sql.exec("DELETE FROM left_pairs WHERE partner_id = ?", row.partnerId);
    return row.partnerId;
  }

  addLeftHandles(rows: { pairId: string; partnerId: string }[]): void {
    for (const r of rows) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO left_handles (pair_id, partner_id) VALUES (?, ?)", r.pairId, r.partnerId);
    }
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

  private personal(): Personal | null {
    const v = this.getMeta("personal");
    return v === null ? null : (JSON.parse(v) as Personal);
  }

  private pairBest(): number {
    return Number(this.getMeta("pair_best") ?? 0);
  }

  /** The zone this player's days are in (§6.3): the latest a device reported. */
  private zone(): string {
    return this.getMeta("time_zone") ?? FALLBACK_ZONE;
  }

  /**
   * A turn of this player's at a table with another person (trophy room
   * design D1): their own streak counts the day. Only with `TROPHY` on.
   */
  recordPersonalTurn(at: number, now: number): void {
    if (!trophyOn(this.env) || !this.live()) return;
    this.setMeta("personal", JSON.stringify(recordTurn(this.personal(), at, this.zone(), now)));
  }

  /**
   * Your own streak now, and the longest pair streak seen, raised to
   * `pairBest` (the pairs' current bests): kept here so leaving a pair
   * doesn't lower the record. Null for a player that doesn't exist.
   */
  ownStreak(now: number, pairBest: number): { own: OwnStreak; pairBest: number } | null {
    if (!this.live()) return null;
    const p = this.personal();
    const own = ownView(p, this.zone(), now);
    if (p) this.setMeta("personal", JSON.stringify(p));
    const best = Math.max(this.pairBest(), pairBest);
    this.setMeta("pair_best", best);
    return { own, pairBest: best };
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

  /**
   * One alarm for everything (§13.2): guest retention, and with streaks on the
   * next reminder decision and any deferred push.
   */
  private async arm(now: number): Promise<void> {
    if (!this.exists()) return;
    const times: number[] = [];
    if (!this.isSignedIn()) times.push(Number(this.getMeta("last_touch") ?? now) + GUEST_TTL_MS);
    const oldest = this.ctx.storage.sql.exec<{ t: number | null }>("SELECT MIN(at) AS t FROM pounces").toArray()[0]?.t ?? null;
    if (oldest !== null) times.push(oldest + POUNCE_KEEP_MS);
    if (notifyOn(this.env) && this.live()) {
      const wake = nextWake(this.notify(), this.reminderInput(now));
      if (wake !== null && Number.isFinite(wake)) times.push(wake);
      times.push(...this.pending().map((p) => p.at));
    }
    if (times.length === 0) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(Math.min(...times));
  }

  /** Retention (§14): a stub after 30 days, a guest nobody has touched for 90. Then reminders. */
  async alarm(): Promise<void> {
    const now = Date.now();
    const stubAt = this.getMeta("stub_at");
    if (stubAt !== null) {
      if (now >= Number(stubAt) + STUB_TTL_MS) await this.destroy();
      return;
    }
    const lastTouch = Number(this.getMeta("last_touch") ?? 0);
    if (!this.isSignedIn() && now >= lastTouch + GUEST_TTL_MS) {
      await this.expire();
      return;
    }
    this.prunePounces(now);
    if (notifyOn(this.env)) await this.remind(now);
    else await this.arm(now);
  }

  // ---- Notifications (§12) ----

  private notify(): NotifyState {
    const v = this.getMeta("notify");
    return v === null ? emptyNotifyState() : { ...emptyNotifyState(), ...(JSON.parse(v) as NotifyState) };
  }

  private saveNotify(st: NotifyState): void {
    this.setMeta("notify", JSON.stringify(st));
  }

  /** Pushes held back by spacing or a teen's night, and when they may go. */
  private pending(): Pending[] {
    const v = this.getMeta("pending");
    return v === null ? [] : (JSON.parse(v) as Pending[]);
  }

  private savePending(list: Pending[]): void {
    this.setMeta("pending", list.length === 0 ? null : JSON.stringify(list.slice(-MAX_PENDING)));
  }

  private band(): AgeBand | null {
    return this.getMeta("age_band") as AgeBand | null;
  }

  private notifySettings(): NotifySettings {
    return notifySettings(this.section("settings"), this.band());
  }

  // ---- Pounces (§12.4) ----

  /** Every pounce this player has sent, newest first. */
  pounceRows(): StoredPounce[] {
    return this.ctx.storage.sql
      .exec<{
        id: string;
        to_id: string | null;
        target: string;
        at: number;
        answer: string | null;
        answered_at: number | null;
        code: string | null;
        quiet: number;
        link: string | null;
        from_person: string;
        from_device: string;
      }>("SELECT * FROM pounces ORDER BY at DESC")
      .toArray()
      .map((r) => ({
        id: r.id,
        to: r.to_id,
        target: JSON.parse(r.target) as Target,
        at: r.at,
        answer: r.answer as Answer | null,
        answeredAt: r.answered_at,
        code: r.code,
        quiet: r.quiet === 1,
        link: r.link,
        fromPerson: r.from_person,
        fromDevice: r.from_device,
      }));
  }

  /** This player's pounces on `to` (or, for null, its Messages links) from the last 7 days. */
  pouncesTo(to: string | null, now: number): PounceRow[] {
    return this.pounceRows()
      .filter((r) => (to === null ? r.link !== null : r.to === to) && r.at > now - POUNCE_KEEP_MS)
      .map((r) => ({
        id: r.id,
        to: r.to,
        target: r.target,
        at: r.at,
        answer: r.answer,
        answeredAt: r.answeredAt,
        code: r.code,
        quiet: r.quiet,
      }));
  }

  pounce(id: string): StoredPounce | null {
    return this.pounceRows().find((r) => r.id === id) ?? null;
  }

  /**
   * Stores a pounce unless this player is resting from pouncing on that
   * person (§12.4). Check and insert run with no await between.
   */
  async tryPounce(row: StoredPounce, now: number): Promise<{ ok: true } | { until: number } | { gone: true }> {
    if (!this.live()) return { gone: true };
    const until = restingUntil(this.pouncesTo(row.link === null ? row.to : null, now), now);
    if (until !== null) return { until };
    this.ctx.storage.sql.exec(
      `INSERT INTO pounces (id, to_id, target, at, answer, answered_at, code, quiet, link, from_person, from_device)
       VALUES (?, ?, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?)`,
      row.id,
      row.to,
      JSON.stringify(row.target),
      row.at,
      row.quiet ? 1 : 0,
      row.link,
      row.fromPerson,
      row.fromDevice,
    );
    await this.arm(now);
    return { ok: true };
  }

  /**
   * Claims a pounce for an answer and records it, in one step with no await
   * (§12.4): of two answers at once, one claims it and the other sees the
   * result. A link pounce now belongs to whoever answered it. `code` is the
   * table, or null while a new one is being dealt.
   */
  claimAnswer(
    id: string,
    by: string,
    answer: Answer,
    code: string | null,
    now: number,
  ): { claimed: { answer: Answer | null; answeredAt: number | null; code: string | null } } | { repeat: StoredPounce } | { gone: true } | { expired: true } {
    const row = this.pounce(id);
    if (!row) return { gone: true };
    const verdict = claimAnswer(row, by, answer, now, row.link !== null);
    if (verdict === "gone") return { gone: true };
    if (verdict === "expired") return { expired: true };
    if (verdict === "repeat") return { repeat: row };
    this.ctx.storage.sql.exec(
      "UPDATE pounces SET to_id = COALESCE(to_id, ?), answer = ?, answered_at = ?, code = ? WHERE id = ?",
      by,
      answer,
      now,
      code ?? row.code,
      id,
    );
    return { claimed: { answer: row.answer, answeredAt: row.answeredAt, code: row.code } };
  }

  /** The new table a claimed "Play" was dealt. */
  setPounceCode(id: string, code: string): void {
    this.ctx.storage.sql.exec("UPDATE pounces SET code = ? WHERE id = ?", code, id);
  }

  /** Dealing failed: the pounce goes back to how it was, so it can be answered again. */
  releaseAnswer(id: string, prev: { answer: Answer | null; answeredAt: number | null; code: string | null }): void {
    this.ctx.storage.sql.exec("UPDATE pounces SET answer = ?, answered_at = ?, code = ? WHERE id = ?", prev.answer, prev.answeredAt, prev.code, id);
  }

  private prunePounces(now: number): void {
    this.ctx.storage.sql.exec("DELETE FROM pounces WHERE at <= ?", now - POUNCE_KEEP_MS);
  }

  /** When the alarm is set, for tests. */
  async alarmAt(): Promise<number | null> {
    return this.ctx.storage.getAlarm();
  }

  /** The reminder state, for tests and support. */
  notifyState(): NotifyState {
    return this.notify();
  }

  /** Who this player is to a push: name, band, zone, settings and devices. Null when gone or merged. */
  pushProfile(): PushProfile | null {
    if (!this.live()) return null;
    return {
      id: this.getMeta("id") as string,
      name: this.getMeta("name") as string,
      band: this.band(),
      zone: this.getMeta("time_zone"),
      settings: this.notifySettings(),
      devices: this.deviceIds(),
    };
  }

  private reminderInput(now: number): ReminderInput {
    return {
      now,
      zone: this.getMeta("time_zone"),
      band: this.band(),
      settings: this.notifySettings(),
      name: (this.getMeta("name") as string | null) ?? "",
      lastOpenAt: this.getMeta("last_touch") === null ? null : Number(this.getMeta("last_touch")),
      pairs: [],
      tableNames: Object.fromEntries(this.listTables().flatMap((t) => (t.name ? [[t.code, t.name]] : []))),
    };
  }

  /** The title of a streak push (§12.2): the table's name when the pair has exactly one shared table, else the partner's. */
  private titled(o: Outgoing, title?: StatusTitle): Outgoing {
    if (!title) return o;
    const names = new Map(this.listTables().map((t) => [t.code, t.name]));
    const only = title.shared.length === 1 ? names.get(title.shared[0] as string) : undefined;
    return { ...o, title: only ?? title.partner };
  }

  /**
   * Sends a push that isn't the game's own (§12.1): status, milestone, play
   * again and pounce answers, under the band rules, quiet hours and spacing.
   * One held back by spacing or a teen's night waits for the alarm.
   */
  async status(o: Outgoing, now: number, title?: StatusTitle): Promise<boolean> {
    const profile = notifyOn(this.env) ? this.pushProfile() : null;
    if (!profile) return false;
    const out = this.titled(o, title);
    const st = this.notify();
    const g = gate({
      kind: out.kind,
      band: profile.band,
      zone: profile.zone ?? FALLBACK_ZONE,
      settings: profile.settings,
      now,
      spacedAt: st.spacedAt,
      remindersToday: st.reminders,
    });
    if (!g.send) {
      if (g.retryAt !== null) {
        this.savePending([...this.pending().filter((p) => p.o.collapse !== out.collapse), { at: g.retryAt, o: out }]);
        await this.arm(now);
      }
      return false;
    }
    noteSent(st, out.kind, now, profile.zone);
    this.saveNotify(st);
    return deliverToPlayer(this.env, profile, out, g.level);
  }

  /** A turn at a shared table (§13.3 flow 1): backoff resets and, with learned timing, the histogram counts it. */
  async recordTurn(at: number, now: number): Promise<void> {
    if (!notifyOn(this.env) || !this.live()) return;
    const st = this.notify();
    const band = this.band();
    noteTurn(st, at, this.getMeta("time_zone"), this.notifySettings().auto && band !== "kitten");
    this.saveNotify(st);
    await this.arm(now);
  }

  private async pairFacts(now: number): Promise<PairFacts[]> {
    const id = this.getMeta("id") as string;
    const rows = this.pairList();
    const all = await Promise.all(
      rows.map(async (row) => {
        const f = await this.env.PAIRS.get(this.env.PAIRS.idFromName(row.pairId))
          .facts(id, now)
          .catch(() => null);
        if (!f) return null;
        const v = f.view as StreakView;
        return {
          pair: v.pair,
          partner: v.partner.name,
          count: v.count,
          me: f.in,
          kept: v.kept,
          paused: f.paused,
          myMove: v.myMove,
          breakId: f.breakId,
          brokeOn: f.brokeOn,
          pinned: row.pinned,
          lastTurnAt: f.lastTurnAt,
          streak: streakBlock(v),
        };
      }),
    );
    return all.filter((f) => f !== null);
  }

  /**
   * The reminder pass (§13.3 flow 5): decides the slots that are due, sends
   * deferred pushes whose time has come, and re-arms. The alarm runs it; so
   * does a test hook with a chosen time.
   */
  async remind(now: number): Promise<void> {
    this.prunePounces(now);
    if (!notifyOn(this.env) || !this.live()) {
      await this.arm(now);
      return;
    }
    const profile = this.pushProfile() as PushProfile;
    const input = this.reminderInput(now);
    if (dueSlots(this.notify(), input).length > 0) {
      input.pairs = await this.pairFacts(now);
      // Decided in one go after the await, so a turn recorded meanwhile isn't overwritten.
      const st = this.notify();
      const out = dueSlots(st, input).map((slot) => decide(st, input, slot));
      this.saveNotify(st);
      for (const { push, level } of out) {
        if (push && level) await deliverToPlayer(this.env, profile, push, level).catch(() => false);
      }
    }
    const due = this.pending().filter((p) => p.at <= now);
    if (due.length > 0) {
      this.savePending(this.pending().filter((p) => p.at > now));
      for (const p of due) await this.status(p.o, now).catch(() => false);
    }
    await this.arm(now);
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
      await forgetLinks(env, id);
      // A kitten's consent record goes with it (parent consent, plan decision 10).
      await endKitten(env, id);
    }
    await this.destroy();
  }
}
