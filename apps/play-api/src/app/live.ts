import { remembered, type CacheLike } from "./memory";
import { latestVersion, type LatestEnv } from "./status";

/** This isolate's own copy of the last answer (see `remembered`). */
const LOCAL = new Map<string, { value: string; until: number }>();

/**
 * The version live on the App Store as this Worker (or Durable Object) knows it: from
 * `APP_LATEST`, memory, the cache, or Apple's public lookup, in that order. Null when unknown.
 */
export function storeLatest(env: LatestEnv): Promise<string | null> {
  const cache = (globalThis as { caches?: { default?: CacheLike } }).caches?.default;
  return latestVersion(env, remembered(cache, Date.now, LOCAL), fetch);
}
