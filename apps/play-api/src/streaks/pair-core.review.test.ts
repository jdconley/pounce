import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDays, pairOn, pass, play, settle } from "../../tests/streak-helpers";

import { addDays } from "./clock";
import { advance, nextWakeAt, pause, view } from "./pair-core";

const day = (n: number) => addDays(D0, n);

/** Fixes from the whole-branch review. */
describe("review fixes", () => {
  it("re-pausing before the last paused day settles keeps that day paused", () => {
    const s = pairOn();
    keepDays(s, D0, 5);
    s.streak.naps = 0;
    pause(s, A, 1, at(day(5), "09:00"));
    // 04:05 the next morning: day 5 hasn't settled yet (04:10).
    pause(s, A, 2, at(day(6), "04:05"));
    settle(s, day(5));
    expect(s.days[day(5)]?.state).toBe("paused");
    expect(s.streak).toMatchObject({ count: 5, winback: null, pausedUntil: day(7) });
  });

  it("lights no paws on a day nobody has played, and says when today is kept", () => {
    const s = pairOn();
    keepDays(s, D0, 3);
    pass(s, at(day(2), "11:00"), C);
    const quiet = view(s, A, at(day(3), "21:00"));
    expect([quiet.me, quiet.them, quiet.kept]).toEqual([false, false, false]);
    play(s, A, at(day(3), "21:30"), C);
    const kept = view(s, B, at(day(3), "21:31"));
    expect([kept.me, kept.them, kept.kept]).toEqual([true, true, true]);
  });

  it("doesn't send when anyone last played", () => {
    const s = pairOn();
    keepDays(s, D0, 1);
    expect(view(s, A, at(D0, "11:00"))).not.toHaveProperty("lastTurnAt");
  });

  it("wakes an idle pair to drop day rows past 120 days", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    expect(s.streak.count).toBe(0);
    const wake = nextWakeAt(s) as number;
    expect(wake).toBe(Date.parse(`${addDays(D0, 121)}T00:00:00Z`));
    advance(s, wake);
    expect(s.days[D0]).toBeUndefined();
    expect(nextWakeAt(s)).toBeGreaterThan(wake);
    const empty = pairOn();
    empty.days = {};
    expect(nextWakeAt(empty)).toBeNull();
  });
});
