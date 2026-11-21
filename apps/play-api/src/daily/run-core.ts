import { closesAt, levelFor, puzzleNumber } from "./days";

import type { DailyGameId, DailyModule, DailyResult, Outcome } from "./module";
import type { Day } from "../streaks/clock";

/**
 * The run referee (spec §3, "A run"): one player's run at one game on one date, refereed move by
 * move with the game's own rules. The server's clock is the only clock and the server works out
 * the result; nothing here takes a time, a score or an outcome from a client. Pure: `DailyRun`
 * loads a `RunState`, calls one of these, and saves it.
 */
export type RunState = {
  id: string; playerId: string; game: DailyGameId; date: Day; zone: string;
  startedAt: number; seq: number; state: unknown; hints: number;
  lastMoveAt: number; ended: { outcome: Outcome; at: number } | null;
  result: DailyResult | null; tv: boolean;
  answers: Record<number, Answer>; // the answer for each batch's `from`, so a resend gets the same reply
};
/**
 * An answer to a batch, a hint or a give-up. `seq` counts the moves accepted so far (hints aren't
 * moves). A refusal's `at` is the index of the move refused in its batch, 0 when it isn't about
 * one move.
 */
export type Answer =
  | { ok: true; seq: number; reveals: unknown[]; progress: number; result: DailyResult | null }
  | { ok: false; error: "illegal" | "too_soon" | "over" | "stale" | "bad_message"; at: number; seq: number };

/** What a hint costs on the clock. */
export const HINT_PENALTY_MS = 30_000;
/** The most moves one batch may carry. */
export const MAX_BATCH = 100;
/** How many accepted batches' answers are kept for resends: a dropped connection resends the last one or two. */
const KEPT_ANSWERS = 8;

type Refusal = Extract<Answer, { ok: false }>["error"];

const refuse = (r: RunState, error: Refusal, at = 0): Answer => ({ ok: false, error, at, seq: r.seq });

function answer(m: DailyModule, p: unknown, r: RunState, reveals: unknown[]): Answer {
  return { ok: true, seq: r.seq, reveals, progress: m.progress(p, r.state), result: r.result };
}

/** Ends the run at `at` and works out its result, on the server's numbers. */
function end(m: DailyModule, p: unknown, r: RunState, outcome: Outcome, at: number): DailyResult {
  const timeMs = at - r.startedAt + HINT_PENALTY_MS * r.hints;
  const base = m.result(p, r.state, outcome, timeMs, r.hints);
  const result: DailyResult = {
    game: r.game,
    date: r.date,
    number: puzzleNumber(r.date),
    ...base,
    outcome,
    timeMs,
    hints: r.hints,
    tooFast: timeMs < m.floorMs[levelFor(r.date)],
  };
  r.ended = { outcome, at };
  r.result = result;
  return result;
}

/** A refusal when the run can't take anything more: closed at its day's end first, if due. */
function finished(m: DailyModule, p: unknown, r: RunState, now: number): Answer | null {
  close(m, p, r, now);
  return r.ended ? refuse(r, "over") : null;
}

export function newRun(
  m: DailyModule,
  p: unknown,
  a: { id: string; playerId: string; game: DailyGameId; date: Day; zone: string; now: number },
): RunState {
  return {
    id: a.id,
    playerId: a.playerId,
    game: a.game,
    date: a.date,
    zone: a.zone,
    startedAt: a.now,
    seq: 0,
    state: m.init(p),
    hints: 0,
    lastMoveAt: 0,
    ended: null,
    result: null,
    tv: false,
    answers: {},
  };
}

/**
 * A batch of moves from `from`, all or nothing: the first move refused refuses the batch and
 * nothing changes. A batch resent from an earlier `from` gets the answer it got then.
 */
export function moves(m: DailyModule, p: unknown, r: RunState, from: number, raw: unknown[], now: number): Answer {
  if (!Array.isArray(raw) || raw.length > MAX_BATCH) return refuse(r, "bad_message");
  if (from < r.seq) return r.answers[from] ?? refuse(r, "stale");
  const over = finished(m, p, r, now);
  if (over) return over;
  if (from > r.seq) return refuse(r, "stale");
  let state = r.state;
  let ending: "solved" | "missed" | "done" | undefined;
  const reveals: unknown[] = [];
  for (const [i, item] of raw.entries()) {
    if (ending) return refuse(r, "over", i);
    const move = m.parseMove(item);
    if (move === null) return refuse(r, "bad_message", i);
    // Moves in one batch arrive together: only the first can be spaced from the last batch.
    const previous = i === 0 ? r.lastMoveAt : now;
    if (previous > 0 && now - previous < m.minMoveGapMs) return refuse(r, "too_soon", i);
    const applied = m.apply(p, state, move, now - r.startedAt);
    if (!applied.ok) return refuse(r, applied.reason, i);
    state = applied.state;
    if (applied.reveal !== undefined) reveals.push(applied.reveal);
    ending = applied.end;
  }
  if (raw.length === 0) return answer(m, p, r, reveals);
  r.state = state;
  r.seq += raw.length;
  r.lastMoveAt = now;
  if (ending) end(m, p, r, ending, now);
  const a = answer(m, p, r, reveals);
  r.answers[from] = a;
  for (const key of Object.keys(r.answers).map(Number).sort((x, y) => x - y).slice(0, -KEPT_ANSWERS)) delete r.answers[key];
  return a;
}

/** A hint from the server: it costs `HINT_PENALTY_MS` and isn't a move. */
export function useHint(m: DailyModule, p: unknown, r: RunState, now: number): Answer {
  const over = finished(m, p, r, now);
  if (over) return over;
  const applied = m.hint(p, r.state);
  if (applied === null) return refuse(r, "illegal");
  if (!applied.ok) return refuse(r, applied.reason);
  r.state = applied.state;
  r.hints += 1;
  if (applied.end) end(m, p, r, applied.end, now);
  return answer(m, p, r, applied.reveal === undefined ? [] : [applied.reveal]);
}

/** Ends the run unsolved. */
export function giveUp(m: DailyModule, p: unknown, r: RunState, now: number): Answer {
  const over = finished(m, p, r, now);
  if (over) return over;
  end(m, p, r, "gaveUp", now);
  return answer(m, p, r, []);
}

/** At its day's end an open run closes, unsolved, at 04:00 however late this runs. Null: nothing new. */
export function close(m: DailyModule, p: unknown, r: RunState, now: number): DailyResult | null {
  const at = closesAt(r.date, r.zone);
  if (r.ended || now < at) return null;
  return end(m, p, r, "closed", at);
}

/** An ended run counts toward streaks: one the player finished or gave up, with at least one move (spec §5). */
export function countsForStreak(r: RunState): boolean {
  return r.ended !== null && r.ended.outcome !== "closed" && r.seq > 0;
}
