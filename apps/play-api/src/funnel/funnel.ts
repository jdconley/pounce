/**
 * The first-run funnel (first-run funnel design, Part 3): when each device first reached each
 * step, in a SQL database (`FUNNEL`, D1) that can be queried by hand (docs/funnel.md).
 *
 * Anonymous by construction: a device is kept under a keyed hash of its id, never the id itself,
 * and nothing here holds a name, a player, an account, a table code or an address. What a device
 * brings is its platform, app version, a language and region ("en-US"), and how it first came
 * (an invite link, a pasted invite, or on its own).
 *
 * Nothing here may slow or break a request: every call is meant for `waitUntil`, and without the
 * database or the token secret every call does nothing.
 */

import { isAppMilestone, isSource, type AppMilestone, type Milestone, type ServerMilestone, type Source } from "./milestones";

import type { AppIdentity } from "../app/version";

export type FunnelEnv = { FUNNEL?: D1Database; TOKEN_SECRET?: string };

const DAY_MS = 86_400_000;
/** Activity is kept for each of a device's first 90 days (day 1, day 7, day 30 return). */
const MAX_DAY = 90;
/** How long ago an app may say it reached a step it couldn't send then (offline): 30 days. */
const MAX_AGO_S = 30 * 86_400;
/** More milestones than the app has in one report is not a report. */
const MAX_REACHED = 20;
/** A language, optionally with a region: "en", "en-US", "pt-BR". */
const LOCALE = /^[a-z]{2,3}(?:-[A-Z]{2})?$/;
/** A version or game id, as the server keeps them: short, plain. */
const PLAIN = /^[a-z0-9][a-z0-9.-]{0,23}$/;

