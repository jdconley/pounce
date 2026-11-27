import type { Seed } from "../rules/rng";

/**
 * xoshiro128** 1.1 with its state passed in and out, so a Toy Tumble box can keep its generator
 * in plain JSON and every engine (this one, the app's Swift port) draws exactly the same numbers.
 * The same generator as `rules/rng.ts`'s `createRng`; `basics.test.ts` holds the two together.
 */

const rotl = (x: number, k: number): number => ((x << k) | (x >>> (32 - k))) >>> 0;

/** The next uint32 output and the state after it. The state given is not changed. */
export function rngNext(s: Readonly<Seed>): [number, Seed] {
  const [s0, s1, s2, s3] = s;
  const result = Math.imul(rotl(Math.imul(s1, 5) >>> 0, 7), 9) >>> 0;
  const t = (s1 << 9) >>> 0;
  let n2 = (s2 ^ s0) >>> 0;
  let n3 = (s3 ^ s1) >>> 0;
  const n1 = (s1 ^ n2) >>> 0;
  const n0 = (s0 ^ n3) >>> 0;
  n2 = (n2 ^ t) >>> 0;
  n3 = rotl(n3, 11);
  return [result, [n0, n1, n2, n3]];
}

/** A uint32 output as a float in [0, 1). */
export const rngFloat = (u: number): number => u / 4294967296;

/** Fisher-Yates from the end, as `rules/rng.ts`'s `shuffle`. Returns the new order and the state after. */
export function rngShuffle<T>(items: readonly T[], s: Readonly<Seed>): [T[], Seed] {
  const out = [...items];
  let state: Seed = [s[0], s[1], s[2], s[3]];
  for (let i = out.length - 1; i > 0; i--) {
    const [u, next] = rngNext(state);
    state = next;
    const j = Math.floor(rngFloat(u) * (i + 1));
    [out[i], out[j]] = [out[j] as T, out[i] as T];
  }
  return [out, state];
}
