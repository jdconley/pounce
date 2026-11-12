/**
 * Which app is asking (app updates design §2): the header an app from version 1.1 on sends with
 * every request and socket upgrade, and how two versions compare. Version 1.0 sends no such
 * header, and an app that sends none is answered exactly as it always was.
 */

/** `X-Pounce-App: platform=ios; version=1.1; build=57; protocol=1`. Keys in any order; unknown keys are ignored. */
export const APP_HEADER = "x-pounce-app";

/** The one version of the app that never says what it is. */
export const UNIDENTIFIED_VERSION = "1.0";
/** The protocol that version speaks. */
export const UNIDENTIFIED_PROTOCOL = 1;

const MAX_HEADER = 200;
const MAX_PARTS = 4;
const MAX_PART = 999_999;

/** A version as its numbers, most significant first: "1.2.0" is [1, 2, 0]. */
export type Version = readonly number[];

/**
 * Reads a dotted version. Forgiving about what surrounds the numbers ("v1.2", " 1.2 ", "1.2-beta",
 * "1.2 (57)" are all 1.2), strict about there being numbers: anything that doesn't start with one
 * is null, never a guess. At most four parts; a longer one, or a part past six digits, is null.
 */
export function parseVersion(text: unknown): Version | null {
  if (typeof text !== "string") return null;
  const found = /^\s*v?(\d+(?:\.\d+)*)(.*)$/i.exec(text);
  if (!found) return null;
  // "1.2.x" names no version; "1.2-beta" and "1.2 (57)" name 1.2.
  if ((found[2] as string).startsWith(".")) return null;
  const parts = (found[1] as string).split(".").map(Number);
  if (parts.length > MAX_PARTS || parts.some((n) => !Number.isSafeInteger(n) || n > MAX_PART)) return null;
  return parts;
}

/** Negative when `a` is older than `b`, positive when newer, 0 when the same. "1.1" and "1.1.0" are the same. */
export function compareVersions(a: Version, b: Version): number {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const d = (a[i] ?? 0) - (b[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

/** `a` is older than `b`. Either one unreadable: false, since nobody is told to update on a guess. */
export function olderThan(a: string | null | undefined, b: string | null | undefined): boolean {
  const [x, y] = [parseVersion(a), parseVersion(b)];
  return x !== null && y !== null && compareVersions(x, y) < 0;
}

/** A version as the server says it back: its numbers joined with dots, or null for one it can't read. */
export function cleanVersion(text: unknown): string | null {
  return parseVersion(text)?.join(".") ?? null;
}

/** What an app said about itself. */
export type AppIdentity = {
  /** Lower case, e.g. "ios". */
  platform: string;
  /** As sent, cleaned: "1.1". */
  version: string;
  /** The build number, when it sent one that is a number. */
  build: number | null;
  /** The protocol it speaks, when it said. */
  protocol: number | null;
};

const PLATFORM = /^[a-z][a-z0-9-]{0,19}$/;

/**
 * The app behind a request, or null for one that didn't say (version 1.0) or said something
 * unreadable: no platform, or no version. An unreadable header is treated as no header, so the
 * worst a broken one gets is what 1.0 gets.
 */
export function parseApp(header: string | null | undefined): AppIdentity | null {
  if (typeof header !== "string" || header.length > MAX_HEADER) return null;
  const fields = new Map<string, string>();
  for (const part of header.split(";")) {
    const at = part.indexOf("=");
    if (at < 1) continue;
    const key = part.slice(0, at).trim().toLowerCase();
    if (!fields.has(key)) fields.set(key, part.slice(at + 1).trim());
  }
  const platform = (fields.get("platform") ?? "").toLowerCase();
  const version = cleanVersion(fields.get("version"));
  if (!PLATFORM.test(platform) || version === null) return null;
  return { platform, version, build: wholeNumber(fields.get("build")), protocol: wholeNumber(fields.get("protocol")) };
}

function wholeNumber(text: string | undefined): number | null {
  if (text === undefined || !/^\d{1,9}$/.test(text)) return null;
  return Number(text);
}

/** What the server still supports: the oldest app version (null: every one) and the oldest protocol. */
export type Supported = { minimum: string | null; minProtocol: number };

/**
 * Whether this app is too old to be served (the hard moment, design §4.3). An app that didn't
 * say what it is counts as version 1.0 speaking protocol 1, the only app that doesn't say.
 */
export function tooOld(app: AppIdentity | null, supported: Supported): boolean {
  const version = app?.version ?? UNIDENTIFIED_VERSION;
  const protocol = app === null ? UNIDENTIFIED_PROTOCOL : app.protocol;
  if (protocol !== null && protocol < supported.minProtocol) return true;
  return olderThan(version, supported.minimum);
}