/** The tables. Created by the Worker itself the first time it needs them (`ready`). */
export const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    created_at INTEGER,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    platform TEXT,
    app_version TEXT,
    locale TEXT,
    source TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS milestones (
    id TEXT NOT NULL,
    milestone TEXT NOT NULL,
    at INTEGER NOT NULL,
    game TEXT,
    app_version TEXT,
    PRIMARY KEY (id, milestone)
  )`,
  `CREATE INDEX IF NOT EXISTS milestones_by_step ON milestones (milestone, at)`,
  `CREATE TABLE IF NOT EXISTS device_days (
    id TEXT NOT NULL,
    day INTEGER NOT NULL,
    PRIMARY KEY (id, day)
  )`,
  `CREATE TABLE IF NOT EXISTS page_views (
    day TEXT NOT NULL,
    page TEXT NOT NULL,
    views INTEGER NOT NULL,
    PRIMARY KEY (day, page)
  )`,
];

const DEVICE_UPSERT = `INSERT INTO devices (id, created_at, first_seen, last_seen, platform, app_version, locale, source)
  VALUES (?1, ?2, ?3, ?3, ?4, ?5, ?6, ?7)
  ON CONFLICT (id) DO UPDATE SET
    created_at = COALESCE(devices.created_at, excluded.created_at),
    last_seen = MAX(devices.last_seen, excluded.last_seen),
    platform = COALESCE(excluded.platform, devices.platform),
    app_version = COALESCE(excluded.app_version, devices.app_version),
    locale = COALESCE(excluded.locale, devices.locale),
    source = CASE WHEN devices.source IS NULL OR devices.source = 'organic' THEN COALESCE(excluded.source, devices.source)
      ELSE devices.source END`;

/** First time wins: a step sent again, or sent late with an earlier time, keeps the earliest. */
const MILESTONE_UPSERT = `INSERT INTO milestones (id, milestone, at, game, app_version) VALUES (?1, ?2, ?3, ?4, ?5)
  ON CONFLICT (id, milestone) DO UPDATE SET at = excluded.at, game = excluded.game, app_version = excluded.app_version
  WHERE excluded.at < milestones.at`;

/** The day of the device's life this is (0 is the day it was minted), for a device minted since tracking began. */
const DAY_INSERT = `INSERT OR IGNORE INTO device_days (id, day)
  SELECT id, CAST((?2 - created_at) / ${DAY_MS} AS INTEGER) FROM devices
  WHERE id = ?1 AND created_at IS NOT NULL AND ?2 >= created_at AND CAST((?2 - created_at) / ${DAY_MS} AS INTEGER) <= ${MAX_DAY}`;

const SEEN_UPDATE = `UPDATE devices SET last_seen = MAX(last_seen, ?2) WHERE id = ?1`;

const VIEW_UPSERT = `INSERT INTO page_views (day, page, views) VALUES (?1, ?2, 1)
  ON CONFLICT (day, page) DO UPDATE SET views = views + 1`;

const ready = new WeakMap<D1Database, Promise<unknown>>();

/** Creates the tables once per isolate and database; a failure is tried again on the next call. */
function ensureSchema(db: D1Database): Promise<unknown> {
  let done = ready.get(db);
  if (!done) {
    done = db.batch(SCHEMA.map((sql) => db.prepare(sql))).catch((error: unknown) => {
      ready.delete(db);
      throw error;
    });
    ready.set(db, done);
  }
  return done;
}

const keys = new Map<string, Promise<CryptoKey>>();

/** The HMAC key for funnel ids: derived from the token secret, so no new secret is needed. */
function funnelKey(secret: string): Promise<CryptoKey> {
  let key = keys.get(secret);
  if (!key) {
    const raw = new TextEncoder().encode(`funnel:${secret}`);
    key = crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    keys.set(secret, key);
  }
  return key;
}

/** The device as the funnel knows it: 22 characters of a keyed hash of its id. */
export async function funnelId(secret: string, deviceId: string): Promise<string> {
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await funnelKey(secret), new TextEncoder().encode(deviceId)));
  let bin = "";
  for (const b of mac.subarray(0, 16)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The database, ready, and the key to hash ids with; null when the funnel is off. */
async function open(env: FunnelEnv): Promise<{ db: D1Database; secret: string } | null> {
  const db = env.FUNNEL;
  const secret = env.TOKEN_SECRET;
  if (!db || !secret) return null;
  await ensureSchema(db);
  return { db, secret };
}

const plain = (text: string | null | undefined): string | null => (text && PLAIN.test(text) ? text : null);

/** `POST /v1/devices` minted `deviceId`: the device's row, and its first step. */
export async function minted(env: FunnelEnv, deviceId: string, now: number, app: AppIdentity | null): Promise<void> {
  const on = await open(env);
  if (!on) return;
  const id = await funnelId(on.secret, deviceId);
  const version = plain(app?.version);
  await on.db.batch([
    on.db.prepare(DEVICE_UPSERT).bind(id, now, now, plain(app?.platform), version, null, null),
    on.db.prepare(MILESTONE_UPSERT).bind(id, "device_created", now, null, version),
    on.db.prepare(DAY_INSERT).bind(id, now),
  ]);
}

/** One step the server saw a device reach. */
export type Reached = { deviceId: string; milestone: ServerMilestone; game?: string };

/** Steps the server saw, all at `now`. Each device's first time is the one kept. */
export async function reached(env: FunnelEnv, steps: readonly Reached[], now: number): Promise<void> {
  if (steps.length === 0) return;
  const on = await open(env);
  if (!on) return;
  const statements = await Promise.all(
    steps.map(async ({ deviceId, milestone, game }) =>
      on.db.prepare(MILESTONE_UPSERT).bind(await funnelId(on.secret, deviceId), milestone, now, plain(game), null),
    ),
  );
  await on.db.batch(statements);
}

/** What an app reports (`POST /v1/funnel`): steps with how many seconds ago each was reached. */
export type Report = { reached: [AppMilestone, number][]; source: Source | null; locale: string | null };

/**
 * The body of `POST /v1/funnel`, or null for one that isn't a report:
 * `{"reached": {"age_done": 12, "named": 0}, "source": "join_link", "locale": "en-US"}`.
 * Only those three keys. A step this server doesn't know, or a time it can't use, is left out
 * (a newer app may know more steps); an unknown source or a locale that isn't one is refused.
 */
export function parseReport(body: Record<string, unknown> | null): Report | null {
  if (!body || Object.keys(body).some((key) => key !== "reached" && key !== "source" && key !== "locale")) return null;
  const { reached: steps, source, locale } = body;
  if (typeof steps !== "object" || steps === null || Array.isArray(steps)) return null;
  const entries = Object.entries(steps);
  if (entries.length > MAX_REACHED) return null;
  if (source !== undefined && !isSource(source)) return null;
  if (locale !== undefined && (typeof locale !== "string" || !LOCALE.test(locale))) return null;
  const kept = entries.flatMap(([milestone, ago]): [AppMilestone, number][] =>
    isAppMilestone(milestone) && Number.isInteger(ago) && (ago as number) >= 0 && (ago as number) <= MAX_AGO_S
      ? [[milestone, ago as number]]
      : [],
  );
  return { reached: kept, source: source ?? null, locale: (locale as string | undefined) ?? null };
}

/** An app's report: its row (version, locale, how it came), its steps, and that it was in use today. */
export async function report(env: FunnelEnv, deviceId: string, sent: Report, now: number, app: AppIdentity | null): Promise<void> {
  const on = await open(env);
  if (!on) return;
  const id = await funnelId(on.secret, deviceId);
  const version = plain(app?.version);
  await on.db.batch([
    on.db.prepare(DEVICE_UPSERT).bind(id, null, now, plain(app?.platform), version, sent.locale, sent.source),
    ...sent.reached.map(([milestone, ago]) => on.db.prepare(MILESTONE_UPSERT).bind(id, milestone, now - ago * 1000, null, version)),
    on.db.prepare(DAY_INSERT).bind(id, now),
  ]);
}

/** When this isolate last wrote each device's activity: at most once an hour per device. */
const lastActive = new Map<string, number>();
const ACTIVE_EVERY_MS = 3_600_000;
const MAX_REMEMBERED = 10_000;

/** The device was in use (it opened a table or Home's list): day 1 and day 7 return come from this. */
export async function active(env: FunnelEnv, deviceId: string, now: number): Promise<void> {
  const last = lastActive.get(deviceId);
  if (last !== undefined && now - last < ACTIVE_EVERY_MS) return;
  if (lastActive.size >= MAX_REMEMBERED) lastActive.clear();
  lastActive.set(deviceId, now);
  const on = await open(env);
  if (!on) return;
  const id = await funnelId(on.secret, deviceId);
  await on.db.batch([on.db.prepare(SEEN_UPDATE).bind(id, now), on.db.prepare(DAY_INSERT).bind(id, now)]);
}

/** Link preview fetchers (Messages, social apps, crawlers): their views are counted apart. */
const PREVIEW_AGENT = /facebookexternalhit|facebot|twitterbot|slackbot|discordbot|whatsapp|telegrambot|linkedinbot|bot\b|crawler|spider/i;

/**
 * One view of an invite page on the web (`j`: a table link, `p`: a request to play), counted per
 * UTC day. Nothing about the viewer is kept. A link preview's fetch counts as `j_preview` or
 * `p_preview`: roughly one per invite sent through Messages.
 */
export async function pageView(env: FunnelEnv, page: "j" | "p", userAgent: string | null, now: number): Promise<void> {
  const on = await open(env);
  if (!on) return;
  const kind = PREVIEW_AGENT.test(userAgent ?? "") ? `${page}_preview` : page;
  await on.db.prepare(VIEW_UPSERT).bind(new Date(now).toISOString().slice(0, 10), kind).run();
}

/** Deletes everything the funnel holds for a device (its data was deleted in the app). */
export async function forget(env: FunnelEnv, deviceId: string): Promise<void> {
  const on = await open(env);
  if (!on) return;
  const id = await funnelId(on.secret, deviceId);
  await on.db.batch(
    ["DELETE FROM milestones WHERE id = ?1", "DELETE FROM device_days WHERE id = ?1", "DELETE FROM devices WHERE id = ?1"].map((sql) =>
      on.db.prepare(sql).bind(id),
    ),
  );
}

/** Drops this isolate's memory of activity (tests). */
export function resetActivity(): void {
  lastActive.clear();
}

export type { Milestone };
