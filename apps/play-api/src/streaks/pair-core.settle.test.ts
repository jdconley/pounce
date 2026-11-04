import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDay, keepDays, missDay, pairOn, pass, play, settle } from "../../tests/streak-helpers";

import { addDays } from "./clock";
import { advance, nextSettleAt, pause, unpause, view } from "./pair-core";

const day = (n: number) => addDays(D0, n);

/** A pair with `n` kept days from D0, settled, with no naps left. */
function streakOf(n: number) {
  const s = pairOn();
  keepDays(s, D0, n);
  settle(s, day(n - 1));
  s.streak.naps = 0;
  return s;
}

describe("cat naps", () => {
  it("cover a missed day without growing or breaking the streak", () => {
    const s = streakOf(10);
    s.streak.naps = 1;
    missDay(s, day(10));
    settle(s, day(10));
    expect(s.days[day(10)]?.state).toBe("nap");
    expect([s.streak.count, s.streak.naps]).toEqual([10, 0]);
    expect(view(s, A, at(day(11), "09:00")).week.at(-2)).toEqual({ day: day(10), state: "nap" });
  });

  it("are earned at the 7-day milestone and for a perfect week, at most two", () => {
    const s = pairOn();
    keepDays(s, D0, 6);
    expect(s.streak.naps).toBe(0);
    keepDay(s, day(6));
    expect(s.streak).toMatchObject({ count: 7, naps: 2, perfectWeeks: 1 });
    keepDays(s, day(7), 7);
    expect(s.streak).toMatchObject({ count: 14, naps: 2, perfectWeeks: 2 });
  });

  it("aren't spent while there's no streak", () => {
    const s = pairOn();
    s.streak.naps = 1;
    missDay(s, D0);
    settle(s, D0);
    expect(s.days[D0]?.state).toBe("missed");
    expect(s.streak.naps).toBe(1);
  });

  it("reset the perfect week run", () => {
    const s = streakOf(4);
    s.streak.naps = 1;
    missDay(s, day(4));
    keepDays(s, day(5), 3);
    expect(s.days[day(4)]?.state).toBe("nap");
    expect(s.streak).toMatchObject({ count: 7, perfectWeeks: 0, perfectRun: 3 });
  });
});

describe("win-back", () => {
  it("starts when a day is missed with no nap, keeping the count", () => {
    const s = streakOf(12);
    missDay(s, day(12));
    settle(s, day(12));
    expect(s.days[day(12)]?.state).toBe("winback");
    expect(view(s, A, at(day(13), "08:00"))).toMatchObject({ count: 12, winback: { kept: 0 } });
    expect(view(s, A, at(day(13), "08:00")).week.at(-2)?.state).toBe("missed");
  });

  it("brings the streak back whole after two kept days, and the miss becomes a nap", () => {
    const s = streakOf(12);
    missDay(s, day(12));
    keepDay(s, day(13));
    expect(view(s, A, at(day(13), "11:00"))).toMatchObject({ count: 13, winback: { kept: 1 } });
    keepDay(s, day(14));
    expect(s.streak.winback).toBeNull();
    expect(s.days[day(12)]?.state).toBe("nap");
    expect(s.streak.count).toBe(14);
  });

  it("ends the streak at 0 when the first day is missed too", () => {
    const s = streakOf(12);
    const breakId = s.streak.breakId;
    missDay(s, day(12));
    missDay(s, day(13));
    settle(s, day(13));
    expect(s.streak).toMatchObject({ count: 0, winback: null, best: 12, lifetimeKept: 12, breakId: breakId + 1 });
    expect(s.days[day(13)]?.state).toBe("missed");
    keepDay(s, day(14));
    expect(s.streak.count).toBe(1);
  });

  it("ends the streak at 0 when the second day is missed", () => {
    const s = streakOf(12);
    missDay(s, day(12));
    keepDay(s, day(13));
    missDay(s, day(14));
    settle(s, day(14));
    expect(s.streak).toMatchObject({ count: 0, winback: null, best: 13 });
  });

  it("waits through a held day", () => {
    const s = streakOf(12);
    missDay(s, day(12));
    pass(s, at(day(12), "23:00"), C);
    settle(s, day(13));
    expect(s.days[day(13)]?.state).toBe("held");
    expect(s.streak.winback).toEqual({ missedDay: day(12), kept: 0 });
  });

  it("can be covered by a nap earned on the way", () => {
    const s = streakOf(6);
    missDay(s, day(6));
    keepDay(s, day(7));
    expect(s.streak).toMatchObject({ count: 7, naps: 1 });
    missDay(s, day(8));
    settle(s, day(8));
    expect(s.days[day(8)]?.state).toBe("nap");
    expect(s.streak.winback).toEqual({ missedDay: day(6), kept: 1 });
  });
});

