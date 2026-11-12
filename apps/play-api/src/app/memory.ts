import type { Remembered } from "./status";

/** The part of the Workers Cache API this needs. */
export type CacheLike = {
  match(key: string): Promise<{ text(): Promise<string> } | undefined>;
  put(key: string, value: Response): Promise<void>;
};

/**
 * Cache keys must be URLs, and Cloudflare's cache is per zone: the key is a path on the Worker's
 * own host (`origin`, from a request it served), one no route answers. The Worker runs before
 * the cache on its routes, so nothing kept here is ever served to a visitor.
 */
export const cacheUrl = (origin: string, key: string): string => `${origin}/__cache/${encodeURIComponent(key)}`;

/**
 * Where the App Store's version is kept between requests: this isolate's own memory first, then
 * the data centre's cache (so a new isolate doesn't start from nothing). Either may forget early.
 * `origin`: the Worker's own origin when it is known; without it only this isolate remembers.
 */
export function remembered(
  cache: CacheLike | undefined,
  origin: string | null,
  now: () => number,
  local: Map<string, { value: string; until: number }>,
): Remembered {
  const shared = origin === null ? undefined : cache;
  return {
    async get(key) {
      const mine = local.get(key);
      if (mine && now() < mine.until) return mine.value;
      local.delete(key);
      const hit = await shared?.match(cacheUrl(origin as string, key));
      if (!hit) return null;
      const value = await hit.text();
      // Briefly this isolate's too, so a burst of requests reads the cache once.
      local.set(key, { value, until: now() + LOCAL_READ_MS });
      return value;
    },
    async put(key, value, ttlSeconds) {
      local.set(key, { value, until: now() + ttlSeconds * 1000 });
      await shared?.put(cacheUrl(origin as string, key), new Response(value, { headers: { "cache-control": `public, max-age=${ttlSeconds}` } }));
    },
  };
}

/** How long a value read from the shared cache is trusted here before it is read again (another isolate may have refreshed it). */
export const LOCAL_READ_MS = 60_000;
