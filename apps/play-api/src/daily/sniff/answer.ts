/**
 * Which word is Sniff's answer on a date (spec §2, §3). Server only.
 *
 * The answers fall into three pools, one per kind of day:
 * - easy (Mon, Tue): the commonest words, no letter twice;
 * - mid (Wed, Thu, Sun): common words, no letter twice;
 * - hard (Fri, Sat): less common words, and every word with a letter twice.
 *
 * Each pool is walked in a shuffled order, one word per day that uses it. The order is a shuffle
 * keyed by a secret seed that doesn't change by date, so no word repeats until its pool is used up
 * (a "cycle"), and nobody can tell which word goes with which day. Each cycle gets a new order.
 */
import { createRng, type Seed, shuffle } from "../../rules/rng";

import { ANSWERS } from "./words/answers";

import type { Day, DayLevel } from "./contract";

export type Pool = "easy" | "mid" | "hard";

const POOL_NUMBER: Record<Pool, number> = { easy: 0, mid: 1, hard: 2 };

/** A Monday well before launch, where every pool's count starts. Never change it after launch. */
export const SNIFF_EPOCH: Day = "2026-01-05";

const DAY_MS = 86_400_000;

const repeats = (w: string) => new Set(w).size < w.length;

export const POOLS: Readonly<Record<Pool, readonly string[]>> = {
  easy: ANSWERS.filter(([w, t]) => t === 1 && !repeats(w)).map(([w]) => w),
  mid: ANSWERS.filter(([w, t]) => t === 2 && !repeats(w)).map(([w]) => w),
  hard: ANSWERS.filter(([w, t]) => t === 3 || repeats(w)).map(([w]) => w),
};

/** The level of a date, Mon 1 to Sun 7, as `levelFor` in `src/daily/days.ts`. */
export function levelOf(date: Day): DayLevel {
  const sunday0 = new Date(`${date}T00:00:00Z`).getUTCDay();
  return (sunday0 === 0 ? 7 : sunday0) as DayLevel;
}

export function poolFor(level: DayLevel): Pool {
  if (level <= 2) return "easy";
  if (level === 5 || level === 6) return "hard";
  return "mid";
}

/** How many of a week's days (Mon first) use each pool, and how many of the first k do. */
const WEEK: Pool[] = ([1, 2, 3, 4, 5, 6, 7] as DayLevel[]).map(poolFor);
const inFirst = (pool: Pool, k: number) => WEEK.slice(0, k).filter((p) => p === pool).length;

/**
 * How many dates from `SNIFF_EPOCH` up to, not including, `date` use `pool`. Negative before the
 * epoch: minus the pool's dates from `date` up to the epoch.
 */
export function poolDay(date: Day, pool: Pool): number {
  const days = Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${SNIFF_EPOCH}T00:00:00Z`)) / DAY_MS);
  const weeks = Math.floor(days / 7);
  return weeks * inFirst(pool, 7) + inFirst(pool, days - weeks * 7);
}

/** A 32-bit finaliser (MurmurHash3's), so nearby inputs give unrelated words. */
function mix(h: number): number {
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h >>> 0;
}

/** The seed for a pool's cycle: the key mixed with the pool and the cycle. Its first bit is set, so it is never all zero. */
function cycleSeed(key: Readonly<Seed>, pool: Pool, cycle: number): Seed {
  const salt = (i: number) => mix(Math.imul(POOL_NUMBER[pool] + 1, 0x9e3779b9) ^ Math.imul(cycle | 0, 0x632be5ab) ^ Math.imul(i + 1, 0x7f4a7c15));
  const seed = key.map((word, i) => mix((word ^ salt(i)) >>> 0)) as Seed;
  seed[0] = (seed[0] | 1) >>> 0;
  return seed;
}

/** The answer for `date`, from its weekday's pool, in that pool's keyed order for its cycle. */
export function answerFor(key: Readonly<Seed>, date: Day): string {
  const pool = poolFor(levelOf(date));
  const words = POOLS[pool];
  const i = poolDay(date, pool);
  const cycle = Math.floor(i / words.length);
  const order = shuffle(words, createRng(cycleSeed(key, pool, cycle)));
  return order[i - cycle * words.length] as string;
}

