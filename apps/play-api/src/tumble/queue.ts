import { rngShuffle } from "./rng";

import type { ToyId } from "./toys";
import type { Seed } from "../rules/rng";

/** The seven small toys every bag holds once; an eighth, a 5-cell toy, alternates bag by bag (spec §4.1). */
const SMALL: readonly ToyId[] = ["i3", "v3", "i4", "o4", "t4", "l4", "j4"];
export const BAG = 8;

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
  const bag = Math.floor(n / BAG);
  while (dealt.bags.length <= bag) {
    const b = dealt.bags.length;
    const [order, state] = rngShuffle([...SMALL, b % 2 === 0 ? "p5" : "u5"], dealt.state);
    dealt.bags.push(order);
    dealt.state = state;
  }
  return (dealt.bags[bag] as ToyId[])[n % BAG] as ToyId;
}
