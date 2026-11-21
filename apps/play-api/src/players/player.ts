import { DurableObject } from "cloudflare:workers";

import { addToStats, dish, emptyStats, mergeStats, rankGame, statsView, type BoardRow, type GameBoard, type Stats } from "../daily/board";
import { dailyDay, puzzleNumber, type DailyZone } from "../daily/days";
import { DAILY_TITLES, DISH_APP, listedGames } from "../daily/games";
import { liveMessage, resultMessages, tvsMessage, type BoardAnswer, type DailyEvent } from "../daily/messages";
import { dailyOn } from "../env";
import { endKitten } from "../kittens/kittens";
import { forgetLinks } from "../links/links";
import { deliverToPlayer, type PushProfile } from "../notify/deliver";
import { gate } from "../notify/policy";
import { streakBlock } from "../notify/pushes";
import { decide, dueSlots, emptyNotifyState, nextWake, noteSent, noteTurn, type NotifyState, type PairFacts, type ReminderInput } from "../notify/reminders";
import { notifySettings, type NotifySettings } from "../notify/settings";
import { claimAnswer, KEEP_MS, restingUntil, type Answer, type PounceRow, type Target } from "../pounce/limits";
import { createTables, drawable, listTables, removeTable, upsertTable, type TableEntry } from "../room/tables";
import { addDays, dayKey, FALLBACK_ZONE, type Day } from "../streaks/clock";
import { leaveAllPairs } from "../streaks/pairs";
import { mergePersonal, ownView, recordTurn, type OwnStreak, type Personal } from "../streaks/personal";
import { notifyOn, quietStartMinutes, streaksOn, trophyOn } from "../streaks/profile";

import { IDENTITIES_NAME } from "./identities";
import { mergeSection } from "./state";

import type { DailyResult } from "../daily/module";
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
/** What an account merge carries of the Dish (`exportDaily`, `absorbDaily`). */
export type DailyExport = {
  me: string;
  zone: string | null;
  results: { playerId: string; result: DailyResult }[];
  faces: { playerId: string; name: string; cat: number }[];
  stats: Record<string, Stats>;
  runs: { date: Day; game: string; runId: string; startedAt: number }[];
  tokens: { hash: string; expires: number }[];
};

/** Tries at reporting a daily run to a pair, as a table's report gets. */
const DAILY_STREAK_ATTEMPTS = 2;
/** Daily results are kept this many days (daily games design §6). */
const DAILY_KEEP_DAYS = 120;
const BOARD_PING = '{"t":"ping"}';
const BOARD_PONG = '{"t":"pong"}';
/** Progress reaches the boards at most this often per game. */
const PROGRESS_EVERY_MS = 1000;
/** The headers the Worker sets on a board socket it hands to the player: never a client's own. */
export const BOARD_ROLE_HEADER = "x-pounce-board-role";
export const BOARD_HASH_HEADER = "x-pounce-board-hash";

function closeBoard(ws: WebSocket, reason: string): void {
  try {
    ws.close(1000, reason);
  } catch {
    // Already closing.
  }
}

function sendTo(ws: WebSocket, message: unknown): void {
  try {
    ws.send(JSON.stringify(message));
  } catch {
    // A socket that is closing hears nothing more.
  }
}

/**
 * One instance per player (named by playerId): name and cat, identities,
 * devices, household people, tables, and synced state. A player exists once
 * `touch` creates it; until then (or after `destroy`) room reports are ignored,
 * so a deleted player isn't brought back by a room that hasn't heard yet.
 */
