/** A random source returning a float in [0, 1). */
export type Rng = () => number;

/**
 * 128 bits of generator state as four uint32 words; plain numbers so a game's
 * state stays JSON-serializable. Must not be all zero.
 */
export type Seed = [number, number, number, number];

const rotl = (x: number, k: number): number => (x << k) | (x >>> (32 - k));

/**
 * Seeded xoshiro128** 1.1 (Blackman and Vigna): deterministic for a given
 * seed. Its 128-bit state is far beyond brute force, so the card ids a client
 * sees cannot be used to recover the seed and the deck order.
 */
export function createRng(seed: Readonly<Seed>): Rng {
  const s = Uint32Array.from(seed);
  if (s.every((word) => word === 0)) throw new RangeError("seed must not be all zero");
  return () => {
    const result = Math.imul(rotl(Math.imul(s[1] as number, 5), 7), 9) >>> 0;
    const t = (s[1] as number) << 9;
    s[2] ^= s[0] as number;
    s[3] ^= s[1] as number;
    s[1] ^= s[2] as number;
    s[0] ^= s[3] as number;
    s[2] ^= t;
    s[3] = rotl(s[3] as number, 11);
    return result / 4294967296;
  };
}

/** Fisher-Yates shuffle. Returns a new array; the input is not modified. */
export function shuffle<T>(items: readonly T[], rng: Rng): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j] as T, out[i] as T];
  }
  return out;
}
