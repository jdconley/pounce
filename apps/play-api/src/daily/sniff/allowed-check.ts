import { ALLOWED } from "./words/allowed";

const WORD = /^[a-z]{5}$/;

/**
 * True when `word` is one a player may guess. A binary search over the sorted list joined with no
 * separator: nothing is parsed, so it is safe on a client's main thread (about 14 comparisons).
 */
export function isAllowed(word: string, allowed: string = ALLOWED): boolean {
  if (!WORD.test(word)) return false;
  let lo = 0;
  let hi = allowed.length / 5 - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const at = allowed.slice(mid * 5, mid * 5 + 5);
    if (at === word) return true;
    if (at < word) lo = mid + 1;
    else hi = mid - 1;
  }
  return false;
}