export class Player extends DurableObject<Env> {
  /** When each of this player's games last sent its progress to the boards (at most once a second). */
  private progressAt = new Map<string, number>();
  /** The TV count this player's phones last heard (`tvsChanged`); null: none heard yet. */
  private lastTvs: number | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => this.schema());
    // Board sockets ping; answered without waking the player.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(BOARD_PING, BOARD_PONG));
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
    // The Daily Dish (daily games design §6): this player's and their connections' results, by
    // date, kept 120 days; and this player's lifetime stats per game.
    sql.exec("CREATE TABLE IF NOT EXISTS daily_results (date TEXT, game TEXT, player_id TEXT, result TEXT, PRIMARY KEY (date, game, player_id))");
    sql.exec("CREATE TABLE IF NOT EXISTS daily_stats (game TEXT PRIMARY KEY, stats TEXT)");
    // The name and cat each connection had on their latest result or progress.
    sql.exec("CREATE TABLE IF NOT EXISTS daily_faces (player_id TEXT PRIMARY KEY, name TEXT, cat INTEGER)");
    // Runs this player and their connections are playing now, and how far each got (spoiler-free).
    sql.exec("CREATE TABLE IF NOT EXISTS daily_playing (date TEXT, game TEXT, player_id TEXT, progress REAL, PRIMARY KEY (date, game, player_id))");
    // The run this player plays for each game and date, and when it started: after an account
    // merge it may be one the guest started, so no second run is ever opened.
    sql.exec("CREATE TABLE IF NOT EXISTS daily_runs (date TEXT, game TEXT, run_id TEXT, started_at INTEGER, PRIMARY KEY (date, game))");
    // The hashes of the TV board tokens showing this player's board, and when each expires.
    sql.exec("CREATE TABLE IF NOT EXISTS board_tokens (hash TEXT PRIMARY KEY, expires INTEGER)");
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
    // Board sockets reconnect, and find the account.
    for (const ws of this.ctx.getWebSockets()) closeBoard(ws, "moved");
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
    const partner = this.pairList().find((r) => r.pairId === pairId)?.partnerId;
    this.ctx.storage.sql.exec("DELETE FROM pairs WHERE pair_id = ?", pairId);
    // Their Dish results, name and progress were kept only for this pair's board.
    if (partner !== undefined && this.pairWith(partner) === null) this.forgetDaily(partner);
  }

  /** Forgets someone's Dish data: they're no longer a connection, or they're gone. */
  private forgetDaily(playerId: string): void {
    for (const table of ["daily_results", "daily_faces", "daily_playing"]) {
      this.ctx.storage.sql.exec(`DELETE FROM ${table} WHERE player_id = ?`, playerId);
    }
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

  /** After a merge: the partner `from` is now `to`. Their Dish rows go; `to` shares its own (`shareDaily`). */
  repointPair(pairId: string, to: string): void {
    const old = this.pairList().find((r) => r.pairId === pairId)?.partnerId;
    this.ctx.storage.sql.exec("UPDATE pairs SET partner_id = ? WHERE pair_id = ?", to, pairId);
    if (old !== undefined && old !== to && this.pairWith(old) === null) this.forgetDaily(old);
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
   * The Daily Dish: this player's day now and the zone it runs in (daily games design §2, §3). A
   * reported zone change waits for the next 04:00 (`dailyDay`); the locked zone is kept here.
   * Null for a player that doesn't exist.
   */
  dailyDay(now: number): { day: Day; zone: string } | null {
    if (!this.live()) return null;
    const kept = this.getMeta("daily_zone");
    const { day, zone } = dailyDay(now, kept === null ? null : (JSON.parse(kept) as DailyZone), this.getMeta("time_zone"));
    this.setMeta("daily_zone", JSON.stringify(zone));
    return { day, zone: zone.before ?? zone.zone };
  }

  /**
   * A run of this player's ended (`DailyRun`): keeps the result and the game's stats, and hands
   * the result to each connection's board (`receiveDaily`). `counts`: it counts toward streaks
   * (`countsForStreak`); `endedAt`: when it ended, on the server's clock. Idempotent: a retried
   * report changes nothing.
   */
  async recordDaily(result: DailyResult, counts: boolean, endedAt: number, runId?: string): Promise<void> {
    // A guest merged into an account: the result is the account's. Mid-merge: not yet (the run retries).
    const to = this.getMeta("forward_to");
    if (to !== null) {
      await (this.env.PLAYERS.get(this.env.PLAYERS.idFromName(to)) as unknown as { recordDaily: Player["recordDaily"] }).recordDaily(result, counts, endedAt, runId);
      return;
    }
    if (this.getMeta("retiring") !== null) throw new Error("player_moving");
    if (!this.live()) return;
    // Only the run this player plays for that game and date: after a merge, the other one's result is no one's.
    if (runId !== undefined && this.noteRun(result.date, result.game, runId, endedAt) !== runId) return;
    const me = this.getMeta("id") as string;
    if (!this.storeDaily(me, result)) return;
    this.pushResult("me", me, result);
    // It counts toward your own streak and every pair's, as a turn does (§5), and resets the
    // reminders' backoff (§9). Only with DAILY on. Either way, today's Dish may have closed.
    const now = Date.now();
    if (counts && dailyOn(this.env)) this.ctx.waitUntil(this.recordTurn(endedAt, now));
    else if (notifyOn(this.env)) this.ctx.waitUntil(this.arm(now));
    if (counts && dailyOn(this.env)) {
      this.recordPersonalTurn(endedAt, now);
      if (streaksOn(this.env)) {
        for (const { pairId } of this.pairList()) {
          const pair = this.env.PAIRS.get(this.env.PAIRS.idFromName(pairId));
          // With the same retry as a table's report (§5, "The reporting path").
          this.ctx.waitUntil(
            (async () => {
              for (let attempt = 0; attempt < DAILY_STREAK_ATTEMPTS; attempt++) {
                try {
                  await pair.reportDaily(me, endedAt, now);
                  return;
                } catch {
                  // Tried again below.
                }
              }
              console.error("daily_streak_report_failed");
            })(),
          );
        }
      }
    }
    const kept = this.ctx.storage.sql.exec<{ stats: string }>("SELECT stats FROM daily_stats WHERE game = ?", result.game).toArray()[0];
    const stats = addToStats(kept ? (JSON.parse(kept.stats) as Stats) : null, result);
    this.ctx.storage.sql.exec(
      "INSERT INTO daily_stats (game, stats) VALUES (?, ?) ON CONFLICT (game) DO UPDATE SET stats = excluded.stats",
      result.game,
      JSON.stringify(stats),
    );
    const face = { name: this.getMeta("name") as string, cat: Number(this.getMeta("cat")) };
    for (const { partnerId } of this.pairList()) {
      const partner = this.env.PLAYERS.get(this.env.PLAYERS.idFromName(partnerId)) as unknown as { receiveDaily: Player["receiveDaily"] };
      this.ctx.waitUntil(
        Promise.resolve(partner.receiveDaily(me, face, result)).catch(() => {
          console.error("daily_fanout_failed");
        }),
      );
    }
  }

  /**
   * A connection's results after their account merge (`shareDaily`): each replaces whatever was
   * kept for that game and date, since the merge may have kept a different run.
   */
  receiveDailyMany(from: string, face: { name: string; cat: number }, results: DailyResult[]): void {
    if (!this.live() || this.pairWith(from) === null) return;
    // Everything kept of them goes first: a result the merge dropped leaves no trace.
    this.ctx.storage.sql.exec("DELETE FROM daily_results WHERE player_id = ?", from);
    this.ctx.storage.sql.exec("DELETE FROM daily_playing WHERE player_id = ?", from);
    for (const r of results) this.storeDaily(from, r);
    this.saveFace(from, face);
    if (this.ctx.getWebSockets().length > 0) {
      const now = Date.now();
      this.ctx.waitUntil(
        this.board((this.dailyDay(now) as { day: Day }).day, now).then((board) => {
          for (const ws of this.ctx.getWebSockets()) sendTo(ws, { t: "board", board });
        }),
      );
    }
  }

  /** A connection's result, for this player's board. Only from someone this player is paired with. */
  receiveDaily(from: string, face: { name: string; cat: number }, result: DailyResult): void {
    const pairId = this.live() ? this.pairWith(from) : null;
    if (pairId === null) return;
    // The face after the result: keeping a result prunes faces nobody's results use.
    const fresh = this.storeDaily(from, result);
    this.saveFace(from, face);
    if (fresh) this.pushResult(pairId, from, result);
  }

  private saveFace(playerId: string, face: { name: string; cat: number }): void {
    this.ctx.storage.sql.exec(
      "INSERT INTO daily_faces (player_id, name, cat) VALUES (?, ?, ?) ON CONFLICT (player_id) DO UPDATE SET name = excluded.name, cat = excluded.cat",
      playerId,
      face.name,
      face.cat,
    );
  }

  /** A run ended: it isn't playing any more, and the boards hear the result, then the board as it now stands. */
  private pushResult(handle: string, playerId: string, result: DailyResult): void {
    this.ctx.storage.sql.exec("DELETE FROM daily_playing WHERE date = ? AND game = ? AND player_id = ?", result.date, result.game, playerId);
    if (this.ctx.getWebSockets().length === 0) return;
    const now = Date.now();
    this.ctx.waitUntil(
      this.board((this.dailyDay(now) as { day: Day }).day, now).then((board) => {
        const messages = resultMessages(handle, result, board);
        for (const ws of this.ctx.getWebSockets()) for (const m of messages) sendTo(ws, m);
      }),
    );
  }

  /**
   * A run of this player's tells its boards how it's going (`DailyRun`): this player's own
   * sockets, and each connection's. Progress goes at most once a second per game; watching goes
   * only to TVs.
   */
  dailyEvent(e: DailyEvent, now: number): void {
    if (!this.live()) return;
    const me = this.getMeta("id") as string;
    if (e.k === "progress") {
      if (now - (this.progressAt.get(e.game) ?? 0) < PROGRESS_EVERY_MS) return;
      this.progressAt.set(e.game, now);
    }
    const face = { name: this.getMeta("name") as string, cat: Number(this.getMeta("cat")) };
    this.relayDaily("me", me, face, e);
    for (const { partnerId } of this.pairList()) {
      const partner = this.env.PLAYERS.get(this.env.PLAYERS.idFromName(partnerId)) as unknown as { partnerDaily: Player["partnerDaily"] };
      this.ctx.waitUntil(
        Promise.resolve(partner.partnerDaily(me, face, e)).catch(() => {
          console.error("daily_live_failed");
        }),
      );
    }
  }

  /** A connection's run, for this player's boards. Only from someone this player is paired with. */
  partnerDaily(from: string, face: { name: string; cat: number }, e: DailyEvent): void {
    const pairId = this.live() ? this.pairWith(from) : null;
    if (pairId === null) return;
    this.saveFace(from, face);
    this.relayDaily(pairId, from, face, e);
  }

  private relayDaily(handle: string, playerId: string, face: { name: string; cat: number }, e: DailyEvent): void {
    if (e.k === "progress") {
      this.ctx.storage.sql.exec(
        "INSERT INTO daily_playing (date, game, player_id, progress) VALUES (?, ?, ?, ?) ON CONFLICT (date, game, player_id) DO UPDATE SET progress = excluded.progress",
        e.date,
        e.game,
        playerId,
        e.progress,
      );
      for (const ws of this.ctx.getWebSockets()) sendTo(ws, liveMessage(handle, face, e).message);
      return;
    }
    const { message } = liveMessage(handle, face, e);
    for (const ws of this.ctx.getWebSockets("tv")) sendTo(ws, message);
  }

  /**
   * A board socket (daily games design §6, §8), handed over by the Worker: a phone of this
   * player's, or a TV showing their board (`BOARD_ROLE_HEADER`). It hears the board at once, then
   * results and progress, and a TV hears watching too. It may say nothing but ping.
   */
  async fetch(request: Request): Promise<Response> {
    const role = request.headers.get(BOARD_ROLE_HEADER);
    if (!this.live() || (role !== "phone" && role !== "tv") || request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "content-type": "application/json" } });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, role === "tv" ? ["tv", `tv:${request.headers.get(BOARD_HASH_HEADER) ?? ""}`] : ["phone"]);
    const now = Date.now();
    const board = await this.board((this.dailyDay(now) as { day: Day }).day, now);
    sendTo(server, { t: "board", board });
    if (role === "tv") this.ownTvsChanged();
    else this.lastTvs = board.tvs;
    return new Response(null, { status: 101, webSocket: client });
  }

  /** The TV sockets open now on this player's own board. */
  ownTvs(): number {
    return this.ctx.getWebSockets("tv").filter((ws) => ws.readyState === WebSocket.OPEN).length;
  }

  /** The TVs showing a board this player is on: their own, and their connections' (watch offers reach all of them). */
  private async tvCount(): Promise<number> {
    const partners = await Promise.all(
      this.pairList().map(({ partnerId }) =>
        (this.env.PLAYERS.get(this.env.PLAYERS.idFromName(partnerId)) as unknown as { ownTvs(): Promise<number> }).ownTvs().catch(() => 0),
      ),
    );
    return partners.reduce((a, b) => a + b, this.ownTvs());
  }

  /** This player's phones hear the TV count when it changed. */
  async tvsChanged(): Promise<void> {
    const phones = this.ctx.getWebSockets("phone");
    if (!this.live() || phones.length === 0) {
      this.lastTvs = null;
      return;
    }
    const count = await this.tvCount();
    if (count === this.lastTvs) return;
    this.lastTvs = count;
    for (const ws of this.ctx.getWebSockets("phone")) sendTo(ws, tvsMessage(count));
  }

  /** A TV on this player's own board came or went: their phones hear, and their connections' phones. */
  private ownTvsChanged(): void {
    const tell = (p: Promise<void>) => this.ctx.waitUntil(p.catch(() => undefined));
    tell(this.tvsChanged());
    for (const { partnerId } of this.pairList()) {
      tell((this.env.PLAYERS.get(this.env.PLAYERS.idFromName(partnerId)) as unknown as { tvsChanged(): Promise<void> }).tvsChanged());
    }
  }

  webSocketMessage(ws: WebSocket): void {
    sendTo(ws, { t: "error", error: "not_allowed" });
  }

  webSocketClose(ws: WebSocket, code: number, reason: string): void {
    try {
      ws.close(code, reason);
    } catch {
      // Already closed, or a code that may not be sent back (1005, 1006).
    }
    if (this.ctx.getTags(ws).includes("tv")) this.ownTvsChanged();
  }

  /** A TV was given a board token for this player's board (`ScreenLinks.linkBoard`). */
  addBoardToken(hash: string, expires: number): void {
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO board_tokens (hash, expires) VALUES (?, ?)", hash, expires);
  }

  /** A board token expired: its TV sockets close. */
  boardTokenGone(hash: string): void {
    this.ctx.storage.sql.exec("DELETE FROM board_tokens WHERE hash = ?", hash);
    for (const ws of this.ctx.getWebSockets(`tv:${hash}`)) closeBoard(ws, "expired");
    this.ownTvsChanged();
  }

  /** Unlink: every TV showing this player's board forgets it, and its sockets close. */
  async revokeBoards(): Promise<void> {
    const hashes = this.ctx.storage.sql.exec<{ hash: string }>("SELECT hash FROM board_tokens").toArray().map((r) => r.hash);
    await Promise.all(hashes.map((hash) => this.env.BOARD_TOKENS.get(this.env.BOARD_TOKENS.idFromName(hash)).revoke()));
    this.ctx.storage.sql.exec("DELETE FROM board_tokens");
    for (const ws of this.ctx.getWebSockets("tv")) closeBoard(ws, "revoked");
    this.ownTvsChanged();
  }

  /** The run this player plays for `game` on `date`, if one was started: never open a second. */
  dailyRunFor(date: Day, game: string): string | null {
    return (
      this.ctx.storage.sql.exec<{ run_id: string }>("SELECT run_id FROM daily_runs WHERE date = ? AND game = ?", date, game).toArray()[0]?.run_id ?? null
    );
  }

  /** A run was started (or resumed) for `game` on `date`; the first one noted stays. */
  noteRun(date: Day, game: string, runId: string, startedAt: number): string | null {
    if (!this.live()) return null;
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO daily_runs (date, game, run_id, started_at) VALUES (?, ?, ?, ?)", date, game, runId, startedAt);
    return this.dailyRunFor(date, game);
  }

  /** Everything this player keeps of the Dish, for an account merge (`absorbDaily`). */
  exportDaily(): DailyExport {
    const { sql } = this.ctx.storage;
    return {
      me: this.getMeta("id") ?? "",
      zone: this.getMeta("daily_zone"),
      results: sql
        .exec<{ date: string; game: string; player_id: string; result: string }>("SELECT date, game, player_id, result FROM daily_results")
        .toArray()
        .map((r) => ({ playerId: r.player_id, result: JSON.parse(r.result) as DailyResult })),
      faces: sql.exec<{ player_id: string; name: string; cat: number }>("SELECT player_id, name, cat FROM daily_faces").toArray().map((f) => ({ playerId: f.player_id, name: f.name, cat: f.cat })),
      stats: Object.fromEntries(sql.exec<{ game: string; stats: string }>("SELECT game, stats FROM daily_stats").toArray().map((r) => [r.game, JSON.parse(r.stats) as Stats])),
      runs: sql
        .exec<{ date: string; game: string; run_id: string; started_at: number }>("SELECT date, game, run_id, started_at FROM daily_runs")
        .toArray()
        .map((r) => ({ date: r.date, game: r.game, runId: r.run_id, startedAt: r.started_at })),
      tokens: sql.exec<{ hash: string; expires: number }>("SELECT hash, expires FROM board_tokens").toArray(),
    };
  }

  /**
   * An account merge brings the guest's Dish here (accounts design §13.1). One run per game and
   * date: when both started one, the earlier-started run and its result stay and the other goes.
   * Results, stats, connections' results and TV board tokens come along. Returns the runs to hand
   * to this player (`adopt`) and to delete (`drop`).
   */
  absorbDaily(e: DailyExport): { adopt: string[]; drop: string[]; tokens: string[] } {
    const { sql } = this.ctx.storage;
    const me = this.getMeta("id") ?? "";
    // A retried merge re-applies the plan made the first time, and merges nothing twice.
    const done = this.getMeta(`daily_absorbed:${e.me}`);
    if (done !== null) return JSON.parse(done) as { adopt: string[]; drop: string[]; tokens: string[] };
    const mine = (date: string, game: string) =>
      sql.exec<{ result: string }>("SELECT result FROM daily_results WHERE date = ? AND game = ? AND player_id = ?", date, game, me).toArray()[0];
    const adopt: string[] = [];
    const drop: string[] = [];
    const dropped: DailyResult[] = [];
    /** Games and dates where the guest's run won, and where the account's did. */
    const guestWins = new Set<string>();
    const accountWins = new Set<string>();
    const key = (date: string, game: string) => `${date}|${game}`;
    for (const g of e.runs) {
      const own = sql
        .exec<{ run_id: string; started_at: number }>("SELECT run_id, started_at FROM daily_runs WHERE date = ? AND game = ?", g.date, g.game)
        .toArray()[0];
      if (own && own.run_id === g.runId) continue;
      if (!own || g.startedAt < own.started_at) {
        sql.exec("INSERT OR REPLACE INTO daily_runs (date, game, run_id, started_at) VALUES (?, ?, ?, ?)", g.date, g.game, g.runId, g.startedAt);
        adopt.push(g.runId);
        guestWins.add(key(g.date, g.game));
        if (own) drop.push(own.run_id);
      } else {
        drop.push(g.runId);
        accountWins.add(key(g.date, g.game));
      }
    }
    for (const { playerId, result } of e.results) {
      if (playerId === me) continue;
      if (playerId !== e.me) {
        // A connection's result: the pair moves here too.
        sql.exec("INSERT OR IGNORE INTO daily_results (date, game, player_id, result) VALUES (?, ?, ?, ?)", result.date, result.game, playerId, JSON.stringify(result));
        continue;
      }
      const own = mine(result.date, result.game);
      if (accountWins.has(key(result.date, result.game)) || (own && !guestWins.has(key(result.date, result.game)))) {
        dropped.push(result);
        continue;
      }
      if (own) dropped.push(JSON.parse(own.result) as DailyResult);
      sql.exec("INSERT OR REPLACE INTO daily_results (date, game, player_id, result) VALUES (?, ?, ?, ?)", result.date, result.game, me, JSON.stringify(result));
    }
    // The account's own result for a game and date the guest's run won, with no guest result yet: it goes.
    for (const k of guestWins) {
      const [date, game] = k.split("|") as [string, string];
      const own = mine(date, game);
      if (own && !e.results.some((r) => r.playerId === e.me && r.result.date === date && r.result.game === game)) {
        dropped.push(JSON.parse(own.result) as DailyResult);
        sql.exec("DELETE FROM daily_results WHERE date = ? AND game = ? AND player_id = ?", date, game, me);
      }
    }
    for (const f of e.faces) {
      if (f.playerId !== me) sql.exec("INSERT OR IGNORE INTO daily_faces (player_id, name, cat) VALUES (?, ?, ?)", f.playerId, f.name, f.cat);
    }
    const kept = new Map(sql.exec<{ game: string; stats: string }>("SELECT game, stats FROM daily_stats").toArray().map((r) => [r.game, JSON.parse(r.stats) as Stats]));
    for (const game of new Set([...kept.keys(), ...Object.keys(e.stats)])) {
      const merged = mergeStats(kept.get(game) ?? null, e.stats[game] ?? null, dropped.filter((r) => r.game === game));
      if (merged) sql.exec("INSERT OR REPLACE INTO daily_stats (game, stats) VALUES (?, ?)", game, JSON.stringify(merged));
    }
    for (const t of e.tokens) sql.exec("INSERT OR REPLACE INTO board_tokens (hash, expires) VALUES (?, ?)", t.hash, t.expires);
    if (this.getMeta("daily_zone") === null && e.zone !== null) this.setMeta("daily_zone", e.zone);
    const plan = { adopt, drop, tokens: e.tokens.map((t) => t.hash) };
    this.setMeta(`daily_absorbed:${e.me}`, JSON.stringify(plan));
    return plan;
  }

  /** After an account merge: each connection gets this player's results, in place of what it kept. */
  shareDaily(): void {
    if (!this.live()) return;
    const me = this.getMeta("id") as string;
    const results = this.ctx.storage.sql
      .exec<{ result: string }>("SELECT result FROM daily_results WHERE player_id = ?", me)
      .toArray()
      .map((r) => JSON.parse(r.result) as DailyResult);
    // Sent even with none: a connection drops whatever the merge dropped.
    const face = { name: this.getMeta("name") as string, cat: Number(this.getMeta("cat")) };
    for (const { partnerId } of this.pairList()) {
      const partner = this.env.PLAYERS.get(this.env.PLAYERS.idFromName(partnerId)) as unknown as { receiveDailyMany: Player["receiveDailyMany"] };
      this.ctx.waitUntil(
        Promise.resolve(partner.receiveDailyMany(me, face, results)).catch(() => {
          console.error("daily_share_failed");
        }),
      );
    }
  }

  /** Keeps a result unless it is already kept, or older than 120 days. False: nothing new. */
  private storeDaily(playerId: string, result: DailyResult): boolean {
    this.pruneDaily(Date.now());
    if (result.date < this.dailyCutoff(Date.now())) return false;
    const had = this.ctx.storage.sql
      .exec("SELECT 1 FROM daily_results WHERE date = ? AND game = ? AND player_id = ?", result.date, result.game, playerId)
      .toArray().length;
    if (had > 0) return false;
    this.ctx.storage.sql.exec(
      "INSERT INTO daily_results (date, game, player_id, result) VALUES (?, ?, ?, ?)",
      result.date,
      result.game,
      playerId,
      JSON.stringify(result),
    );
    return true;
  }

  /** The oldest date whose results are kept: 120 days before this player's day. */
  private dailyCutoff(now: number): Day {
    return addDays(dayKey(now, this.zone()), -DAILY_KEEP_DAYS);
  }

  /** Forgets results past 120 days, and the faces of people with none left. */
  private pruneDaily(now: number): void {
    const { sql } = this.ctx.storage;
    const cutoff = this.dailyCutoff(now);
    sql.exec("DELETE FROM daily_results WHERE date < ?", cutoff);
    sql.exec("DELETE FROM daily_runs WHERE date < ?", cutoff);
    // A run is playing only on its own date: anything older closed at 04:00.
    sql.exec("DELETE FROM daily_playing WHERE date < ?", addDays(dayKey(now, this.zone()), -1));
    sql.exec("DELETE FROM daily_faces WHERE player_id NOT IN (SELECT player_id FROM daily_results UNION SELECT player_id FROM daily_playing)");
  }

  /**
   * This player's board for `date` (daily games design §6): this player and their connections,
   * per game and overall. Who is on it is read now, so a pair that is left drops off. Rows name
   * this player "me" and a connection by its pair id: no player id leaves the server.
   */
  async board(date: Day, now: number): Promise<BoardAnswer> {
    return { ...this.boardRows(date, now), tvs: await this.tvCount() };
  }

  private boardRows(date: Day, now: number): Omit<BoardAnswer, "tvs"> {
    this.pruneDaily(now);
    const me = this.getMeta("id") ?? "";
    const handles = new Map<string, string>([[me, "me"]]);
    for (const p of this.pairList()) handles.set(p.partnerId, p.pairId);
    const faces = new Map<string, { name: string; cat: number }>(
      this.ctx.storage.sql
        .exec<{ player_id: string; name: string; cat: number }>("SELECT player_id, name, cat FROM daily_faces")
        .toArray()
        .map((f) => [f.player_id, { name: f.name, cat: f.cat }]),
    );
    faces.set(me, { name: this.getMeta("name") ?? "", cat: Number(this.getMeta("cat") ?? 0) });
    const rows = this.ctx.storage.sql
      .exec<{ game: string; player_id: string; result: string }>("SELECT game, player_id, result FROM daily_results WHERE date = ?", date)
      .toArray();
    const playing = this.ctx.storage.sql
      .exec<{ game: string; player_id: string; progress: number }>("SELECT game, player_id, progress FROM daily_playing WHERE date = ?", date)
      .toArray();
    const shown = (id: string) => handles.has(id) && faces.has(id);
    const rowOf = (id: string, result: DailyResult | null, progress: number | null): BoardRow => {
      const face = faces.get(id) as { name: string; cat: number };
      return { player: handles.get(id) as string, name: face.name, cat: face.cat, rank: null, result, playing: progress === null ? null : { progress } };
    };
    const games = listedGames(this.env).map((m): GameBoard => {
      const done = rows.filter((r) => r.game === m.id && shown(r.player_id));
      const inPlay = playing.filter((r) => r.game === m.id && shown(r.player_id) && !done.some((d) => d.player_id === r.player_id));
      const all = [...done.map((r) => rowOf(r.player_id, JSON.parse(r.result) as DailyResult, null)), ...inPlay.map((r) => rowOf(r.player_id, null, r.progress))];
      return { game: m.id, number: puzzleNumber(date), rows: rankGame(m, all) };
    });
    return { date, games, dish: dish(games) };
  }

  /** This player's stats for each listed game, as shown on `today`. */
  dailyStats(today: Day): Record<string, Stats> {
    const kept = new Map(
      this.ctx.storage.sql
        .exec<{ game: string; stats: string }>("SELECT game, stats FROM daily_stats")
        .toArray()
        .map((r) => [r.game, JSON.parse(r.stats) as Stats]),
    );
    return Object.fromEntries(listedGames(this.env).map((m) => [m.id, statsView(kept.get(m.id) ?? emptyStats(), today)]));
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
    // No TV keeps showing a board that's gone.
    await this.revokeBoards().catch(() => undefined);
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
    this.pruneDaily(now);
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
    // Tables only a newer app can open: a reminder that points at one says what an older app gets.
    const newerOnly = this.listTables().flatMap((t) => (drawable(t.game, []) ? [] : [t.code]));
    return {
      now,
      zone: this.getMeta("time_zone"),
      band: this.band(),
      settings: this.notifySettings(),
      name: (this.getMeta("name") as string | null) ?? "",
      lastOpenAt: this.getMeta("last_touch") === null ? null : Number(this.getMeta("last_touch")),
      pairs: [],
      tableNames: Object.fromEntries(this.listTables().flatMap((t) => (t.name ? [[t.code, t.name]] : []))),
      ...(newerOnly.length > 0 ? { newerOnly } : {}),
    };
  }

  /** One of this player's devices runs an app that has the Dish (it lists `dish` in `X-Pounce-Games`). */
  private async dishApp(): Promise<boolean> {
    const found = await Promise.all(
      this.deviceIds().map((d) =>
        this.env.DEVICES.get(this.env.DEVICES.idFromName(d))
          .players()
          .then((p) => p.games.includes(DISH_APP))
          .catch(() => false),
      ),
    );
    return found.some(Boolean);
  }

  /**
   * Today's Dish, while this player has ended no daily run today (daily games design §9): the
   * first game they haven't played, for the daily reminder. Null once they've played.
   */
  private openDish(now: number): { game: string; title: string; number: number } | null {
    const kept = this.getMeta("daily_zone");
    const today = dailyDay(now, kept === null ? null : (JSON.parse(kept) as DailyZone), this.getMeta("time_zone")).day;
    const mine = this.ctx.storage.sql
      .exec<{ game: string; result: string }>("SELECT game, result FROM daily_results WHERE date = ? AND player_id = ?", today, this.getMeta("id"))
      .toArray();
    if (mine.some((r) => (JSON.parse(r.result) as DailyResult).outcome !== "closed")) return null;
    const next = listedGames(this.env).find((m) => !mine.some((r) => r.game === m.id));
    return next ? { game: next.id, title: DAILY_TITLES[next.id], number: puzzleNumber(today) } : null;
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
      // The Dish counts only when one of this player's devices has an app that has it.
      if (dailyOn(this.env) && (await this.dishApp())) input.dish = this.openDish(now);
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
