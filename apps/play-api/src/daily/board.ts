import { addDays, daysBetween, type Day } from "../streaks/clock";

import type { DailyGameId, DailyModule, DailyResult } from "./module";

/**
 * The family board (spec §6) and per-game stats (spec §7), pure. A board holds only people who
 * played or are playing: never who hasn't, never a "last". `rank` is a 1-based competition rank
 * (ties share it, and the next rank skips); null for someone still playing.
 */
export type BoardRow = { player: string; name: string; cat: number; rank: number | null; result: DailyResult | null; playing: { progress: number } | null };
export type GameBoard = { game: DailyGameId; number: number; rows: BoardRow[] }; // played rows only, ranked by module.compare
export type DishRow = { player: string; name: string; cat: number; rank: number; points: number; crowns: DailyGameId[]; ended: number };
export type Dish = { rows: DishRow[] };
/**
 * One game's lifetime stats for one player. `streak` counts consecutive dates with an ended run
 * (`lastEnded` the latest); `guesses[i]` counts Sniff solves in i + 1 guesses; `last30` holds the
 * results of the last 30 days, oldest first.
 */
export type Stats = {
  played: number; solved: number; streak: number; best: number;
  bestTimeMs: number | null; bestPoints: number | null; guesses: number[];
  last30: { date: Day; result: DailyResult | null }[];
  lastEnded: Day | null;
};

/** Dish points for first, second and third in a game. */
const PLACES = [3, 2, 1];
const WINDOW_DAYS = 30;
const SNIFF_TRIES = 6;

/** 1-based competition ranks for a sorted list: equal neighbours share one. */
function ranks<T>(sorted: T[], same: (a: T, b: T) => boolean): number[] {
  const out: number[] = [];
  sorted.forEach((item, i) => out.push(i > 0 && same(sorted[i - 1] as T, item) ? (out[i - 1] as number) : i + 1));
  return out;
}

/** A run that finished the puzzle: solved, or Box Fort's normal ending. Everything else didn't. */
export const finishedRun = (r: DailyResult): boolean => r.outcome === "solved" || r.outcome === "done";

/** A result's percent: its own, or for one stored before `percent`, its progress. */
export const percentOf = (r: DailyResult): number => r.percent ?? Math.max(0, Math.min(100, Math.floor(r.progress * 100 + 1e-9)));

/**
 * The board's order for one game (spec §6, "Ranking", JD 2026-11-26: "if you fail or quit any
 * puzzle you should get ranked on % completed as well. just lower rank than anyone that completed
 * it"): every finished run first, by the game's own `compare`; then every run that failed, was
 * given up or closed at 04:00, by percent, highest first, then the shorter time.
 */
export function rankOrder(m: DailyModule): (a: DailyResult, b: DailyResult) => number {
  return (a, b) => {
    const [fa, fb] = [finishedRun(a), finishedRun(b)];
    if (fa !== fb) return fa ? -1 : 1;
    if (fa) return m.compare(a, b);
    return percentOf(b) - percentOf(a) || a.timeMs - b.timeMs;
  };
}

/**
 * One game's board: results ranked best first (`rankOrder`), then people still playing, furthest
 * first. A run marked too fast is left off; so is anyone with neither.
 */
export function rankGame(m: DailyModule, rows: BoardRow[]): BoardRow[] {
  const order = rankOrder(m);
  const done = rows.filter((r) => r.result !== null && !r.result.tooFast).sort((a, b) => order(a.result as DailyResult, b.result as DailyResult));
  const placed = ranks(done, (a, b) => order(a.result as DailyResult, b.result as DailyResult) === 0);
  const playing = rows
    .filter((r) => r.result === null && r.playing !== null)
    .sort((a, b) => (b.playing as { progress: number }).progress - (a.playing as { progress: number }).progress);
  return [...done.map((r, i) => ({ ...r, rank: placed[i] as number })), ...playing.map((r) => ({ ...r, rank: null }))];
}

/**
 * The overall board, the Dish (spec §6): per game 3, 2 and 1 points for the first three places
 * (ties share a place's points), plus 1 for each ended run (a run closed at 04:00 didn't end), and
 * a crown for each game won. Only ranked rows count: too-fast runs and people still playing earn
 * nothing. Only rows with at least 1 point are listed.
 */
export function dish(boards: GameBoard[]): Dish {
  const byPlayer = new Map<string, DishRow>();
  for (const b of boards) {
    for (const r of b.rows) {
      if (r.rank === null || r.result === null || r.result.tooFast) continue;
      const row = byPlayer.get(r.player) ?? { player: r.player, name: r.name, cat: r.cat, rank: 0, points: 0, crowns: [], ended: 0 };
      row.points += PLACES[r.rank - 1] ?? 0;
      if (r.result.outcome !== "closed") {
        row.points += 1;
        row.ended += 1;
      }
      if (r.rank === 1) row.crowns.push(b.game);
      byPlayer.set(r.player, row);
    }
  }
  // No row with 0 points: no last place, and no row for someone who only ran out the clock.
  const sorted = [...byPlayer.values()].filter((r) => r.points > 0).sort(
    (a, b) => b.points - a.points || b.crowns.length - a.crowns.length || b.ended - a.ended || a.name.localeCompare(b.name),
  );
  const placed = ranks(sorted, (a, b) => a.points === b.points);
  return { rows: sorted.map((r, i) => ({ ...r, rank: placed[i] as number })) };
}

