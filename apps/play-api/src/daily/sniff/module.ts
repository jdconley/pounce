/**
 * Sniff, the Daily Dish's five-letter word puzzle (spec §1): the server's game module. Server
 * only: it holds the answer. The client gets each guess's marks as the move's reveal, and the
 * answer only when the run ends.
 */
import { isAllowed } from "./allowed-check";
import { answerFor } from "./answer";
import { markGuess } from "./marks";
import { type Guess, LETTERS, type SniffMove, type SniffPublic, type SniffReveal, type SniffView, TRIES } from "./types";

import type { DayLevel } from "../days";
import type { Applied, DailyModule, DailyResult } from "../module";

export type SniffPuzzle = { answer: string; level: DayLevel };
export type SniffState = { guesses: Guess[]; lastMs: number | null };

/** Guesses closer together than this are refused (spec §3, limits). */
const GAP_MS = 500;
/** A run faster than this is kept but left off the board: typing a word and sending it takes longer. */
const FLOOR_MS = 5000;

const solved = (s: SniffState) => s.guesses.some((g) => g.marks.every((m) => m === "spot"));
const ended = (s: SniffState) => solved(s) || s.guesses.length >= TRIES;

/** Ranks a result: solved first, then by fewest guesses; unsolved by how close they got. */
function rank(r: DailyResult): number[] {
  const guesses = r.guesses ?? TRIES + 1;
  return r.outcome === "solved" ? [0, guesses, 0, r.timeMs] : [1, 0, -r.progress, r.timeMs];
}

export const sniff: DailyModule<SniffPuzzle, SniffState, SniffMove> = {
  id: "sniff",

  // The answer follows the date and the cycle key alone; the day's rng isn't needed.
  make(_rng, level, day) {
    return { answer: answerFor(day.key, day.date), level };
  },

  publicPuzzle(): SniffPublic {
    return { letters: LETTERS, tries: TRIES };
  },

  init() {
    return { guesses: [], lastMs: null };
  },

  parseMove(raw) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
    const keys = Object.keys(raw);
    if (keys.length !== 2 || !keys.includes("k") || !keys.includes("word")) return null;
    const { k, word } = raw as { k: unknown; word: unknown };
    if (k !== "guess" || typeof word !== "string" || !/^[a-z]{5}$/.test(word)) return null;
    return { k, word };
  },

  apply(p, s, m, ms): Applied<SniffState> {
    if (ended(s)) return { ok: false, reason: "over" };
    if (s.lastMs !== null && ms - s.lastMs < GAP_MS) return { ok: false, reason: "too_soon" };
    if (!isAllowed(m.word)) return { ok: false, reason: "illegal" };
    const g: Guess = { word: m.word, marks: markGuess(p.answer, m.word) };
    const state: SniffState = { guesses: [...s.guesses, g], lastMs: ms };
    const end = solved(state) ? "solved" : state.guesses.length >= TRIES ? "missed" : undefined;
    const reveal: SniffReveal = end ? { ...g, answer: p.answer } : g;
    return end ? { ok: true, state, reveal, end } : { ok: true, state, reveal };
  },

  hint() {
    return null;
  },

  progress(_p, s) {
    return s.guesses.length / TRIES;
  },

  publicState(p, s): SniffView {
    return ended(s) ? { guesses: s.guesses, answer: p.answer } : { guesses: s.guesses };
  },

  /**
   * How far a miss got, by the fair measure (spec §6, "Ranking"): the letters found in their right
   * place in any guess, out of five. Finding the first letter in guess two and the last in guess
   * five is two letters found, even though no one guess had both.
   */
  result(_p, s, outcome, timeMs, hints) {
    const found = Array.from({ length: LETTERS }, (_, i) => s.guesses.some((g) => g.marks[i] === "spot")).filter(Boolean).length;
    return { outcome, timeMs, hints, guesses: s.guesses.length, progress: outcome === "solved" ? 1 : found / LETTERS };
  },

  compare(a, b) {
    const ra = rank(a);
    const rb = rank(b);
    for (let i = 0; i < ra.length; i++) {
      const d = (ra[i] as number) - (rb[i] as number);
      if (d !== 0) return d;
    }
    return 0;
  },

  floorMs: { 1: FLOOR_MS, 2: FLOOR_MS, 3: FLOOR_MS, 4: FLOOR_MS, 5: FLOOR_MS, 6: FLOOR_MS, 7: FLOOR_MS },
  minMoveGapMs: GAP_MS,
};
