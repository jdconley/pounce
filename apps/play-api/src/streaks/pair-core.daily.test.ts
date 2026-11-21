import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDay, keepDays, LA, missDay, NY, pairOn, pass, person, play, settle } from "../../tests/streak-helpers";

import { addDays } from "./clock";
import { advance, facts, pause, repoint, reportDaily, view, type DayState, type PairState } from "./pair-core";

/**
 * A daily run counts as playing today (daily games design §5, "The rule, exactly"): a day with a
 * table turn follows the old rules, a daily run counting as that person's turn; a day whose only
 * plays are daily runs is kept only when both people ended one.
 */
const D1 = addDays(D0, 1);
const D7 = addDays(D0, 7);

describe("a day with only daily runs", () => {
  it("both play only daily runs: kept", () => {
    const s = pairOn();
    reportDaily(s, A, at(D1, "09:00"), at(D1, "09:00"));
    expect(view(s, A, at(D1, "09:01"))).toMatchObject({ me: true, them: false, count: 0 });
    reportDaily(s, B, at(D1, "21:00"), at(D1, "21:00"));
    expect(view(s, A, at(D1, "21:01"))).toMatchObject({ me: true, them: true, count: 1 });
    expect(s.days[D1]?.daily).toEqual({ [A]: 1, [B]: 1 });
    expect(s.days[D1]?.turns).toEqual({ [A]: 1, [B]: 1 });
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("kept");
  });

  it("one plays a daily run, the other nothing: missed (nap used)", () => {
    const s = pairOn();
    keepDays(s, D0, 7);
    settle(s, addDays(D0, 6));
    const naps = s.streak.naps;
    expect(naps).toBeGreaterThan(0);
    // The late move pass doesn't apply: B never held a move, and still the day isn't kept.
    reportDaily(s, A, at(D7, "09:00"), at(D7, "09:00"));
    settle(s, D7);
    expect(s.days[D7]?.state).toBe("nap");
    expect(s.streak).toMatchObject({ count: 7, naps: naps - 1 });
  });

  it("A holds the move all day and plays Sniff, B nothing: not kept", () => {
    const s = pairOn();
    keepDay(s, D0);
    settle(s, D0);
    missDay(s, D1);
    reportDaily(s, A, at(D1, "12:00"), at(D1, "12:00"));
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("winback");
    expect(s.streak.count).toBe(1);
  });

  it("each person's run counts on their own day", () => {
    const s = pairOn(D0, [person(A, LA), person(B, NY)]);
    // 02:00 in New York the next morning is still D1's night there.
    reportDaily(s, B, at(addDays(D1, 1), "02:00", NY), at(addDays(D1, 1), "02:00", NY));
    reportDaily(s, A, at(D1, "20:00"), at(D1, "20:00"));
    expect(s.days[D1]?.daily).toEqual({ [A]: 1, [B]: 1 });
  });
});

describe("mixing a table turn and a daily run", () => {
  it("a table turn by Mom, JD never held the move, JD plays Sniff: kept", () => {
    const s = pairOn();
    // A (Mom) plays at a table with C; the move never reaches B (JD).
    play(s, A, at(D1, "09:00"), C);
    reportDaily(s, B, at(D1, "10:00"), at(D1, "10:00"));
    expect(view(s, B, at(D1, "10:01"))).toMatchObject({ me: true, them: true, count: 1 });
    settle(s, D1);
    expect(s.days[D1]?.state).toBe("kept");
  });

  it("a table turn by Mom and JD's Sniff count on a day JD held the move", () => {
    const s = pairOn();
    play(s, A, at(D1, "09:00"), B);
    reportDaily(s, B, at(D1, "12:00"), at(D1, "12:00"));
    expect(view(s, A, at(D1, "12:01"))).toMatchObject({ me: true, them: true, count: 1 });
  });
});

