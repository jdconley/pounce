import type { Section } from "./parse";

/** How far ahead of the server a client's clock may write. */
const MAX_CLOCK_LEAD_MS = 60_000;

/**
 * Last writer wins per key. A tie keeps what's stored, and a write dated
 * more than a minute ahead counts as a minute ahead, so one device with a
 * wrong clock can't win every future write.
 */
export function mergeSection(current: Section, patch: Section, now: number): Section {
  const merged: Section = { ...current };
  for (const [key, entry] of Object.entries(patch)) {
    const at = Math.min(entry.at, now + MAX_CLOCK_LEAD_MS);
    const existing = merged[key];
    if (!existing || at > existing.at) merged[key] = { v: entry.v, at };
  }
  return merged;
}
