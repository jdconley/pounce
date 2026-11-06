import { describe, expect, it } from "vitest";

import { at, D0, LA, NY } from "../../tests/streak-helpers";

import { addDays, type Day } from "./clock";
import { advancePersonal, mergePersonal, ownView, recordTurn, type Personal } from "./personal";

const day = (n: number): Day => addDays(D0, n);

/** One turn at 09:00 on each day from `from` for `n` days. */
function playDays(p: Personal | null, from: number, n: number, zone = LA): Personal {
  let s = p;
  for (let i = 0; i < n; i++) s = recordTurn(s, at(day(from + i), "09:00", zone), zone, at(day(from + i), "09:00", zone));
  return s as Personal;
}

const look = (p: Personal | null, d: Day, hhmm = "12:00", zone = LA) => ownView(p, zone, at(d, hhmm, zone));

describe("your own streak (D1, §6, §8)", () => {
  it("keeps today at the first turn, and a second turn changes nothing", () => {
    const s = recordTurn(null, at(D0, "09:00"), LA, at(D0, "09:00"));
    expect(look(s, D0)).toMatchObject({ count: 1, best: 1, kept: true, lifetimeKept: 1, naps: 0, winback: null });
    const again = recordTurn(s, at(D0, "21:00"), LA, at(D0, "21:00"));
    expect(look(again, D0)).toMatchObject({ count: 1, lifetimeKept: 1 });
  });

  it("is all zeros before any turn, with a plain week", () => {
    const v = look(null, D0);
    expect(v).toMatchObject({ count: 0, best: 0, kept: false, naps: 0, winback: null, lifetimeKept: 0, perfectWeeks: 0 });
    expect(v.week.map((w) => w.state)).toEqual(Array(7).fill("none"));
    expect(v.week.at(-1)?.day).toBe(D0);
  });

  it("counts a turn at 03:59 for the day before, and one at 04:01 for the new day", () => {
    const late = recordTurn(null, at(day(1), "03:59"), LA, at(day(1), "03:59"));
    expect(late.firstDay).toBe(D0);
    expect(look(late, D0, "23:00").count).toBe(1);
    const next = recordTurn(late, at(day(1), "04:01"), LA, at(day(1), "04:01"));
    expect(look(next, day(1), "05:00")).toMatchObject({ count: 2, kept: true });
  });

  it("uses the player's own zone for the day", () => {
    // 05:00 in New York is 02:00 in Los Angeles: a new day in New York, still the last one in Los Angeles.
    const s = recordTurn(null, at(day(1), "05:00", NY), NY, at(day(1), "05:00", NY));
    expect(s.firstDay).toBe(day(1));
  });

  it("counts up day after day, and best follows", () => {
    const s = playDays(null, 0, 5);
    expect(look(s, day(4))).toMatchObject({ count: 5, best: 5, lifetimeKept: 5 });
    expect(look(s, day(4)).week.map((w) => w.state)).toEqual(["none", "none", "kept", "kept", "kept", "kept", "kept"]);
  });

  it("shows yesterday's count during today until a turn, with today live", () => {
    const s = playDays(null, 0, 2);
    const v = look(s, day(2), "09:00");
    expect(v).toMatchObject({ count: 2, kept: false });
    expect(v.week.at(-1)?.state).toBe("live");
  });

  it("earns a nap at the 7th day and another for a perfect week, at most two", () => {
    const s = playDays(null, 0, 7);
    // Day 7 is both the 7th day and the first perfect week.
    expect(look(s, day(6)).naps).toBe(2);
    expect(look(s, day(6)).perfectWeeks).toBe(1);
    const more = playDays(s, 7, 7);
    expect(look(more, day(13))).toMatchObject({ naps: 2, perfectWeeks: 2, count: 14 });
  });

  it("a nap covers a missed day: the count holds and the run goes on", () => {
    const s = playDays(null, 0, 7);
    const v = look(s, day(8), "09:00");
    expect(v).toMatchObject({ count: 7, naps: 1, winback: null });
    expect(v.week.at(-2)?.state).toBe("nap");
    const back = playDays(s, 8, 1);
    expect(look(back, day(8))).toMatchObject({ count: 8, kept: true });
  });

  it("with no nap left, a miss starts win-back; two kept days bring it back and the miss shows as a nap", () => {
    const s = playDays(null, 0, 3);
    const v = look(s, day(4), "09:00");
    expect(v).toMatchObject({ count: 3, winback: { kept: 0 } });
    expect(v.week.at(-2)?.state).toBe("missed");
    const one = playDays(s, 4, 1);
    expect(look(one, day(4))).toMatchObject({ count: 4, winback: { kept: 1 } });
    const two = playDays(one, 5, 1);
    const won = look(two, day(5));
    expect(won).toMatchObject({ count: 5, winback: null });
    expect(won.week.map((w) => w.state).slice(-3)).toEqual(["nap", "kept", "kept"]);
  });

  it("a miss during win-back ends the streak at 0; best and total days stay (the fresh start)", () => {
    const s = playDays(null, 0, 3);
    const ended = look(s, day(5), "09:00");
    expect(ended).toMatchObject({ count: 0, best: 3, lifetimeKept: 3, winback: null });
    const fresh = playDays(s, 5, 1);
    expect(look(fresh, day(5))).toMatchObject({ count: 1, best: 3, lifetimeKept: 4 });
  });

  it("settles a long absence down to 0 and keeps no old days", () => {
    const s = playDays(null, 0, 10);
    const v = look(s, day(60));
    expect(v).toMatchObject({ count: 0, best: 10, lifetimeKept: 10, naps: 0 });
    expect(Object.keys(s.days).every((d) => d >= day(52))).toBe(true);
    expect(v.week.map((w) => w.state)).toEqual(["missed", "missed", "missed", "missed", "missed", "missed", "live"]);
  });

  it("waits ten minutes past the day's end before settling, so a late report still counts", () => {
    const s = playDays(null, 0, 1);
    // A 03:59 turn reported at 04:05: yesterday hasn't settled yet.
    const late = recordTurn(s, at(day(2), "03:59"), LA, at(day(2), "04:05"));
    expect(look(late, day(2), "04:06")).toMatchObject({ count: 2 });
    // A turn so late its day has settled is ignored, as is one before the record began.
    const settled = recordTurn(late, at(day(2), "03:00"), LA, at(day(3), "12:00"));
    expect(look(settled, day(3)).count).toBe(2);
    const before = recordTurn(late, at(addDays(D0, -3), "09:00"), LA, at(day(2), "09:00"));
    expect(before.firstDay).toBe(D0);
  });

  it("applies a new day only once the day before has settled", () => {
    const s = playDays(null, 0, 2);
    // Day 2 has no turn; a turn on day 3 at 04:05 waits for day 2's settlement at 04:10.
    const early = recordTurn(s, at(day(3), "04:05"), LA, at(day(3), "04:05"));
    expect(look(early, day(3), "04:06").kept).toBe(false);
    expect(look(early, day(3), "04:30")).toMatchObject({ count: 3, kept: true, winback: { kept: 1 } });
  });

  it("counts a waiting turn when its day settles, even if nobody looked in between", () => {
    const s = playDays(null, 0, 2);
    const early = recordTurn(s, at(day(3), "04:05"), LA, at(day(3), "04:05"));
    expect(look(early, day(4), "09:00")).toMatchObject({ count: 3, winback: { kept: 1 } });
  });

  it("advancePersonal leaves no record alone", () => {
    expect(() => advancePersonal(null, LA, at(D0, "09:00"))).not.toThrow();
  });
});

describe("mergePersonal (§13.1)", () => {
  it("keeps the longer current streak whole and the larger lifetime numbers", () => {
    const long = playDays(null, 0, 9);
    const short = playDays(null, 6, 3);
    short.best = 20;
    short.perfectWeeks = 3;
    short.lifetimeKept = 40;
    const merged = mergePersonal(short, long) as Personal;
    expect(look(merged, day(8))).toMatchObject({ count: 9, best: 20, lifetimeKept: 40, perfectWeeks: 3, naps: 2 });
    expect(mergePersonal(long, short)?.count).toBe(9);
  });

  it("takes whichever exists, and nothing from nothing", () => {
    const s = playDays(null, 0, 2);
    expect(mergePersonal(null, s)).toEqual(s);
    expect(mergePersonal(s, null)).toEqual(s);
    expect(mergePersonal(null, null)).toBeNull();
  });
});
