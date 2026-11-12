import { SPACING_MS, type Level, type NotifyKind } from "./policy";

import type { Outgoing } from "./types";

/**
 * The one push for a device whose app can't open a table (app updates design §5): someone asked
 * it to a game its version of Pounce can't draw, so it is told to update, by name and by game.
 *
 * It is the only way to reach version 1.0, which shows none of the app's own update screens. So
 * the payload is one 1.0 handles as it does any push it doesn't know: it shows the words, and a
 * tap opens the app. It carries no top-level `code` (1.0 would try to open a table it is told
 * doesn't exist), no badge and no streak block.
 */

export type Face = { name: string; cat: number };

/** What to say, and about which table. */
export type UpdatePush = { code: string; title: string; from: Face; game: string; gameTitle: string };

/** "Mia wants to play Tuna Tiles. Update Pounce to join." No emoji, no hurry, nobody blamed. */
export const updateBody = (from: string, gameTitle: string): string => `${from} wants to play ${gameTitle}. Update Pounce to join.`;

/**
 * Pushes a person sent about one table. When one is held back from a device because its app can't
 * draw the table's game, the device gets the update push in its place. A stalled seat's two
 * ("retire soon", "retired") are not asks to play, and a streak reminder has its own words.
 */
const ASKS: readonly NotifyKind[] = ["your_move", "nudge", "pounce", "play_again"];

/** The update push that stands in for `o` at a table of `game`, or null when `o` isn't a person asking them to it. */
export function updateFor(o: Outgoing, game: string, gameTitle: string): UpdatePush | null {
  if (!ASKS.includes(o.kind) || o.code === undefined || !o.from) return null;
  return { code: o.code, title: o.title, from: o.from, game, gameTitle };
}

/** The APNs JSON body. `update` is for apps that know the kind; 1.0 ignores it. */
export function updateAlert(p: UpdatePush, level: Level): Record<string, unknown> {
  return {
    aps: {
      alert: { title: p.title, body: updateBody(p.from.name, p.gameTitle) },
      ...(level === "active" ? { sound: "default" } : {}),
      "thread-id": `update:${p.code}`,
      category: "STATUS",
      "interruption-level": level,
      "relevance-score": 0.9,
    },
    kind: "update",
    from: p.from,
    update: { code: p.code, game: p.game },
  };
}

export const updateCollapse = (code: string): string => `update:${code}`;

/** Per device: when each table's update push went, newest last. */
export type UpdatesSent = Record<string, number>;

/** How many tables a device remembers having been told about. */
export const MAX_REMEMBERED = 50;

/**
 * Whether a device may be sent the update push for `code` now: once per table, ever, and no more
 * than one of them every 20 minutes whatever the table (the spacing every other unasked push keeps).
 */
export function updateDue(sent: UpdatesSent, code: string, now: number): boolean {
  if (sent[code] !== undefined) return false;
  const last = Math.max(-Infinity, ...Object.values(sent));
  return now - last >= SPACING_MS;
}

/** `sent` with `code` written down, keeping the newest `MAX_REMEMBERED`. */
export function noteUpdate(sent: UpdatesSent, code: string, now: number): UpdatesSent {
  const all = Object.entries({ ...sent, [code]: now }).sort((a, b) => a[1] - b[1]);
  return Object.fromEntries(all.slice(-MAX_REMEMBERED));
}

/** Reads what a device stored; anything unreadable is nothing sent. */
export function parseSent(text: string | null): UpdatesSent {
  try {
    const value: unknown = JSON.parse(text ?? "{}");
    if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).filter((e): e is [string, number] => typeof e[1] === "number"));
  } catch {
    return {};
  }
}
