/** Test helpers for Cat Nap's maker tests: the shape checks every made quilt must pass. */
import { createHmac } from "node:crypto";

import { createRng, type Rng } from "../src/rules/rng";

import type { DayLevel } from "../src/daily/cat-nap/contract";
import type { NapPuzzle } from "../src/daily/cat-nap/maker";

/** Each patch is one piece, sharing sides. */
export function contiguous(n: number, patches: number[]): boolean {
  for (let p = 0; p < n; p++) {
    const cells = patches.flatMap((x, i) => (x === p ? [i] : []));
    if (!cells.length) return false;
    const seen = new Set([cells[0]!]);
    const todo = [cells[0]!];
    while (todo.length) {
      const c = todo.pop()!;
      const r = Math.floor(c / n);
      const k = c % n;
      const near = [r > 0 ? c - n : -1, r < n - 1 ? c + n : -1, k > 0 ? c - 1 : -1, k < n - 1 ? c + 1 : -1];
      for (const d of near) {
        if (d >= 0 && patches[d] === p && !seen.has(d)) {
          seen.add(d);
          todo.push(d);
        }
      }
    }
    if (seen.size !== cells.length) return false;
  }
  return true;
}

/** Every patch holds exactly one of the solution's cats. */
export function oneCatPerPatch(p: NapPuzzle): boolean {
  const counts = Array<number>(p.n).fill(0);
  p.solution.forEach((c, r) => counts[p.patches[r * p.n + c]!]!++);
  return counts.every((k) => k === 1);
}

/**
 * A date's generator, as the server seeds it (`seed.ts`: an HMAC of `daily.v1|cat-nap|date`, the
 * first 16 bytes as four words), here with a fixed test key.
 */
export function dateRng(date: string): Rng {
  const mac = createHmac("sha256", "cat-nap test key").update(`daily.v1|cat-nap|${date}`).digest();
  const words: [number, number, number, number] = [mac.readUInt32LE(0), mac.readUInt32LE(4), mac.readUInt32LE(8), mac.readUInt32LE(12)];
  return createRng(words.every((w) => w === 0) ? [1, 0, 0, 0] : words);
}

/** Mon 1 .. Sat 6, Sun 7. */
export function levelOf(date: string): DayLevel {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  return (day === 0 ? 7 : day) as DayLevel;
}

export function datesFrom(start: string, count: number): string[] {
  const t = Date.parse(`${start}T00:00:00Z`);
  return Array.from({ length: count }, (_, i) => new Date(t + i * 86_400_000).toISOString().slice(0, 10));
}
