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

/** How long an answer from Apple is believed. */
export const FOUND_TTL_S = 6 * 60 * 60;
/** How long "not there" or a failed lookup is, so a missing listing costs Apple one request a quarter hour. */
export const MISSING_TTL_S = 15 * 60;
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

/** Somewhere to keep the last answer for a while: the Worker's cache in production, a map in tests. */
export type Remembered = {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, ttlSeconds: number): Promise<void>;
};

export type LatestEnv = { APP_LATEST?: string; APP_STORE_URL?: string; APP_LOOKUP?: string };

const MISSING = "-";

/** The App Store id in `APP_STORE_URL`, else Pounce's own. */
export function storeId(env: Pick<LatestEnv, "APP_STORE_URL">): string {
  return /^https:\/\/\S*\/id(\d{6,12})(?:[/?#]|$)/.exec(env.APP_STORE_URL ?? "")?.[1] ?? APP_STORE_ID;
}

/**
 * The version live on the App Store, or null when that isn't known: the app isn't listed yet, or
 * Apple couldn't be asked. `APP_LATEST` overrides the lookup (a version: that one; "off": none,
 * and Apple is never asked). Otherwise Apple's public lookup is asked, at most once per
 * `FOUND_TTL_S` (or `MISSING_TTL_S` after a miss) per cache. Never throws.
 */
export async function latestVersion(env: LatestEnv, memory: Remembered, fetcher: typeof fetch): Promise<string | null> {
  const fixed = (env.APP_LATEST ?? "").trim();
  if (fixed !== "") return cleanVersion(fixed);
  if ((env.APP_LOOKUP ?? "").trim().toLowerCase() === "off") return null;
  const id = storeId(env);
  const key = `app-latest:${id}`;
  try {
    const kept = await memory.get(key);
    if (kept !== null) return kept === MISSING ? null : cleanVersion(kept);
  } catch {
    // A cache that can't be read is an empty one.
  }
  const found = await askApple(id, fetcher);
  try {
    await memory.put(key, found ?? MISSING, found === null ? MISSING_TTL_S : FOUND_TTL_S);
  } catch {
    // Not kept: the next request asks again.
  }
  return found;
}

async function askApple(id: string, fetcher: typeof fetch): Promise<string | null> {
  try {
    // Nothing of the asking app's request goes along: no header, no address, no id of theirs.
    const res = await fetcher(lookupUrl(id), { headers: { accept: "application/json" }, signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS) });
    if (!res.ok) return null;
    const text = await res.text();
    if (text.length > MAX_LOOKUP_BYTES) return null;
    return readLookup(JSON.parse(text));
  } catch {
    return null;
  }
}

export type StatusEnv = LatestEnv & { APP_MINIMUM?: string; TESTFLIGHT_URL?: string };

const https = (url: string | undefined): string | null => (url?.startsWith("https://") ? url : null);

/**
 * The oldest version still supported, as it is enforced: `APP_MINIMUM`, but only once the App
 * Store has a version at least that new. Until then there is no minimum, so a minimum set too
 * early (or mistyped as a version that doesn't exist) locks nobody out of the one they have.
 */
export function enforcedMinimum(env: Pick<StatusEnv, "APP_MINIMUM">, latest: string | null): string | null {
  const minimum = cleanVersion(env.APP_MINIMUM);
  if (minimum === null || latest === null || olderThan(latest, minimum)) return null;
  return minimum;
}

/** `GET /v1/app`: every key is left out when it isn't known. */
export type AppStatus = { latest?: string; minimum?: string; storeUrl?: string; testflightUrl?: string };

/** Where the store listing is, said only while there is something on it to get. */
function links(env: StatusEnv, latest: string | null): Pick<AppStatus, "storeUrl" | "testflightUrl"> {
  const store = latest === null ? null : (https(env.APP_STORE_URL) ?? `https://apps.apple.com/app/id${storeId(env)}`);
  const beta = https(env.TESTFLIGHT_URL);
  return { ...(store ? { storeUrl: store } : {}), ...(beta ? { testflightUrl: beta } : {}) };
}

export function appStatus(env: StatusEnv, latest: string | null): AppStatus {
  const minimum = enforcedMinimum(env, latest);
  return { ...(latest === null ? {} : { latest }), ...(minimum === null ? {} : { minimum }), ...links(env, latest) };
}

/** The answer to an app that is too old (426): what it needs, and where to get it. */
export type UpdateRequired = { error: "update_required"; minimum?: string } & Pick<AppStatus, "storeUrl" | "testflightUrl">;

/**
 * The refusal for this app, or null when it is served. Asks for the App Store's version only for
 * an app `APP_MINIMUM` or the protocol would turn away, so every other request costs nothing.
 */
export async function refusalFor(
  app: AppIdentity | null,
  env: StatusEnv,
  minProtocol: number,
  latest: () => Promise<string | null>,
): Promise<UpdateRequired | null> {
  const wanted = cleanVersion(env.APP_MINIMUM);
  if (!tooOld(app, { minimum: wanted, minProtocol })) return null;
  const live = await latest();
  const minimum = enforcedMinimum(env, live);
  // Turned away by the version: only once that version can be downloaded.
  if (!tooOld(app, { minimum, minProtocol })) return null;
  return { error: "update_required", ...(minimum === null ? {} : { minimum }), ...links(env, live) };
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
