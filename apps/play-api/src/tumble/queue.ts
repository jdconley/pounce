import { rngShuffle } from "./rng";

import type { ToyId } from "./toys";
import type { Seed } from "../rules/rng";

/**
 * The seven small toys every bag holds once. Every other bag also holds a 5-cell toy, the paw print
 * and the food bowl taking turns, so bags run 8, 7, 8, 7 (spec §4.1, tuned by the soak §9.3).
 */
const SMALL: readonly ToyId[] = ["i3", "v3", "i4", "o4", "t4", "l4", "j4"];
/** Toys in a pair of bags: one with a 5-cell toy, one without. */
export const PAIR = 15;

type Dealt = { bags: ToyId[][]; state: Seed };
const cache = new Map<string, Dealt>();
const CACHE_SEEDS = 8;

/**
 * Toy `n` of a round's queue. Every box in a round gets the same queue. Bags are dealt in order
 * from one generator that starts at the round seed, and kept for the few seeds in play.
 */
export function toyAt(roundSeed: Readonly<Seed>, n: number): ToyId {
  const key = roundSeed.join(",");
  let dealt = cache.get(key);
  if (!dealt) {
    dealt = { bags: [], state: [roundSeed[0], roundSeed[1], roundSeed[2], roundSeed[3]] };
    if (cache.size >= CACHE_SEEDS) cache.delete(cache.keys().next().value as string);
    cache.set(key, dealt);
  }
  const pair = Math.floor(n / PAIR);
  const i = n % PAIR;
  const bag = pair * 2 + (i < SMALL.length + 1 ? 0 : 1);
  while (dealt.bags.length <= bag) {
    const b = dealt.bags.length;
    const five: ToyId[] = b % 2 === 1 ? [] : [b % 4 === 0 ? "p5" : "u5"];
    const [order, state] = rngShuffle<ToyId>([...SMALL, ...five], dealt.state);
    dealt.bags.push(order);
    dealt.state = state;
  }
  return (dealt.bags[bag] as ToyId[])[i < SMALL.length + 1 ? i : i - (SMALL.length + 1)] as ToyId;
}
