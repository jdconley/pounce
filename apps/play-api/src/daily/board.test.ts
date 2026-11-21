import { describe, expect, it } from "vitest";

import { addDays } from "../streaks/clock";

import { addToStats, dish, emptyStats, mergeStats, rankGame, statsView, type BoardRow, type GameBoard, type Stats } from "./board";
import { testGame } from "./test-game";

import type { DailyModule, DailyResult, Outcome } from "./module";

const m = testGame as DailyModule;

const result = (r: Partial<DailyResult> = {}): DailyResult => ({
  game: "test",
  date: "2026-11-23",
  number: 1,
  outcome: "solved",
  timeMs: 60_000,
  hints: 0,
  tooFast: false,
  progress: 1,
  ...r,
});
const row = (player: string, r: Partial<DailyResult> | null, playing: number | null = null): BoardRow => ({
  player,
  name: player.toUpperCase(),
  cat: 1,
  rank: null,
  result: r === null ? null : result(r),
  playing: playing === null ? null : { progress: playing },
});

describe("rankGame", () => {
  it("rankGame orders by compare and drops tooFast", () => {
    const ranked = rankGame(m, [
      row("slow", { timeMs: 90_000 }),
      row("bot", { timeMs: 1000, tooFast: true }),
      row("quit", { outcome: "gaveUp", progress: 0.5 }),
      row("fast", { timeMs: 40_000 }),
    ]);
    expect(ranked.map((r) => [r.player, r.rank])).toEqual([
      ["fast", 1],
      ["slow", 2],
      ["quit", 3],
    ]);
  });

  it("ties share a rank, and the next rank skips", () => {
    const ranked = rankGame(m, [row("a", { timeMs: 50_000 }), row("b", { timeMs: 50_000 }), row("c", { timeMs: 70_000 })]);
    expect(ranked.map((r) => r.rank)).toEqual([1, 1, 3]);
  });

  it("people playing now come after the results, furthest first, with no rank", () => {
    const ranked = rankGame(m, [row("near", null, 0.2), row("done", {}), row("far", null, 0.7), row("nobody", null)]);
    expect(ranked.map((r) => [r.player, r.rank])).toEqual([
      ["done", 1],
      ["far", null],
      ["near", null],
    ]);
  });
});

const board = (rows: BoardRow[], game: "test" | "sniff" = "test"): GameBoard => ({ game, number: 1, rows: rankGame(m, rows) });

describe("dish", () => {
  it("dish gives 3/2/1 plus 1 per ended run, shared ties, crowns", () => {
    const d = dish([
      board([row("a", { timeMs: 40_000 }), row("b", { timeMs: 50_000 }), row("c", { timeMs: 60_000 }), row("d", { timeMs: 70_000 })]),
      board([row("b", { timeMs: 40_000 }), row("a", { timeMs: 40_000 }), row("c", { timeMs: 60_000 })], "sniff"),
    ]);
    expect(d.rows).toEqual([
      // a: first (3 + 1), then a shared first (3 + 1). b: second (2 + 1), then the shared first.
      { player: "a", name: "A", cat: 1, rank: 1, points: 8, crowns: ["test", "sniff"], ended: 2 },
      { player: "b", name: "B", cat: 1, rank: 2, points: 7, crowns: ["sniff"], ended: 2 },
      // c: third in test (1 + 1), third in sniff after a shared first (1 + 1).
      { player: "c", name: "C", cat: 1, rank: 3, points: 4, crowns: [], ended: 2 },
      { player: "d", name: "D", cat: 1, rank: 4, points: 1, crowns: [], ended: 1 },
    ]);
  });

  it("closed runs earn no ended point", () => {
    const d = dish([board([row("a", { outcome: "closed", progress: 0.4 }), row("b", { outcome: "gaveUp", progress: 0.2 })])]);
    expect(d.rows.map((r) => [r.player, r.points, r.ended])).toEqual([
      ["a", 3, 0],
      ["b", 3, 1],
    ]);
  });

  it("tooFast rows and people still playing earn nothing and aren't on the Dish", () => {
    const d = dish([board([row("bot", { tooFast: true }), row("now", null, 0.5), row("a", {})])]);
    expect(d.rows.map((r) => r.player)).toEqual(["a"]);
  });

  it("equal totals share a rank", () => {
    const d = dish([board([row("a", {})]), board([row("b", {})], "sniff")]);
    expect(d.rows.map((r) => [r.player, r.rank])).toEqual([
      ["a", 1],
      ["b", 1],
    ]);
  });
});

