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

/**
 * One game's board: results ranked best first by the game's own `compare`, then people still
 * playing, furthest first. A run marked too fast is left off; so is anyone with neither.
 */
export function rankGame(m: DailyModule, rows: BoardRow[]): BoardRow[] {
  const done = rows.filter((r) => r.result !== null && !r.result.tooFast).sort((a, b) => m.compare(a.result as DailyResult, b.result as DailyResult));
  const placed = ranks(done, (a, b) => m.compare(a.result as DailyResult, b.result as DailyResult) === 0);
  const playing = rows
    .filter((r) => r.result === null && r.playing !== null)
    .sort((a, b) => (b.playing as { progress: number }).progress - (a.playing as { progress: number }).progress);
  return [...done.map((r, i) => ({ ...r, rank: placed[i] as number })), ...playing.map((r) => ({ ...r, rank: null }))];
}

/**
 * The overall board, the Dish (spec §6): per game 3, 2 and 1 points for the first three places
 * (ties share a place's points), plus 1 for each ended run (a run closed at 04:00 didn't end), and
 * a crown for each game won. Only ranked rows count: too-fast runs and people still playing earn
 * nothing.
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
  const sorted = [...byPlayer.values()].sort(
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
