import type { Answer } from "../notify/copy";

export type { Answer } from "../notify/copy";

/** What a pounce asks for (§12.4): a table you share (by code), a new game, or "you pick". */
export type Target = { table: string } | "new" | "pick";

/** One pounce, as the sender's `Player` keeps it (§13.2). `to` is null for a link nobody has answered. */
export type PounceRow = {
  id: string;
  to: string | null;
  target: Target;
  at: number;
  answer: Answer | null;
  answeredAt: number | null;
  /** The table "Play" sent them to. */
  code: string | null;
  /** It landed in the recipient's quiet hours: the sender sees a moon. */
  quiet: boolean;
};

const M = 60_000;
const H = 60 * M;
/** At most 3 pounces an hour from one person to another (§12.4). */
export const PER_HOUR = 3;
export const NO_REST_MS = H;
export const UNANSWERED = 3;
export const UNANSWERED_REST_MS = 3 * H;
/** A pounce shows as sent, or waiting, for an hour (§11.1 "until it's answered or the hour passes"). */
export const LIVE_MS = H;
/** A pounce can be answered for a day, like a link. */
export const ANSWER_MS = 24 * H;
/** Pounces are kept 7 days (§14). */
export const KEEP_MS = 7 * 24 * H;

const newestFirst = (rows: PounceRow[]) => [...rows].sort((a, b) => b.at - a.at);

/**
 * When this sender may pounce on this person again (§12.4), or null when
 * they may now: 3 an hour; an hour after "Not now"; 3 hours after every
 * third unanswered pounce in a row.
 */
export function restingUntil(rows: PounceRow[], now: number): number | null {
  const sorted = newestFirst(rows);
  const until: number[] = [];
  const third = sorted[PER_HOUR - 1];
  if (third && third.at > now - H) until.push(third.at + H);
  for (const r of sorted) if (r.answer === "no" && r.answeredAt !== null) until.push(r.answeredAt + NO_REST_MS);
  let unanswered = 0;
  while (unanswered < sorted.length && (sorted[unanswered] as PounceRow).answer === null) unanswered += 1;
  if (unanswered >= UNANSWERED && unanswered % UNANSWERED === 0) until.push((sorted[0] as PounceRow).at + UNANSWERED_REST_MS);
  const latest = Math.max(...until.filter((t) => t > now));
  return Number.isFinite(latest) ? latest : null;
}

/** A pair's pounce state for one person (the `pounce` field of `StreakView`, §13.4). */
export type PounceView = {
  /** My latest pounce on them is out and unanswered, this hour. */
  sent: boolean;
  /** I can't pounce on them right now (the sleeping bell). */
  resting: boolean;
  /** My pounce landed in their quiet hours (the moon). */
  quiet: boolean;
  /** Their answer to my latest pounce, this hour. */
  answer: Answer | null;
  code: string | null;
  /** Their unanswered pounce on me, this hour. */
  waiting: { id: string; target: Target } | null;
};

export function pounceView(mine: PounceRow[], theirs: PounceRow[], now: number): PounceView {
  const latest = newestFirst(mine)[0];
  const live = latest !== undefined && latest.answer === null && now - latest.at < LIVE_MS;
  const answered = latest?.answer != null && now - (latest.answeredAt as number) < LIVE_MS;
  const waiting = newestFirst(theirs).find((r) => r.answer === null && now - r.at < LIVE_MS);
  return {
    sent: live,
    resting: restingUntil(mine, now) !== null,
    quiet: live && latest.quiet,
    answer: answered ? (latest.answer as Answer) : null,
    code: answered ? latest.code : null,
    waiting: waiting ? { id: waiting.id, target: waiting.target } : null,
  };
}

export function answerable(row: PounceRow, now: number): boolean {
  return now - row.at < ANSWER_MS;
}

/** Whether `answer` changes the pounce: not a repeat, and never a step down from "Play". */
export function nextAnswer(row: PounceRow, answer: Answer): boolean {
  return row.answer !== answer && row.answer !== "play";
}
