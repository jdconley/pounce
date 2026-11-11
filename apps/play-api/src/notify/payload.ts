import type { Level, NotifyKind } from "./policy";
import type { Outgoing } from "./types";

export type Category = "YOUR_MOVE" | "REMINDER" | "POUNCE" | "CONSENT" | "STATUS";

/** Room codes listed in a payload's `streak` block, so the push stays well under 4 KB. */
export const MAX_CODES = 10;
const MAX_COLLAPSE_BYTES = 64;
const HASH_CHARS = 8;
const encoder = new TextEncoder();

const CATEGORY: Partial<Record<NotifyKind, Category>> = {
  your_move: "YOUR_MOVE",
  // Play and In an hour, like the move it asks for.
  nudge: "YOUR_MOVE",
  reminder: "REMINDER",
  last_chance: "REMINDER",
  fresh_start: "REMINDER",
  pounce: "POUNCE",
  consent: "CONSENT",
};

const RELEVANCE: Record<Category, number> = { YOUR_MOVE: 1, POUNCE: 0.9, CONSENT: 0.8, REMINDER: 0.6, STATUS: 0.2 };

/** The notification category the app registers actions for (§12.5); everything else is `STATUS`. */
export const category = (kind: NotifyKind): Category => CATEGORY[kind] ?? "STATUS";
export const relevance = (kind: NotifyKind): number => RELEVANCE[category(kind)];

const bytes = (s: string) => encoder.encode(s).length;

function fnv(text: string): string {
  let hash = 0x811c9dc5;
  for (const ch of text) {
    hash ^= ch.codePointAt(0) as number;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(HASH_CHARS, "0");
}

/** An `apns-collapse-id` within Apple's 64 bytes: long ones keep a prefix and a hash of the whole. */
export function collapseId(raw: string): string {
  if (bytes(raw) <= MAX_COLLAPSE_BYTES) return raw;
  let prefix = "";
  for (const ch of raw) {
    if (bytes(prefix + ch) > MAX_COLLAPSE_BYTES - HASH_CHARS - 1) break;
    prefix += ch;
  }
  return `${prefix}~${fnv(raw)}`;
}

/**
 * The APNs JSON body (§12.5, §12.7): `mutable-content` for the Notification
 * Service Extension, the category, interruption level and relevance, the
 * badge, and the push's data beside `aps`. Passive pushes make no sound.
 */
export function apnsBody(o: Outgoing, level: Level, badge: number): Record<string, unknown> {
  return {
    aps: {
      alert: { title: o.title, body: o.body },
      ...(level === "active" ? { sound: "default" } : {}),
      "thread-id": o.thread,
      "mutable-content": 1,
      category: category(o.kind),
      "interruption-level": level,
      "relevance-score": relevance(o.kind),
      badge,
    },
    ...(o.code === undefined ? {} : { code: o.code }),
    kind: o.kind,
    ...(o.from ? { from: o.from } : {}),
    ...(o.streak
      ? { streak: { ...o.streak, myMove: o.streak.myMove.slice(0, MAX_CODES), theirMove: o.streak.theirMove.slice(0, MAX_CODES) } }
      : {}),
    ...o.data,
  };
}
