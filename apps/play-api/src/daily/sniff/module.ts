/**
 * Sniff, the Daily Dish's five-letter word puzzle (spec §1): the server's game module. Server
 * only: it holds the answer. The client gets each guess's marks as the move's reveal, and the
 * answer only when the run ends.
 */
import { isAllowed } from "./allowed-check";
import { answerFor, pickAnswer } from "./answer";
import { markGuess } from "./marks";
import { type Guess, LETTERS, type SniffMove, type SniffPublic, type SniffReveal, type SniffView, TRIES } from "./types";

import type { Applied, DailyModule, DailyResult, DayLevel } from "./contract";

export type SniffPuzzle = { answer: string; level: DayLevel };
export type SniffState = { guesses: Guess[]; lastMs: number | null };

/** Guesses closer together than this are refused (spec §3, limits). */
const GAP_MS = 500;
/** A run faster than this is kept but left off the board: typing a word and sending it takes longer. */
const FLOOR_MS = 5000;

const solved = (s: SniffState) => s.guesses.some((g) => g.marks.every((m) => m === "spot"));
const ended = (s: SniffState) => solved(s) || s.guesses.length >= TRIES;
const spots = (g: Guess) => g.marks.filter((m) => m === "spot").length;

/** Ranks a result: solved first, then by fewest guesses; unsolved by how close they got. */
function rank(r: DailyResult): number[] {
  const guesses = r.guesses ?? TRIES + 1;
  return r.outcome === "solved" ? [0, guesses, 0, r.timeMs] : [1, 0, -r.progress, r.timeMs];
}

export const sniff: DailyModule<SniffPuzzle, SniffState, SniffMove> = {
  id: "sniff",

  make(rng, level, day) {
    return { answer: day ? answerFor(day.key, day.date) : pickAnswer(rng, level), level };
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

  result(_p, s, outcome, timeMs, hints) {
    const best = Math.max(0, ...s.guesses.map(spots));
    return { outcome, timeMs, hints, guesses: s.guesses.length, progress: outcome === "solved" ? 1 : best / LETTERS };
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
