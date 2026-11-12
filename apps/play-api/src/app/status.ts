import { cleanVersion, olderThan, tooOld, type AppIdentity } from "./version";

/**
 * What is current (app updates design §3): the version live on the App Store, the oldest version
 * the server still supports, and where to get a newer one. One rule runs through all of it:
 * nobody is told to update to a version they can't download.
 */

/** Pounce on the App Store. `APP_STORE_URL` carries the same id once the app is released. */
export const APP_STORE_ID = "6829560061";

/** Apple's public lookup: no key, no cookie, and nothing about who is asking us. */
export const lookupUrl = (id: string): string => `https://itunes.apple.com/lookup?id=${id}`;

/** How long an answer from Apple is fresh: after this it is still used, and asked for again in the background. */
export const FOUND_TTL_S = 6 * 60 * 60;
/** How long before Apple is asked again after "not listed" or a failed lookup. */
export const MISSING_TTL_S = 15 * 60;
/** How long the last answer is kept at all. Far past its freshness: a stale answer beats none. */
export const KEEP_S = 30 * 24 * 60 * 60;
const LOOKUP_TIMEOUT_MS = 3000;
const MAX_LOOKUP_BYTES = 262_144;

/** The version Apple says is live, from a lookup's JSON; null when the listing isn't there or names none. */
export function readLookup(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const { resultCount, results } = body as { resultCount?: unknown; results?: unknown };
  if (resultCount !== 1 || !Array.isArray(results)) return null;
  const first: unknown = results[0];
  if (typeof first !== "object" || first === null) return null;
  return cleanVersion((first as { version?: unknown }).version);
}

/** Somewhere to keep the last answer: this isolate and the Worker's cache in production, a map in tests. */
export type Remembered = {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, ttlSeconds: number): Promise<void>;
};

export type LatestEnv = { APP_LATEST?: string; APP_STORE_URL?: string; APP_LOOKUP?: string };

