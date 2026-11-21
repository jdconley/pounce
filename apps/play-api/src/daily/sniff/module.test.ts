import { readFileSync, writeFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { createRng } from "../../rules/rng";

import { answerFor, POOLS, poolFor } from "./answer";
import { sniff, type SniffPuzzle, type SniffState } from "./module";

import type { Applied, DailyResult, DayLevel, Outcome } from "./contract";
import type { SniffMove } from "./types";

const P: SniffPuzzle = { answer: "plant", level: 1 };
const guess = (word: string): SniffMove => ({ k: "guess", word });

/** Plays `words` a second apart, from 4 s in; returns each answer and the last state. */
function play(p: SniffPuzzle, words: string[], gap = 1000) {
  let s = sniff.init(p);
  const answers: Applied<SniffState>[] = [];
  words.forEach((w, i) => {
    const a = sniff.apply(p, s, guess(w), 4000 + i * gap);
    answers.push(a);
    if (a.ok) s = a.state;
  });
  return { s, answers };
}

const deepHas = (value: unknown, needle: string): boolean => JSON.stringify(value).includes(needle);

describe("sniff module", () => {
  it("is Sniff, with no hints, a 5 s floor and 500 ms between guesses", () => {
    expect(sniff.id).toBe("sniff");
    expect(sniff.minMoveGapMs).toBe(500);
    for (const level of [1, 2, 3, 4, 5, 6, 7] as DayLevel[]) expect(sniff.floorMs[level]).toBe(5000);
    expect(sniff.hint(P, sniff.init(P))).toBeNull();
  });

  it("a solve in three: marks come back, the last ends solved with the answer", () => {
    const { s, answers } = play(P, ["crane", "slant", "plant"]);
    expect(answers[0]).toMatchObject({ ok: true, reveal: { word: "crane", marks: ["none", "none", "spot", "spot", "none"] } });
    expect(answers[0]).not.toHaveProperty("end");
    expect(deepHas(answers[0], "plant")).toBe(false);
    expect(answers[2]).toMatchObject({ ok: true, end: "solved", reveal: { word: "plant", answer: "plant" } });
    expect(sniff.progress(P, s)).toBeCloseTo(3 / 6);
    expect(sniff.publicState(P, s)).toEqual({ guesses: s.guesses, answer: "plant" });
    expect(sniff.result(P, s, "solved", 21_000, 0)).toEqual({ outcome: "solved", timeMs: 21_000, hints: 0, guesses: 3, progress: 1 });
  });

  it("six misses end missed and reveal the answer only then", () => {
    const { s, answers } = play(P, ["crate", "sheep", "dummy", "kitty", "otter", "loops"]);
    for (const a of answers.slice(0, 5)) {
      expect(a.ok && a.end).toBeFalsy();
      expect(deepHas(a, "plant")).toBe(false);
    }
    expect(answers[5]).toMatchObject({ ok: true, end: "missed", reveal: { answer: "plant" } });
    const r = sniff.result(P, s, "missed", 60_000, 0);
    expect(r).toMatchObject({ outcome: "missed", guesses: 6 });
    expect(r.progress).toBeCloseTo(1 / 5); // the best guess, "crate", has one right spot
  });

  it("a seventh guess and a guess after a solve are over, and change nothing", () => {
    const missed = play(P, ["crate", "sheep", "dummy", "kitty", "otter", "loops"]).s;
    expect(sniff.apply(P, missed, guess("plant"), 99_000)).toEqual({ ok: false, reason: "over" });
    const solved = play(P, ["plant"]).s;
    expect(sniff.apply(P, solved, guess("crane"), 99_000)).toEqual({ ok: false, reason: "over" });
  });

  it("a guess 499 ms after the last is too soon; 500 is fine", () => {
    const s = play(P, ["crane"]).s;
    expect(sniff.apply(P, s, guess("slant"), 4499)).toEqual({ ok: false, reason: "too_soon" });
    expect(sniff.apply(P, s, guess("slant"), 4500).ok).toBe(true);
  });

  it("an unknown word is illegal and changes nothing", () => {
    const s = sniff.init(P);
    expect(sniff.apply(P, s, guess("zzzzz"), 4000)).toEqual({ ok: false, reason: "illegal" });
    expect(s).toEqual(sniff.init(P));
  });

  it("parseMove takes only a lowercase five-letter guess, with no other keys", () => {
    expect(sniff.parseMove({ k: "guess", word: "plant" })).toEqual({ k: "guess", word: "plant" });
    for (const bad of [
      null, 1, "plant", [], {}, { k: "guess" }, { k: "guess", word: "PLANT" }, { k: "guess", word: "plan" },
      { k: "guess", word: "plants" }, { k: "guess", word: "pl@nt" }, { k: "guess", word: 12345 },
      { k: "hint", word: "plant" }, { k: "guess", word: "plant", marks: [] }, { word: "plant" },
    ]) {
      expect(sniff.parseMove(bad), JSON.stringify(bad)).toBeNull();
    }
  });

  it("the puzzle and the state before the end hold no answer", () => {
    expect(sniff.publicPuzzle(P)).toEqual({ letters: 5, tries: 6 });
    const { s } = play(P, ["crane", "slant"]);
    expect(deepHas(sniff.publicState(P, s), "plant")).toBe(false);
    expect(sniff.publicState(P, sniff.init(P))).toEqual({ guesses: [] });
    expect(deepHas(sniff.init(P), "plant")).toBe(false);
  });

  it("an unsolved result's progress is the best guess's right spots", () => {
    const { s } = play(P, ["crane", "slant"]);
    expect(sniff.result(P, s, "gaveUp", 30_000, 0)).toEqual({ outcome: "gaveUp", timeMs: 30_000, hints: 0, guesses: 2, progress: 4 / 5 });
    expect(sniff.result(P, sniff.init(P), "closed", 30_000, 0)).toMatchObject({ guesses: 0, progress: 0 });
  });

  it("compare: fewer guesses first, then time; solved before unsolved; then progress", () => {
    const r = (outcome: Outcome, guesses: number, timeMs: number, progress = outcome === "solved" ? 1 : 0): DailyResult => ({
      game: "sniff", date: "2026-12-01", number: 1, outcome, timeMs, hints: 0, tooFast: false, guesses, progress,
    });
    const order = [
      r("solved", 3, 50_000),
      r("solved", 4, 20_000),
      r("solved", 4, 30_000),
      r("missed", 6, 10_000, 0.8),
      r("gaveUp", 2, 5_000, 0.6),
      r("missed", 6, 9_000, 0.2),
      r("closed", 1, 1_000, 0),
    ];
    const shuffled = [order[4], order[0], order[6], order[2], order[5], order[1], order[3]] as DailyResult[];
    expect(shuffled.sort((a, b) => sniff.compare(a, b))).toEqual(order);
    expect(sniff.compare(order[1] as DailyResult, { ...(order[1] as DailyResult) })).toBe(0);
    const noGuesses = { ...r("solved", 3, 1), guesses: undefined };
    expect(sniff.compare(noGuesses, r("solved", 6, 1))).toBeGreaterThan(0);
  });

  it("make uses the day's key when given, the rng when not", () => {
    const key = [9, 8, 7, 6] as [number, number, number, number];
    expect(sniff.make(createRng([1, 1, 1, 1]), 3, { date: "2026-12-02", key })).toEqual({
      answer: answerFor(key, "2026-12-02"),
      level: 3,
    });
    const p = sniff.make(createRng([1, 1, 1, 1]), 5);
    expect(p.level).toBe(5);
    expect(POOLS[poolFor(5)]).toContain(p.answer);
  });
});

type RunVector = {
  name: string;
  answer: string;
  moves: { ms: number; move: unknown }[];
  answers: unknown[];
  end: { outcome: Outcome; timeMs: number; result: unknown };
};

/** The golden runs: a puzzle, moves, and after each move what the server answers. */
const RUNS: Omit<RunVector, "answers" | "end">[] = [
  {
    name: "a solve in three",
    answer: "plant",
    moves: [
      { ms: 4000, move: guess("crane") },
      { ms: 9000, move: guess("slant") },
      { ms: 15000, move: guess("plant") },
    ],
  },
  {
    name: "repeated letters, solved on the last try",
    answer: "kitty",
    moves: [
      { ms: 3000, move: guess("tatty") },
      { ms: 3300, move: guess("otter") },
      { ms: 8000, move: guess("otter") },
      { ms: 12000, move: guess("zzzzz") },
      { ms: 15000, move: guess("witty") },
      { ms: 20000, move: guess("bitty") },
      { ms: 25000, move: guess("ditty") },
      { ms: 30000, move: guess("kitty") },
    ],
  },
  {
    name: "six misses, then a seventh guess is over",
    answer: "piano",
    moves: [
      { ms: 2000, move: guess("crate") },
      { ms: 4000, move: guess("nanny") },
      { ms: 6000, move: guess("sheep") },
      { ms: 8000, move: guess("dummy") },
      { ms: 10000, move: guess("kitty") },
      { ms: 12000, move: guess("loops") },
      { ms: 14000, move: guess("piano") },
    ],
  },
];

function replay(v: (typeof RUNS)[number]): RunVector {
  const p: SniffPuzzle = { answer: v.answer, level: 1 };
  let s = sniff.init(p);
  let end: RunVector["end"] | null = null;
  const answers = v.moves.map(({ ms, move }) => {
    const m = sniff.parseMove(move);
    if (!m) return { ok: false, reason: "bad_message" };
    const a = sniff.apply(p, s, m, ms);
    if (!a.ok) return a;
    s = a.state;
    if (a.end) end = { outcome: a.end, timeMs: ms, result: sniff.result(p, s, a.end, ms, 0) };
    return { ok: true, reveal: a.reveal, end: a.end ?? null, progress: sniff.progress(p, s), view: sniff.publicState(p, s) };
  });
  if (!end) throw new Error(`${v.name} never ends`);
  return { ...v, answers, end };
}

describe("golden runs", () => {
  const file = new URL("../../../fixtures/daily/sniff/runs.json", import.meta.url);
  const played = RUNS.map(replay);

  it("runs.json replays exactly", () => {
    if (process.env.UPDATE_SNIFF_VECTORS) {
      writeFileSync(file, JSON.stringify({ about: "Sniff runs: each move's server answer. Written by module.test.ts (UPDATE_SNIFF_VECTORS=1).", runs: played }, null, 2) + "\n");
    }
    const stored = JSON.parse(readFileSync(file, "utf8")) as { runs: RunVector[] };
    expect(stored.runs).toEqual(played);
  });

  it("each run is legal where it should be", () => {
    const [solve, repeats, misses] = played as [RunVector, RunVector, RunVector];
    expect(solve.end.outcome).toBe("solved");
    expect(repeats.answers.map((a) => (a as { ok: boolean; reason?: string }).reason ?? "ok")).toEqual([
      "ok", "too_soon", "ok", "illegal", "ok", "ok", "ok", "ok",
    ]);
    expect(repeats.end.outcome).toBe("solved");
    expect(misses.end.outcome).toBe("missed");
    expect(misses.answers[6]).toEqual({ ok: false, reason: "over" });
  });
});