describe("pause", () => {
  it("lasts up to 14 days, and only that", () => {
    const s = streakOf(3);
    const now = at(day(3), "09:00");
    expect(pause(s, A, 15, now)).toBe(false);
    expect(pause(s, A, 0, now)).toBe(false);
    expect(pause(s, A, 2.5, now)).toBe(false);
    expect(pause(s, C, 3, now)).toBe(false);
    expect(pause(s, A, 14, now)).toBe(true);
    expect(s.streak).toMatchObject({ pausedFrom: day(3), pausedUntil: day(16), pausedBy: A });
    expect(view(s, B, now).pausedUntil).toBe(day(16));
  });

  it("extends from today, never past 14 days from today", () => {
    const s = streakOf(3);
    pause(s, A, 14, at(day(3), "09:00"));
    expect(pause(s, B, 2, at(day(8), "09:00"))).toBe(true);
    expect(s.streak.pausedUntil).toBe(day(16));
    pause(s, B, 14, at(day(8), "09:00"));
    expect(s.streak).toMatchObject({ pausedFrom: day(3), pausedUntil: day(21), pausedBy: B });
  });

  it("starts a new pause once the old one is over", () => {
    const s = streakOf(3);
    pause(s, A, 1, at(day(3), "09:00"));
    pause(s, A, 1, at(day(6), "09:00"));
    expect(s.streak).toMatchObject({ pausedFrom: day(6), pausedUntil: day(6) });
  });

  it("neither grows nor breaks the streak", () => {
    const s = streakOf(3);
    pause(s, A, 2, at(day(3), "09:00"));
    keepDay(s, day(3));
    settle(s, day(4));
    expect(s.days[day(3)]?.state).toBe("paused");
    expect(s.days[day(4)]?.state).toBe("paused");
    expect(s.streak).toMatchObject({ count: 3, winback: null });
    missDay(s, day(5));
    settle(s, day(5));
    expect(s.days[day(5)]?.state).toBe("winback");
    expect(view(s, A, at(day(6), "09:00")).pausedUntil).toBeNull();
  });

  it("starts tomorrow when today is already kept", () => {
    const s = streakOf(3);
    keepDay(s, day(3));
    pause(s, A, 1, at(day(3), "21:00"));
    expect(s.streak).toMatchObject({ pausedFrom: day(4), pausedUntil: day(4) });
    settle(s, day(4));
    expect(s.days[day(3)]?.state).toBe("kept");
    expect(s.days[day(4)]?.state).toBe("paused");
  });

  it("ends early: today counts again before your cutoff, stays paused after it", () => {
    const early = streakOf(3);
    pause(early, A, 5, at(day(3), "09:00"));
    unpause(early, B, at(day(3), "12:00"));
    expect(early.streak).toMatchObject({ pausedFrom: null, pausedUntil: null });

    const late = streakOf(3);
    pause(late, A, 5, at(day(3), "09:00"));
    unpause(late, B, at(day(3), "21:00"));
    expect(late.streak).toMatchObject({ pausedFrom: day(3), pausedUntil: day(3) });

    const midway = streakOf(3);
    pause(midway, A, 5, at(day(3), "09:00"));
    unpause(midway, A, at(day(5), "12:00"));
    expect(midway.streak).toMatchObject({ pausedFrom: day(3), pausedUntil: day(4) });
  });

  it("ignores an unpause with no pause on, or from outside the pair", () => {
    const s = streakOf(3);
    unpause(s, A, at(day(3), "09:00"));
    expect(s.streak.pausedUntil).toBeNull();
    pause(s, A, 3, at(day(3), "09:00"));
    unpause(s, C, at(day(3), "10:00"));
    expect(s.streak.pausedUntil).toBe(day(5));
  });
});

describe("long gaps", () => {
  it("settle in order, end the streak and keep 120 days of rows", () => {
    const s = streakOf(5);
    advance(s, at(day(200), "12:00"));
    expect(s.streak.count).toBe(0);
    expect(s.lastSettled).toBe(day(199));
    expect(Object.keys(s.days).length).toBeLessThanOrEqual(120);
    expect(s.days[D0]).toBeUndefined();
    expect(s.streak).toMatchObject({ best: 5, lifetimeKept: 5 });
  });

  it("wake the pair only while there's a streak to settle", () => {
    const s = pairOn();
    expect(nextSettleAt(s)).toBeNull();
    play(s, A, at(D0, "09:00"), B);
    expect(nextSettleAt(s)).toBeNull();
    play(s, B, at(D0, "10:00"), A);
    expect(nextSettleAt(s)).toBe(at(addDays(D0, 1), "04:10"));
  });
});
