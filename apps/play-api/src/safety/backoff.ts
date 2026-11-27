/**
 * Backoff for wrong guesses (room codes): a few are free, then each further miss locks the key
 * out for twice as long as the one before, up to a cap. Misses are forgotten after a quiet spell.
 */
export type BackoffRule = {
  /** Misses that cost nothing. */
  free: number;
  /** The first lockout. */
  baseMs: number;
  /** The longest lockout. */
  maxMs: number;
  /** With no miss for this long, the count starts over. */
  forgetMs: number;
};

export type Misses = { count: number; last: number; lockedUntil: number };

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

/** One device guessing room codes: 5 typos an hour, then 30 s, 1 min, 2 min, ... up to an hour. */
export const DEVICE_JOIN_RULE: BackoffRule = { free: 5, baseMs: 30_000, maxMs: HOUR, forgetMs: HOUR };
/** One address (a household, a school) guessing room codes: 20 an hour, then the same backoff. */
export const IP_JOIN_RULE: BackoffRule = { free: 20, baseMs: 30_000, maxMs: HOUR, forgetMs: HOUR };

/** When the key may try again; null when it may now. */
export function lockedUntil(m: Misses | null, now: number): number | null {
  return m && m.lockedUntil > now ? m.lockedUntil : null;
}

/** The record after one more miss at `now`. */
export function miss(m: Misses | null, now: number, rule: BackoffRule): Misses {
  const count = (m && now - m.last < rule.forgetMs ? m.count : 0) + 1;
  const over = count - rule.free;
  const lock = over > 0 ? Math.min(rule.maxMs, rule.baseMs * 2 ** Math.min(over - 1, 30)) : 0;
  return { count, last: now, lockedUntil: lock > 0 ? now + lock : 0 };
}

/** A fixed window counter: `max` takes per `windowMs`. */
export type Window = { count: number; start: number };

/** The window after one more take, and whether that take is within `max`. */
export function take(w: Window | null, now: number, max: number, windowMs: number): { window: Window; ok: boolean } {
  const window = w && now - w.start < windowMs ? { count: w.count + 1, start: w.start } : { count: 1, start: now };
  return { window, ok: window.count <= max };
}

/**
 * The address a guess is counted against: an IPv4 address as it is, an IPv6 one by its /64, which
 * a household or a phone gets whole, so stepping through its own addresses buys no more guesses.
 * Anything else (no address, a malformed one) as it is.
 */
export function ipBucket(ip: string): string {
  if (!ip.includes(":") || ip.includes(".")) return ip;
  const halves = ip.toLowerCase().split("::");
  if (halves.length > 2) return ip;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves[1] ? halves[1].split(":") : [];
  const gap = 8 - head.length - tail.length;
  if (halves.length === 2 ? gap < 1 : gap !== 0) return ip;
  const groups = [...head, ...Array<string>(halves.length === 2 ? gap : 0).fill("0"), ...tail];
  if (!groups.every((g) => /^[0-9a-f]{1,4}$/.test(g))) return ip;
  return `${groups
    .slice(0, 4)
    .map((g) => g.replace(/^0+(?=.)/, ""))
    .join(":")}::/64`;
}