describe("stats", () => {
  const on = (date: string, outcome: Outcome = "solved", extra: Partial<DailyResult> = {}) => result({ date, outcome, ...extra });

  it("counts played and solved, and keeps the best time", () => {
    let s: Stats | null = null;
    s = addToStats(s, on("2026-11-23", "solved", { timeMs: 80_000 }));
    s = addToStats(s, on("2026-11-24", "gaveUp", { timeMs: 10_000 }));
    s = addToStats(s, on("2026-11-25", "solved", { timeMs: 70_000 }));
    expect(s).toMatchObject({ played: 3, solved: 2, bestTimeMs: 70_000, bestPoints: null });
  });

  it("stats streak counts consecutive dates with an ended run", () => {
    let s: Stats | null = null;
    s = addToStats(s, on("2026-11-23"));
    s = addToStats(s, on("2026-11-24", "gaveUp"));
    expect(s).toMatchObject({ streak: 2, best: 2 });
    // A run closed at 04:00 didn't end: the streak breaks.
    s = addToStats(s, on("2026-11-25", "closed"));
    expect(s).toMatchObject({ streak: 0, best: 2 });
    s = addToStats(s, on("2026-11-26"));
    s = addToStats(s, on("2026-11-28"));
    expect(s).toMatchObject({ streak: 1, best: 2, lastEnded: "2026-11-28" });
  });

  it("keeps Box Fort's best points and Sniff's guesses", () => {
    let s = addToStats(null, on("2026-11-23", "done", { points: 120 }));
    s = addToStats(s, on("2026-11-24", "done", { points: 300 }));
    expect(s.bestPoints).toBe(300);
    expect(s.bestTimeMs).toBeNull();
    let w = addToStats(null, on("2026-11-23", "solved", { guesses: 4 }));
    w = addToStats(w, on("2026-11-24", "solved", { guesses: 4 }));
    w = addToStats(w, on("2026-11-25", "missed", { guesses: 6 }));
    expect(w.guesses).toEqual([0, 0, 0, 2, 0, 0]);
  });

  it("keeps the last 30 days, oldest first", () => {
    let s: Stats | null = null;
    for (let d = 0; d < 40; d++) s = addToStats(s, on(addDays("2026-10-01", d), d % 2 === 0 ? "solved" : "gaveUp"));
    const last = (s as Stats).last30;
    expect(last).toHaveLength(30);
    expect(last[0]?.date).toBe(addDays("2026-10-01", 10));
    expect(last.at(-1)).toEqual({ date: addDays("2026-10-01", 39), result: on(addDays("2026-10-01", 39), "gaveUp") });
  });

  it("emptyStats is what a game nobody played shows", () => {
    expect(emptyStats()).toEqual({ played: 0, solved: 0, streak: 0, best: 0, bestTimeMs: null, bestPoints: null, guesses: [0, 0, 0, 0, 0, 0], last30: [], lastEnded: null });
  });

  it("statsView shows a streak only while it's alive: ended today or yesterday", () => {
    const s = addToStats(addToStats(null, on("2026-11-23")), on("2026-11-24"));
    expect(statsView(s, "2026-11-24").streak).toBe(2);
    expect(statsView(s, "2026-11-25").streak).toBe(2);
    expect(statsView(s, "2026-11-26").streak).toBe(0);
    expect(statsView(s, "2026-11-26").best).toBe(2);
  });
});

describe("mergeStats (an account merge)", () => {
  const on = (date: string, outcome: Outcome = "solved", extra: Partial<DailyResult> = {}) => result({ date, outcome, ...extra });
  const fold = (rs: DailyResult[]) => rs.reduce<Stats | null>((s, r) => addToStats(s, r), null);

  it("adds the two sides' counts, less the results the merge dropped", () => {
    const a = fold([on("2026-11-20", "solved", { timeMs: 90_000 }), on("2026-11-21", "solved", { timeMs: 80_000, guesses: 3 })]);
    const dropped = on("2026-11-21", "gaveUp", { timeMs: 5000 });
    const b = fold([on("2026-11-19", "solved", { timeMs: 70_000, guesses: 2 }), dropped]);
    const m = mergeStats(a, b, [dropped]) as Stats;
    expect(m).toMatchObject({ played: 3, solved: 3, bestTimeMs: 70_000, guesses: [0, 1, 1, 0, 0, 0] });
    expect(m.last30.map((e) => [e.date, e.result?.outcome])).toEqual([
      ["2026-11-19", "solved"],
      ["2026-11-20", "solved"],
      ["2026-11-21", "solved"],
    ]);
    // Three days in a row once merged.
    expect(m).toMatchObject({ streak: 3, best: 3, lastEnded: "2026-11-21" });
  });

  it("a dropped solve comes off solved and its guesses", () => {
    const dropped = on("2026-11-21", "solved", { guesses: 4, points: 50 });
    const m = mergeStats(fold([on("2026-11-21", "gaveUp")]), fold([dropped]), [dropped]) as Stats;
    expect(m).toMatchObject({ played: 1, solved: 0, guesses: [0, 0, 0, 0, 0, 0] });
    expect(m.last30).toEqual([{ date: "2026-11-21", result: on("2026-11-21", "gaveUp") }]);
  });

  it("keeps the better records and the longer streak, and takes either side alone", () => {
    const a = { ...emptyStats(), played: 50, solved: 40, streak: 40, best: 45, bestTimeMs: 60_000, bestPoints: 900, lastEnded: "2026-11-21" };
    const b = { ...emptyStats(), played: 2, solved: 1, streak: 1, best: 2, bestTimeMs: null, bestPoints: 1000, lastEnded: "2026-11-20" };
    expect(mergeStats(a, b, [])).toMatchObject({ played: 52, solved: 41, streak: 40, best: 45, bestTimeMs: 60_000, bestPoints: 1000, lastEnded: "2026-11-21" });
    expect(mergeStats(b, a, [])).toMatchObject({ streak: 40, best: 45 });
    expect(mergeStats(null, b, [])).toEqual(b);
    expect(mergeStats(a, null, [])).toEqual(a);
    expect(mergeStats(null, null, [])).toBeNull();
    // A side with no stats still loses what the merge dropped from the other.
    const solved = on("2026-11-21");
    expect(mergeStats(fold([solved]), null, [solved])).toMatchObject({ played: 0, solved: 0, last30: [], streak: 0 });
    expect(mergeStats(null, fold([solved]), [solved])).toMatchObject({ played: 0, solved: 0, last30: [], streak: 0, lastEnded: null });
  });
});
