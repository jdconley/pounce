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
  /** A digest of each remembered batch's moves, by `from`: only the same batch gets the stored answer. */
  batches?: Record<number, string>;
  /** The answer to each hint, by the count of hints before it, so a resent hint gets the same reply. */
  hintAnswers?: Record<number, Answer>;
  /** The ended run reached its player (`DailyRun` retries until it does). */
  reported?: boolean;
};
/**
 * An answer to a batch, a hint or a give-up. `seq` counts the moves accepted so far (hints aren't
 * moves). A refusal's `at` is the index of the move refused in its batch, 0 when it isn't about
 * one move.
 */
export type Answer =
  | { ok: true; seq: number; reveals: unknown[]; progress: number; result: DailyResult | null }
  | { ok: false; error: "illegal" | "too_soon" | "over" | "stale" | "bad_message"; at: number; seq: number };

/** What `POST /v1/daily/{game}/start` answers (docs/daily-protocol.md). */
export type StartView = {
  run: string;
  game: DailyGameId;
  date: Day;
  number: number;
  level: number;
  startedAt: number;
  now: number;
  puzzle: unknown;
  state: unknown;
  seq: number;
  hints: number;
  result: DailyResult | null;
  closesAt: number;
};

/** What a hint costs on the clock. */
export const HINT_PENALTY_MS = 30_000;
/**
 * Moves a run may make beyond one per `minMoveGapMs` since its start: a batch of a second's moves,
 * and network jitter, fit; a bot's flood doesn't.
 */
export const MOVE_BURST = 10;
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
  // Only the result's own fields: the server's numbers, and the game's guesses, points and
  // progress. Nothing else a game returns (an answer, say) ever reaches a board.
  const result: DailyResult = {
    game: r.game,
    date: r.date,
    number: puzzleNumber(r.date),
    outcome,
    timeMs,
    hints: r.hints,
    ...(base.guesses === undefined ? {} : { guesses: base.guesses }),
    ...(base.points === undefined ? {} : { points: base.points }),
    progress: base.progress,
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

/** The run as start answers it: the public puzzle and state only, never the whole puzzle. */
export function startView(m: DailyModule, p: unknown, r: RunState, now: number): StartView {
  return {
    run: r.id,
    game: r.game,
    date: r.date,
    number: puzzleNumber(r.date),
    level: levelFor(r.date),
    startedAt: r.startedAt,
    now,
    puzzle: m.publicPuzzle(p),
    state: m.publicState(p, r.state),
    seq: r.seq,
    hints: r.hints,
    result: r.result,
    closesAt: closesAt(r.date, r.zone),
  };
}

/**
 * A batch of moves from `from`, all or nothing: the first move refused refuses the batch and
 * nothing changes. A batch resent from an earlier `from` gets the answer it got then.
 */
export function moves(m: DailyModule, p: unknown, r: RunState, from: number, raw: unknown[], now: number): Answer {
  if (!Array.isArray(raw) || raw.length > MAX_BATCH) return refuse(r, "bad_message");
  if (from < r.seq) return (r.batches?.[from] === digest(raw) ? r.answers[from] : undefined) ?? refuse(r, "stale");
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
    // The move budget: at most one move per `minMoveGapMs` since the start, plus a burst for
    // batching and network jitter. Clients batch for up to a second, so moves arrive together.
    if (m.minMoveGapMs > 0 && r.seq + i + 1 > Math.floor((now - r.startedAt) / m.minMoveGapMs) + MOVE_BURST) {
      return refuse(r, "too_soon", i);
    }
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
  r.batches = { ...r.batches, [from]: digest(raw) };
  for (const key of Object.keys(r.answers).map(Number).sort((x, y) => x - y).slice(0, -KEPT_ANSWERS)) {
    delete r.answers[key];
    delete r.batches[key];
  }
  return a;
}

/**
 * A hint from the server: it costs `HINT_PENALTY_MS` and isn't a move. `seen`: the hints the
 * client had used when it asked; a hint asked again with the same count gets the same answer.
 */
export function useHint(m: DailyModule, p: unknown, r: RunState, now: number, seen?: number): Answer {
  if (seen !== undefined && seen < r.hints) return r.hintAnswers?.[seen] ?? refuse(r, "stale");
  if (seen !== undefined && seen > r.hints) return refuse(r, "stale");
  const over = finished(m, p, r, now);
  if (over) return over;
  const applied = m.hint(p, r.state);
  if (applied === null) return refuse(r, "illegal");
  if (!applied.ok) return refuse(r, applied.reason);
  r.state = applied.state;
  const before = r.hints;
  r.hints += 1;
  if (applied.end) end(m, p, r, applied.end, now);
  const a = answer(m, p, r, applied.reveal === undefined ? [] : [applied.reveal]);
  r.hintAnswers = { ...r.hintAnswers, [before]: a };
  return a;
}

/** A short digest of a batch's moves (FNV-1a, twice over), to tell a resend from a different batch. */
function digest(raw: unknown[]): string {
  const text = JSON.stringify(raw);
  let a = 0x811c9dc5;
  let b = 0x01000193;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193) >>> 0;
    b = Math.imul(b ^ c, 0x811c9dc5) >>> 0;
  }
  return `${a.toString(36)}.${b.toString(36)}.${text.length}`;
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