export function emptyStats(): Stats {
  return { played: 0, solved: 0, streak: 0, best: 0, bestTimeMs: null, bestPoints: null, guesses: Array<number>(SNIFF_TRIES).fill(0), last30: [], lastEnded: null };
}

/** The stats with one more result. */
export function addToStats(s: Stats | null, r: DailyResult): Stats {
  const out: Stats = s ? { ...s, guesses: [...s.guesses], last30: [...s.last30] } : emptyStats();
  out.played += 1;
  if (r.outcome === "solved") {
    out.solved += 1;
    if (out.bestTimeMs === null || r.timeMs < out.bestTimeMs) out.bestTimeMs = r.timeMs;
    if (r.guesses !== undefined && r.guesses >= 1 && r.guesses <= SNIFF_TRIES) out.guesses[r.guesses - 1] = (out.guesses[r.guesses - 1] as number) + 1;
  }
  if (r.points !== undefined && (out.bestPoints === null || r.points > out.bestPoints)) out.bestPoints = r.points;
  if (r.outcome === "closed") {
    out.streak = 0;
  } else {
    out.streak = out.lastEnded !== null && addDays(out.lastEnded, 1) === r.date ? out.streak + 1 : 1;
    out.lastEnded = r.date;
    out.best = Math.max(out.best, out.streak);
  }
  out.last30 = [...out.last30.filter((e) => e.date !== r.date), { date: r.date, result: r }]
    .filter((e) => daysBetween(e.date, r.date) < WINDOW_DAYS)
    .sort((a, b) => a.date.localeCompare(b.date));
  return out;
}

/** The stats as shown on `today`: a streak whose last ended run was before yesterday is over. */
export function statsView(s: Stats, today: Day): Stats {
  const alive = s.lastEnded !== null && daysBetween(s.lastEnded, today) <= 1;
  return alive ? s : { ...s, streak: 0 };
}

const sameResult = (x: DailyResult | null, y: DailyResult) => x !== null && JSON.stringify(x) === JSON.stringify(y);

/**
 * Two players' stats for one game, after an account merge: the counts added, less the results the
 * merge dropped (a second run of the same puzzle); the better records; the last 30 days together;
 * and the streak the merged days give, or the longer side's when it ran past them.
 */
export function mergeStats(x: Stats | null, y: Stats | null, dropped: DailyResult[]): Stats | null {
  if ((!x || !y) && dropped.length === 0) return x ?? y;
  const [a, b] = [x ?? emptyStats(), y ?? emptyStats()];
  const solvedOut = dropped.filter((r) => r.outcome === "solved");
  const guesses = a.guesses.map((n, i) => n + (b.guesses[i] as number) - solvedOut.filter((r) => r.guesses === i + 1).length);
  const best = <T>(x: T | null, y: T | null, pick: (p: T, q: T) => T) => (x === null ? y : y === null ? x : pick(x, y));
  const byDate = new Map<Day, { date: Day; result: DailyResult | null }>();
  for (const e of [...a.last30, ...b.last30]) {
    if (dropped.some((d) => sameResult(e.result, d)) || byDate.has(e.date)) continue;
    byDate.set(e.date, e);
  }
  const days = [...byDate.values()].sort((x, y) => x.date.localeCompare(y.date));
  const newest = days.at(-1)?.date;
  const last30 = newest === undefined ? [] : days.filter((e) => daysBetween(e.date, newest) < WINDOW_DAYS);
  const ended = new Set(last30.filter((e) => e.result !== null && e.result.outcome !== "closed").map((e) => e.date));
  // A side's last ended day still counts unless the merge dropped the run that ended it.
  const still = (side: Stats) =>
    side.lastEnded !== null && (ended.has(side.lastEnded) || !dropped.some((d) => d.date === side.lastEnded)) ? side.lastEnded : null;
  const lastEnded = [still(a), still(b), [...ended].sort().at(-1) ?? null].reduce((p, q) => best(p, q, (m, n) => (m > n ? m : n)), null);
  let run = 0;
  for (let d = lastEnded; d !== null && ended.has(d); d = addDays(d, -1)) run += 1;
  const counts = (side: Stats) => lastEnded !== null && still(side) === lastEnded;
  const streak = Math.max(run, counts(a) ? a.streak : 0, counts(b) ? b.streak : 0);
  return {
    played: a.played + b.played - dropped.length,
    solved: a.solved + b.solved - solvedOut.length,
    streak,
    best: Math.max(a.best, b.best, streak),
    bestTimeMs: best(a.bestTimeMs, b.bestTimeMs, Math.min),
    bestPoints: best(a.bestPoints, b.bestPoints, Math.max),
    guesses,
    last30,
    lastEnded,
  };
}
