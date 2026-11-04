import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDay, LA, NY, pairOn, pass, person, play, settle } from "../../tests/streak-helpers";

import { addDays } from "./clock";
import { advance, newPair, nextSettleAt, report, setPerson, view } from "./pair-core";

const D1 = addDays(D0, 1);
const D2 = addDays(D0, 2);

describe("a day is kept when both of you are in", () => {
  it("keeps the day at the second person's turn and drops a toy", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    const half = view(s, A, at(D0, "09:01"));
    expect([half.count, half.me, half.them]).toEqual([0, true, false]);
    expect(view(s, B, at(D0, "09:01"))).toMatchObject({ me: false, them: true });

    play(s, B, at(D0, "10:00"), A);
    const kept = view(s, A, at(D0, "10:01"));
    expect([kept.count, kept.me, kept.them]).toEqual([1, true, true]);
    expect(kept.todayToy).toMatch(/^toy-/);
    expect(kept.toys).toEqual([kept.todayToy]);
    expect(s.days[D0]?.state).toBe("kept");
  });

  it("counts the turns each of you took before the pair formed that day", () => {
    const s = newPair("pair_1", [person(A), person(B)], at(D0, "10:00"), [1, 2, 3, 4], { [A]: at(D0, "09:00") });
    report(s, { code: "ROOM1", at: at(D0, "10:00"), by: B, holder: A, over: false }, at(D0, "10:00"));
    expect(view(s, A, at(D0, "10:00")).count).toBe(1);
    // Turns before the pair's first day are not counted.
    const late = newPair("pair_2", [person(A), person(B)], at(D1, "10:00"), [1, 2, 3, 4], { [A]: at(D0, "09:00") });
    expect(late.days[D0]).toBeUndefined();
  });

  it("ignores turns credited to someone outside the pair, and sorts the people", () => {
    const s = newPair("pair_1", [person(B), person(A)], at(D0, "10:00"), [1, 2, 3, 4], { [C]: at(D0, "09:00") });
    expect(s.people.map((p) => p.id)).toEqual([A, B]);
    expect(s.days[D0]?.turns).toEqual({});
  });

  it("refuses a pair of one player with themself", () => {
    expect(() => pairOn(D0, [person(A), person(A)])).toThrow();
  });
});

describe("the late move pass", () => {
  it("covers you when the move reached you only after your evening cutoff", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), C);
    pass(s, at(D0, "20:01"), B);
    expect(view(s, B, at(D0, "20:02"))).toMatchObject({ me: true, them: true, count: 1 });
  });

  it("doesn't cover you when it reached you before the cutoff", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), C);
    pass(s, at(D0, "19:59"), B);
    expect(view(s, B, at(D0, "20:30"))).toMatchObject({ me: false, them: true, count: 0 });
    settle(s, D0);
    expect(s.days[D0]?.state).toBe("missed");
  });

  it("uses each person's own quiet hours", () => {
    const s = pairOn(D0, [person(A), person(B, LA, 23 * 60)]);
    play(s, A, at(D0, "09:00"), C);
    pass(s, at(D0, "20:30"), B);
    // B's cutoff is 21:00, so the move reached B in time to play.
    expect(view(s, B, at(D0, "21:30")).me).toBe(false);
  });

  it("covers a person who waited all day while the other played", () => {
    const s = pairOn();
    pass(s, at(D0, "08:30"), C);
    play(s, A, at(D0, "21:00"), C);
    expect(view(s, A, at(D0, "21:01"))).toMatchObject({ me: true, them: true, count: 1 });
  });

  it("keeps a waiting day at settlement when the cutoff passed with nobody calling", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), C);
    expect(view(s, A, at(D0, "09:30")).count).toBe(0);
    settle(s, D0);
    expect(s.days[D0]?.state).toBe("kept");
    expect(s.streak.count).toBe(1);
  });
});

describe("the 04:00 rollover", () => {
  it("puts turns at 03:59 and 04:01 on different days", () => {
    const s = pairOn();
    pass(s, at(D0, "09:00"), B);
    play(s, A, at(D1, "03:59"), B, "ROOM2");
    play(s, B, at(D1, "04:01"), A);
    expect(s.days[D0]?.turns).toEqual({ [A]: 1 });
    expect(s.days[D1]?.turns).toEqual({ [B]: 1 });
    expect(s.streak.count).toBe(0);
  });

  it("counts a turn at 1 a.m. for the night before", () => {
    const s = pairOn();
    play(s, A, at(D0, "22:00"), B);
    play(s, B, at(D1, "01:00"), A);
    expect(s.days[D0]?.state).toBe("kept");
  });
});

