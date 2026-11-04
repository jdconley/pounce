import { describe, expect, test } from "vitest";

import { ANSWER_MS, answerable, LIVE_MS, nextAnswer, NO_REST_MS, pounceView, restingUntil, UNANSWERED_REST_MS, type PounceRow } from "./limits";

const M = 60_000;
const H = 60 * M;
const NOW = Date.UTC(2026, 10, 4, 20);

let n = 0;
const row = (over: Partial<PounceRow> = {}): PounceRow => ({
  id: `pc_${(n += 1)}`,
  to: "p_mia",
  target: "pick",
  at: NOW,
  answer: null,
  answeredAt: null,
  code: null,
  quiet: false,
  ...over,
});

describe("restingUntil (§12.4)", () => {
  test("nothing sent: not resting", () => {
    expect(restingUntil([], NOW)).toBeNull();
  });

  test("3 an hour: the 4th waits until the oldest of the three is an hour old", () => {
    const rows = [row({ at: NOW - 50 * M, answer: "later", answeredAt: NOW - 49 * M }), row({ at: NOW - 20 * M, answer: "later", answeredAt: NOW - 19 * M })];
    expect(restingUntil(rows, NOW)).toBeNull();
    rows.push(row({ at: NOW - 5 * M, answer: "play", answeredAt: NOW - 4 * M }));
    expect(restingUntil(rows, NOW)).toBe(NOW - 50 * M + H);
    expect(restingUntil(rows, NOW + 10 * M)).toBeNull();
  });

  test("after Not now, an hour's rest from the answer", () => {
    const rows = [row({ at: NOW - 30 * M, answer: "no", answeredAt: NOW - 10 * M })];
    expect(restingUntil(rows, NOW)).toBe(NOW - 10 * M + NO_REST_MS);
    expect(restingUntil(rows, NOW + 50 * M)).toBeNull();
  });

  test("after 3 unanswered in a row, 3 hours' rest; an answer clears it", () => {
    const rows = [row({ at: NOW - 5 * H }), row({ at: NOW - 4 * H }), row({ at: NOW - 2 * H })];
    expect(restingUntil(rows, NOW)).toBe(NOW - 2 * H + UNANSWERED_REST_MS);
    expect(restingUntil(rows, NOW + H)).toBeNull();
    // A 4th is allowed after the rest; the 6th rests again.
    expect(restingUntil([...rows, row({ at: NOW + 2 * H })], NOW + 2 * H)).toBeNull();
    const answered = [...rows.slice(0, 2), { ...(rows[2] as PounceRow), answer: "later" as const, answeredAt: NOW - H }];
    expect(restingUntil(answered, NOW)).toBeNull();
  });
});

describe("pounceView", () => {
  test("sent shows for the hour; quiet when it landed silently; answers show; waiting is theirs", () => {
    const mine = [row({ at: NOW - 10 * M, quiet: true })];
    expect(pounceView(mine, [], NOW)).toEqual({ sent: true, resting: false, quiet: true, answer: null, code: null, waiting: null });
    expect(pounceView(mine, [], NOW - 10 * M + LIVE_MS).sent).toBe(false);
    const played = [row({ at: NOW - 10 * M, answer: "play", answeredAt: NOW - 5 * M, code: "NWCDF" })];
    expect(pounceView(played, [], NOW)).toMatchObject({ sent: false, answer: "play", code: "NWCDF" });
    expect(pounceView(played, [], NOW + H).answer).toBeNull();
    const theirs = [row({ id: "pc_old", at: NOW - 30 * M, target: "new" }), row({ id: "pc_new", at: NOW - 5 * M, target: { table: "GH2VD" } })];
    expect(pounceView([], theirs, NOW).waiting).toEqual({ id: "pc_new", target: { table: "GH2VD" } });
    expect(pounceView([], theirs, NOW + H).waiting).toBeNull();
    expect(pounceView([], [row({ answer: "no", answeredAt: NOW })], NOW).waiting).toBeNull();
    expect(pounceView([row({ answer: "no", answeredAt: NOW })], [], NOW).resting).toBe(true);
  });
});

describe("answers", () => {
  test("answerable for 24 hours", () => {
    expect(answerable(row({ at: NOW }), NOW + ANSWER_MS - 1)).toBe(true);
    expect(answerable(row({ at: NOW }), NOW + ANSWER_MS)).toBe(false);
  });

  test("an answer changes the pounce unless it repeats or downgrades a Play", () => {
    expect(nextAnswer(row(), "later")).toBe(true);
    expect(nextAnswer(row({ answer: "later" }), "play")).toBe(true);
    expect(nextAnswer(row({ answer: "no" }), "later")).toBe(true);
    expect(nextAnswer(row({ answer: "later" }), "later")).toBe(false);
    expect(nextAnswer(row({ answer: "play" }), "no")).toBe(false);
  });
});
