/** Longest table name, in code points. */
export const MAX_ROOM_NAME = 30;

const ADJECTIVES = [
  "Sleepy", "Sneaky", "Fuzzy", "Zoomy", "Grumpy", "Fancy",
  "Chonky", "Velvet", "Midnight", "Sunny", "Wobbly", "Purring",
] as const;

const NOUNS = [
  "Sardines", "Whiskers", "Mittens", "Yarn Club", "Box Fort", "Sunbeams",
  "Tuna Heist", "Catnip Lounge", "Laser Dots", "Hairballs", "Scratch Post", "Nap Squad",
] as const;

/**
 * The name a table gets until someone renames it, such as "The Sleepy Sardines".
 * Derived from the room code alone, so a room saved before tables had names
 * gets the same one on every load.
 */
export function defaultRoomName(code: string): string {
  // FNV-1a over the code's characters.
  let hash = 0x811c9dc5;
  for (const ch of code) {
    hash ^= ch.codePointAt(0) as number;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  const adjective = ADJECTIVES[hash % ADJECTIVES.length] as string;
  const noun = NOUNS[Math.floor(hash / ADJECTIVES.length) % NOUNS.length] as string;
  return `The ${adjective} ${noun}`;
}

/** Control characters, line and paragraph separators, and bidi overrides and isolates. */
const FORBIDDEN = /[\p{Cc}\u2028\u2029\u202A-\u202E\u2066-\u2069]/u;

/**
 * A table name as the server stores it: trimmed, runs of spaces collapsed to
 * one, 1-30 code points, no control characters. Null when `value` is not one.
 */
export function parseRoomName(value: unknown): string | null {
  if (typeof value !== "string" || FORBIDDEN.test(value)) return null;
  const name = value.trim().replace(/\s+/gu, " ");
  const length = [...name].length;
  return length >= 1 && length <= MAX_ROOM_NAME ? name : null;
}