describe("a day with only table play is exactly as before", () => {
  /** One scenario per day state, with table play only. */
  const scenarios: [DayState, (s: PairState) => void, string][] = [
    ["kept", (s) => keepDay(s, D1), D1],
    ["missed", (s) => play(s, A, at(D1, "09:00"), B), D1],
    ["held", (s) => pass(s, at(D0, "09:00"), C), D1],
    [
      "nap",
      (s) => {
        keepDays(s, D0, 7);
        missDay(s, D7);
      },
      D7,
    ],
    [
      "winback",
      (s) => {
        keepDay(s, D0);
        missDay(s, D1);
      },
      D1,
    ],
    [
      "paused",
      (s) => {
        keepDay(s, D0);
        pause(s, A, 1, at(D0, "12:00"));
        missDay(s, D1);
      },
      D1,
    ],
  ];

  for (const [state, run, day] of scenarios) {
    it(`a table turn by Mom, no daily runs: identical to before (${state})`, () => {
      const s = pairOn();
      run(s);
      settle(s, day);
      expect(s.days[day]?.state).toBe(state);
      expect(s.days[day]?.daily).toBeUndefined();
    });
  }

  it("a live day stays live, as before", () => {
    const s = pairOn();
    play(s, A, at(D1, "09:00"), B);
    advance(s, at(D1, "09:30"));
    expect(s.days[D1]?.state).toBe("live");
  });

  it("a saved day with no daily field reads as no daily runs", () => {
    const s = pairOn();
    play(s, A, at(D1, "09:00"), C);
    play(s, B, at(D1, "10:00"), C);
    expect(s.days[D1]).not.toHaveProperty("daily");
    expect(view(s, A, at(D1, "10:01")).count).toBe(1);
  });
});

describe("reportDaily's limits", () => {
  it("a daily run reported after settlement is ignored", () => {
    const s = pairOn();
    reportDaily(s, A, at(D1, "09:00"), at(D1, "09:00"));
    settle(s, D1);
    reportDaily(s, B, at(D1, "21:00"), at(addDays(D1, 1), "05:00"));
    expect(s.days[D1]?.daily).toEqual({ [A]: 1 });
    expect(s.days[D1]?.state).toBe("missed");
  });

  it("ignores someone outside the pair, and a run before the pair's first day", () => {
    const s = pairOn(D1);
    reportDaily(s, C, at(D1, "09:00"), at(D1, "09:00"));
    reportDaily(s, A, at(D0, "09:00"), at(D1, "09:00"));
    expect(s.days[D1]?.daily ?? {}).toEqual({});
    expect(s.days[D0]).toBeUndefined();
  });

  it("moves the pair's latest turn", () => {
    const s = pairOn();
    reportDaily(s, A, at(D1, "09:00"), at(D1, "09:00"));
    expect(s.lastTurnAt).toBe(at(D1, "09:00"));
  });
});

describe("what a day with only daily runs shows", () => {
  it("after the cutoff, the one who played no daily run isn't lit: the late move pass doesn't apply", () => {
    const s = pairOn();
    reportDaily(s, A, at(D1, "09:00"), at(D1, "09:00"));
    // 21:00 is past B's 20:00 cutoff, and B never held the move.
    expect(view(s, B, at(D1, "21:00"))).toMatchObject({ me: false, them: true, kept: false });
    expect(view(s, A, at(D1, "21:00"))).toMatchObject({ me: true, them: false });
    expect(facts(s, B, at(D1, "21:00")).in).toBe(false);
    expect(facts(s, A, at(D1, "21:00")).in).toBe(true);
  });

  it("a day nobody played reads as before", () => {
    const s = pairOn();
    advance(s, at(D1, "21:00"));
    expect(facts(s, B, at(D1, "21:00")).in).toBe(true);
    expect(view(s, B, at(D1, "21:00"))).toMatchObject({ me: false, them: false });
  });
});

describe("a merge", () => {
  it("repoint moves a person's daily runs to their account", () => {
    const s = pairOn();
    reportDaily(s, A, at(D1, "09:00"), at(D1, "09:00"));
    const to = "p_zzzzzzzzzzzzzzzzzzzzzz";
    repoint(s, A, to);
    expect(s.days[D1]?.daily).toEqual({ [to]: 1 });
    reportDaily(s, B, at(D1, "10:00"), at(D1, "10:00"));
    expect(s.days[D1]?.applied).toBe(true);
  });
});