/** The App Store id in `APP_STORE_URL`, else Pounce's own. */
export function storeId(env: Pick<LatestEnv, "APP_STORE_URL">): string {
  return /^https:\/\/\S*\/id(\d{6,12})(?:[/?#]|$)/.exec(env.APP_STORE_URL ?? "")?.[1] ?? APP_STORE_ID;
}

/**
 * What is remembered of Apple's lookup. `version`: the last version Apple named, kept through
 * later failures and "not listed" answers (a version once live doesn't stop being so; a lookup
 * that fails says nothing). `tried`: when Apple was last asked, and `ok` whether it named a
 * version then, which decides when to ask again.
 */
export type LookupRecord = { version: string | null; tried: number; ok: boolean };

const recordKey = (id: string) => `app-latest:${id}`;

function parseRecord(text: string | null): LookupRecord | null {
  try {
    const value = JSON.parse(text ?? "null") as Partial<LookupRecord> | null;
    if (typeof value !== "object" || value === null || typeof value.tried !== "number") return null;
    return { version: cleanVersion(value.version), tried: value.tried, ok: value.ok === true };
  } catch {
    return null;
  }
}

async function readRecord(memory: Remembered, id: string): Promise<LookupRecord | null> {
  try {
    return parseRecord(await memory.get(recordKey(id)));
  } catch {
    // A memory that can't be read is an empty one.
    return null;
  }
}

async function writeRecord(memory: Remembered, id: string, record: LookupRecord): Promise<void> {
  try {
    await memory.put(recordKey(id), JSON.stringify(record), KEEP_S);
  } catch {
    // Not kept: this isolate asks again when it next looks.
  }
}

/** Apple should be asked again: never asked, or the last answer has had its time. A clock set back counts as time passed. */
export function lookupDue(record: LookupRecord | null, now: number): boolean {
  if (record === null) return true;
  const age = now - record.tried;
  return age < 0 || age >= (record.ok ? FOUND_TTL_S : MISSING_TTL_S) * 1000;
}

/** Lookups on their way, by store id, in this isolate: a second asker waits on the first, and never starts another. */
const inFlight = new Map<string, Promise<void>>();

/**
 * Asks Apple's public lookup and writes down what it said. One at a time per isolate; and Apple
 * is marked as asked before the request leaves, so however many requests arrive while it is out,
 * and however it ends, nobody asks again until the next one is due. Never throws.
 */
export function refreshLookup(env: LatestEnv, memory: Remembered, fetcher: typeof fetch, now: () => number): Promise<void> {
  const id = storeId(env);
  const running = inFlight.get(id);
  if (running) return running;
  const run = (async () => {
    const before = await readRecord(memory, id);
    // Another isolate asked in the meantime.
    if (!lookupDue(before, now())) return;
    const kept = before?.version ?? null;
    await writeRecord(memory, id, { version: kept, tried: now(), ok: false });
    const found = await askApple(id, fetcher);
    await writeRecord(memory, id, { version: found ?? kept, tried: now(), ok: found !== null });
  })().finally(() => inFlight.delete(id));
  inFlight.set(id, run);
  return run;
}

/**
 * The version Apple last said is live on the App Store, or null when it never has: the app isn't
 * listed yet, or Apple hasn't been reached. **Never waits on Apple**: it answers from what is
 * remembered, however old, and when that has had its time it hands a lookup to `background`
 * (`ctx.waitUntil` in the Worker) for the next asker. `APP_LOOKUP=off` never asks.
 *
 * Without a `background` it only reads. A caller that can't promise the lookup will be let
 * finish must not start one: Apple is marked as asked before the request leaves, and a lookup
 * cut short after that would leave nobody asking again for a quarter of an hour.
 */
export async function storeVersion(
  env: LatestEnv,
  memory: Remembered,
  fetcher: typeof fetch,
  now: () => number,
  background?: (work: Promise<void>) => void,
): Promise<string | null> {
  if ((env.APP_LOOKUP ?? "").trim().toLowerCase() === "off") return null;
  const record = await readRecord(memory, storeId(env));
  if (background && lookupDue(record, now())) background(refreshLookup(env, memory, fetcher, now));
  return record?.version ?? null;
}

/**
 * What the server knows of the App Store, in two parts that must not be confused:
 * - `store`: what Apple itself said is live. Only this lets `APP_MINIMUM` turn anyone away.
 * - `latest`: what apps are told is the newest version, for the soft card and the update push.
 *   The same, unless `APP_LATEST` overrides it (a version, or "off" for "say nothing").
 */
export type Known = { store: string | null; latest: string | null };

export function known(env: Pick<LatestEnv, "APP_LATEST">, store: string | null): Known {
  const fixed = (env.APP_LATEST ?? "").trim();
  return { store, latest: fixed === "" ? store : cleanVersion(fixed) };
}

async function askApple(id: string, fetcher: typeof fetch): Promise<string | null> {
  try {
    // Nothing of the asking app's request goes along: no header, no address, no id of theirs.
    // Bounded twice over: the request is aborted at the timeout, and given up on just after
    // even if it ignores that, so a lookup on its way can never hold the next one back for good.
    let timer: ReturnType<typeof setTimeout> | undefined;
    const gaveUp = new Promise<null>((resolve) => (timer = setTimeout(() => resolve(null), LOOKUP_TIMEOUT_MS + 500)));
    const asked = fetcher(lookupUrl(id), { headers: { accept: "application/json" }, signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS) });
    const res = await Promise.race([asked, gaveUp]).finally(() => clearTimeout(timer));
    if (res === null || !res.ok) return null;
    const text = await res.text();
    if (text.length > MAX_LOOKUP_BYTES) return null;
    return readLookup(JSON.parse(text));
  } catch {
    return null;
  }
}

export type StatusEnv = LatestEnv & { APP_MINIMUM?: string; APP_MINIMUM_FORCE?: string; TESTFLIGHT_URL?: string };

const https = (url: string | undefined): string | null => (url?.startsWith("https://") ? url : null);

const isOn = (flag: string | undefined): boolean => ["on", "1", "true"].includes((flag ?? "").trim().toLowerCase());

/**
 * The oldest version still supported, as it is enforced: `APP_MINIMUM`, but only once the App
 * Store has a version at least that new, **as Apple's own lookup said** (`k.store`). Until then
 * there is no minimum, so one set too early, or mistyped as a version that doesn't exist, locks
 * nobody out of the version they have.
 *
 * `APP_LATEST` never satisfies this: it is the server's word, not Apple's, and pairing it with
 * `APP_MINIMUM` for an unreleased version would turn away everyone below it with nothing to
 * update to. Only `APP_MINIMUM_FORCE=on` lifts the guard: then the minimum is enforced whatever
 * Apple says, which is the owner saying "I know that version is out".
 */
export function enforcedMinimum(env: Pick<StatusEnv, "APP_MINIMUM" | "APP_MINIMUM_FORCE">, k: Pick<Known, "store">): string | null {
  const minimum = cleanVersion(env.APP_MINIMUM);
  if (minimum === null) return null;
  if (isOn(env.APP_MINIMUM_FORCE)) return minimum;
  if (k.store === null || olderThan(k.store, minimum)) return null;
  return minimum;
}

/** `GET /v1/app`: every key is left out when it isn't known. */
export type AppStatus = { latest?: string; minimum?: string; storeUrl?: string; testflightUrl?: string };

/** Where the store listing is, said only while there is something on it to get. */
function links(env: StatusEnv, listed: boolean): Pick<AppStatus, "storeUrl" | "testflightUrl"> {
  const store = listed ? (https(env.APP_STORE_URL) ?? `https://apps.apple.com/app/id${storeId(env)}`) : null;
  const beta = https(env.TESTFLIGHT_URL);
  return { ...(store ? { storeUrl: store } : {}), ...(beta ? { testflightUrl: beta } : {}) };
}

export function appStatus(env: StatusEnv, k: Known): AppStatus {
  const minimum = enforcedMinimum(env, k);
  return {
    ...(k.latest === null ? {} : { latest: k.latest }),
    ...(minimum === null ? {} : { minimum }),
    ...links(env, k.latest !== null || k.store !== null || minimum !== null),
  };
}

/** The answer to an app that is too old (426): what it needs, and where to get it. */
export type UpdateRequired = { error: "update_required"; minimum?: string } & Pick<AppStatus, "storeUrl" | "testflightUrl">;

/**
 * The refusal for this app, or null when it is served. Asks what is known of the App Store only
 * for an app `APP_MINIMUM` or the protocol would turn away, so every other request reads nothing;
 * and what is known is all it asks for (`store` never waits on Apple).
 */
export async function refusalFor(
  app: AppIdentity | null,
  env: StatusEnv,
  minProtocol: number,
  store: () => Promise<string | null>,
): Promise<UpdateRequired | null> {
  const wanted = cleanVersion(env.APP_MINIMUM);
  if (!tooOld(app, { minimum: wanted, minProtocol })) return null;
  const k = known(env, await store());
  const minimum = enforcedMinimum(env, k);
  // Turned away by the version: only once Apple says that version can be downloaded.
  if (!tooOld(app, { minimum, minProtocol })) return null;
  return { error: "update_required", ...(minimum === null ? {} : { minimum }), ...links(env, k.store !== null || minimum !== null) };
}

/** The header a refusal carries, since a refused socket upgrade's body can't be read by the app. */
export const UPDATE_HEADER = "x-pounce-update";
/** `X-Pounce-Update: required`: this app is too old for the server. */
export const UPDATE_REQUIRED = "required";
/** `X-Pounce-Update: game`: this table's game needs a newer app (`X-Pounce-Game`, `X-Pounce-Game-Title`). */
export const UPDATE_GAME = "game";
export const GAME_HEADER = "x-pounce-game";
export const GAME_TITLE_HEADER = "x-pounce-game-title";

/** The answer to an app that said what it is and can't draw this table's game (426). */
export type GameUnsupported = { error: "game_unsupported"; game: string; title: string };

export function gameUnsupported(game: string, title: string): { body: GameUnsupported; headers: Record<string, string> } {
  return {
    body: { error: "game_unsupported", game, title },
    headers: { [UPDATE_HEADER]: UPDATE_GAME, [GAME_HEADER]: game, [GAME_TITLE_HEADER]: encodeURIComponent(title) },
  };
}

/**
 * The one frame a version 1.0 socket is sent when 1.0 is no longer supported: a snapshot of a
 * protocol it doesn't speak. 1.0 reads `t` and `protocol` and nothing else of it, stops the
 * socket, and shows its own "Update the app to play" card (design §6).
 */
export const RETIRED_SNAPSHOT = JSON.stringify({ t: "snapshot", protocol: 0 });
