import type { DailyGameId } from "./module";
import type { Seed } from "../rules/rng";
import type { Day } from "../streaks/clock";

const encoder = new TextEncoder();
/** HKDF's label for the daily key: a key of its own, so nothing else signed with `TOKEN_SECRET` can stand in for it. */
const INFO = "pounce daily v1";

const keys = new Map<string, Promise<CryptoKey>>();

/**
 * The Daily Dish's HMAC key (spec §3, "Seeds"): HKDF-SHA256 over `TOKEN_SECRET`, empty salt,
 * info "pounce daily v1". No new secret. Derived once per secret per isolate.
 */
export function dailyKey(secret: string): Promise<CryptoKey> {
  let key = keys.get(secret);
  if (!key) {
    key = (async () => {
      const base = await crypto.subtle.importKey("raw", encoder.encode(secret), "HKDF", false, ["deriveBits"]);
      const bits = await crypto.subtle.deriveBits(
        { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encoder.encode(INFO) },
        base,
        256,
      );
      return crypto.subtle.importKey("raw", bits, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    })();
    keys.set(secret, key);
  }
  return key;
}

/**
 * The seed for one game on one date: `HMAC-SHA256(dailyKey, "daily.v1|" + game + "|" + date)`,
 * its first 16 bytes as four big-endian uint32 words for `createRng`. Never sent to a client.
 */
export async function dailySeed(secret: string, game: DailyGameId, date: Day): Promise<Seed> {
  return seedOf(await crypto.subtle.sign("HMAC", await dailyKey(secret), encoder.encode(`daily.v1|${game}|${date}`)));
}

/** A MAC's first 16 bytes as a seed. */
export function seedOf(mac: ArrayBuffer): Seed {
  const view = new DataView(mac);
  const seed: Seed = [view.getUint32(0), view.getUint32(4), view.getUint32(8), view.getUint32(12)];
  // xoshiro128** can't start from all zeros; a 2^-128 chance, handled anyway.
  return seed.every((word) => word === 0) ? [1, 0, 0, 0] : seed;
}