describe("time zones", () => {
  it("settles once both people's day has ended, plus ten minutes", () => {
    const s = pairOn(D0, [person(A, LA), person(B, NY)]);
    keepDay(s, D0);
    expect(s.streak.count).toBe(1);
    const due = at(D1, "04:10", LA);
    expect(nextSettleAt(s)).toBe(due);
    advance(s, due - 1);
    expect(s.lastSettled).toBeNull();
    advance(s, due);
    expect(s.lastSettled).toBe(D0);
  });

  it("puts each person's turn on the day in their own zone", () => {
    const s = pairOn(D0, [person(A, LA), person(B, NY)]);
    // 02:00 in LA is 05:00 in New York: A's last night, B's new day.
    play(s, A, at(D1, "02:00"), B);
    play(s, B, at(D1, "02:00"), A);
    expect(s.days[D0]?.turns).toEqual({ [A]: 1 });
    expect(s.days[D1]?.turns).toEqual({ [B]: 1 });
  });

  it("falls back to the partner's zone, then Los Angeles", () => {
    const s = pairOn(D0, [person(A, NY), person(B, null)]);
    play(s, B, at(D1, "02:00", LA), A);
    expect(s.days[D1]?.turns).toEqual({ [B]: 1 });
    const t = pairOn(D0, [person(A, null), person(B, null)]);
    play(t, B, at(D1, "02:00", LA), A);
    expect(t.days[D0]?.turns).toEqual({ [B]: 1 });
  });

  it("settles a DST day at 04:10 the next morning", () => {
    for (const [day, due] of [
      ["2026-03-07", Date.UTC(2026, 2, 8, 11, 10)],
      ["2026-03-08", Date.UTC(2026, 2, 9, 11, 10)],
      ["2026-10-31", Date.UTC(2026, 10, 1, 12, 10)],
      ["2026-11-01", Date.UTC(2026, 10, 2, 12, 10)],
    ] as const) {
      const s = pairOn(day);
      keepDay(s, day);
      expect(nextSettleAt(s)).toBe(due);
    }
  });

  it("doesn't reopen a settled day when someone flies west", () => {
    const s = pairOn();
    keepDay(s, D0);
    pass(s, at(D0, "11:00"), B);
    settle(s, D0);
    setPerson(s, person(B, "Pacific/Honolulu"), at(D1, "04:30"));
    // 05:00 in LA is 03:00 in Honolulu: still D0 there, which has settled.
    play(s, B, at(D1, "05:00"), A);
    expect(s.days[D0]?.turns[B]).toBe(1);
    expect(s.days[D0]?.state).toBe("kept");
  });

  it("takes a new zone from now on", () => {
    const s = pairOn();
    keepDay(s, D0);
    s.people[1].zone = NY;
    expect(nextSettleAt(s)).toBe(at(D1, "04:10", LA));
  });
});

describe("held days", () => {
  it("neither grows nor breaks the streak when a third person held the move all day", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    play(s, B, at(D0, "10:00"), C);
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("held");
    expect(s.streak.count).toBe(1);
    expect(s.streak.winback).toBeNull();
  });

  it("is a miss when no shared table was in play", () => {
    const s = pairOn();
    keepDay(s, D0);
    report(s, { code: "ROOM1", at: at(D0, "21:00"), by: null, holder: null, over: true }, at(D0, "21:00"));
    expect(s.moves).toEqual({});
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("winback");
  });

  it("is a miss when the table ended before the cutoff", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    play(s, B, at(D0, "10:00"), C);
    report(s, { code: "ROOM1", at: at(D1, "12:00"), by: null, holder: null, over: true }, at(D1, "12:00"));
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("winback");
  });

  it("can't happen on the pair's first day, which was only partly seen", () => {
    const s = pairOn();
    pass(s, at(D0, "08:30"), C);
    settle(s, D0);
    expect(s.days[D0]?.state).toBe("missed");
  });
});

describe("late and repeated reports", () => {
  it("leaves a settled day alone", () => {
    const s = pairOn();
    keepDay(s, D0);
    settle(s, D0);
    report(s, { code: "ROOM1", at: at(D0, "23:00"), by: A, holder: B, over: false }, at(D1, "05:00"));
    expect(s.days[D0]?.turns).toEqual({ [A]: 1, [B]: 1 });
  });

  it("draws one toy for a day however many turns keep it", () => {
    const s = pairOn();
    keepDay(s, D0);
    play(s, B, at(D0, "10:00"), A);
    play(s, A, at(D0, "11:00"), B);
    expect(s.streak.count).toBe(1);
    expect(view(s, A, at(D0, "11:00")).toys).toHaveLength(1);
  });

  it("ignores reports about people outside the pair", () => {
    const s = pairOn();
    play(s, C, at(D0, "09:00"), A);
    expect(s.days[D0]?.turns ?? {}).toEqual({});
    expect(s.moves.ROOM1?.holder).toBe(A);
    pass(s, at(D0, "09:30"), C);
    expect(s.moves.ROOM1?.holder).toBeNull();
  });

  it("keeps a day ahead of an unsettled miss only once the miss settles", () => {
    // D1 is missed (A held the move all day). B in New York and A keep D2 at
    // 04:05 LA, before D1 settles at 04:10 LA.
    const s = pairOn(D0, [person(A, LA), person(B, NY)]);
    keepDay(s, D0);
    play(s, B, at(D2, "04:00", LA), C);
    play(s, A, at(D2, "04:05", LA), C);
    expect(s.streak.count).toBe(1);
    advance(s, at(D2, "04:10", LA));
    expect(s.days[D1]?.state).toBe("winback");
    expect(s.streak.count).toBe(2);
    expect(s.streak.winback?.kept).toBe(1);
  });

  it("keeps a day ahead of an unsettled kept day at once", () => {
    const s = pairOn(D0, [person(A, LA), person(B, NY)]);
    keepDay(s, D0);
    pass(s, at(D0, "11:00"), C);
    play(s, B, at(D1, "04:00", LA), C);
    play(s, A, at(D1, "04:05", LA), C);
    expect(s.lastSettled).toBeNull();
    expect(s.streak.count).toBe(2);
  });
});
