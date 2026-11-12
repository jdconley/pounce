import { remembered, type CacheLike } from "./memory";
import { known, storeVersion, type Known, type LatestEnv } from "./status";

/** This isolate's own copy of the last answer (see `remembered`). */
const LOCAL = new Map<string, { value: string; until: number }>();

/** The Worker's own origin, learned from a request it served: where its cache entries are keyed. */
let origin: string | null = null;

/** Notes the origin of a request this Worker (or a Durable Object of it) is serving. */
export function servedAt(url: string): void {
  try {
    const parsed = new URL(url);
    if (parsed.protocol === "https:" || parsed.protocol === "http:") origin = parsed.origin;
  } catch {
    // Not a URL: nothing learned.
  }
}

/**
 * What this Worker (or Durable Object) knows of the App Store right now. Never waits on Apple:
 * a lookup that is due goes to `background` (`ctx.waitUntil`), or runs unawaited without one,
 * and its answer is for the next asker. Never throws.
 */
export async function storeKnown(env: LatestEnv, background?: (work: Promise<unknown>) => void): Promise<Known> {
  const cache = (globalThis as { caches?: { default?: CacheLike } }).caches?.default;
  const later = (work: Promise<void>) => {
    const safe = work.catch(() => undefined);
    if (background) background(safe);
  };
  try {
    return known(env, await storeVersion(env, remembered(cache, origin, Date.now, LOCAL), fetch, Date.now, later));
  } catch {
    return known(env, null);
  }
}
