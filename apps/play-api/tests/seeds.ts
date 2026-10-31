import type { Seed } from "../src/rules/rng";

/** murmur3's 32-bit finalizer: a bijection that spreads every input bit. */
function fmix32(h: number): number {
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h >>> 0;
}

/**
 * A fixed 128-bit seed for tests and the sim, one per `n`. Production seeds
 * are four crypto words; tests need distinct, repeatable, well-mixed ones
 * (xoshiro's first outputs are poor from low-entropy words). Never all zero:
 * fmix32 is a bijection, so at most one word can be 0.
 */
export function seedOf(n: number): Seed {
  return [0, 1, 2, 3].map((i) => fmix32((n + Math.imul(i, 0x9e3779b9)) >>> 0)) as Seed;
}
