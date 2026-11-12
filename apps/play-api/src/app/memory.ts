import type { Remembered } from "./status";

/** The part of the Workers Cache API this needs. */
export type CacheLike = {
  match(key: string): Promise<{ text(): Promise<string> } | undefined>;
  put(key: string, value: Response): Promise<void>;
};

/** Cache keys must be URLs. This host is nobody's: nothing is ever fetched from it. */
const keyUrl = (key: string) => `https://app-status.invalid/${encodeURIComponent(key)}`;

/**
 * Where the App Store's version is kept between requests: this isolate's own memory first, then
 * the data centre's cache (so a new isolate doesn't ask Apple again). Either may forget early;
 * neither is ever wrong for longer than the time it was told to keep an answer.
 */
export function remembered(cache: CacheLike | undefined, now: () => number, local: Map<string, { value: string; until: number }>): Remembered {
  return {
    async get(key) {
      const mine = local.get(key);
      if (mine && now() < mine.until) return mine.value;
      local.delete(key);
      const hit = await cache?.match(keyUrl(key));
      return hit ? hit.text() : null;
    },
    async put(key, value, ttlSeconds) {
      local.set(key, { value, until: now() + ttlSeconds * 1000 });
      await cache?.put(keyUrl(key), new Response(value, { headers: { "cache-control": `public, max-age=${ttlSeconds}` } }));
    },
  };
}
