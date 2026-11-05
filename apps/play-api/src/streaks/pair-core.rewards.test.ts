import { describe, expect, it } from "vitest";

import { A, at, B, C, D0, keepDay, keepDays, LA, NY, pairOn, pass, person, play, settle } from "../../tests/streak-helpers";

import { DEFAULT_BACK, DEFAULT_RUG, FULL_SET_BACK, TOYS } from "./catalog";
import { addDays } from "./clock";
import { mergeStates, openGift, repoint, setPerson, unlockedFor, view } from "./pair-core";

const day = (n: number) => addDays(D0, n);
const P = "p_pppppppppppppppppppppp";

describe("milestones and gifts", () => {
  it("hand both people the same gift at 3 days; each opens their own", () => {
    const s = pairOn();
    keepDays(s, D0, 3);
    const now = at(day(2), "11:00");
    const gift = view(s, A, now).gifts[0];
    expect(gift).toMatchObject({ milestone: 3 });
    expect(view(s, B, now).gifts).toEqual([gift]);
    expect(openGift(s, A, gift?.id as string)).toBe(true);
    expect(openGift(s, A, gift?.id as string)).toBe(true);
    expect(view(s, A, now).gifts).toEqual([]);
    expect(view(s, B, now).gifts).toHaveLength(1);
    expect(openGift(s, A, "nope")).toBe(false);
    expect(openGift(s, C, gift?.id as string)).toBe(false);
  });

  it("give again each time a milestone is reached", () => {
    const s = pairOn();
    keepDays(s, D0, 3);
    s.streak.count = 0;
    keepDays(s, day(3), 3);
    expect(s.gifts.map((g) => g.milestone)).toEqual([3, 3]);
    expect(new Set(s.gifts.map((g) => g.id)).size).toBe(2);
  });

  it("unlock a card back or rug for a person only once they open it", () => {
    const s = pairOn();
    s.owned.push("rug-night-sky", "back-crown");
    s.gifts.push({ id: "g9", milestone: 7, item: "rug-night-sky", openedBy: [] });
    expect(unlockedFor(s, B)).toEqual({ backs: [DEFAULT_BACK, "back-crown"], rugs: [DEFAULT_RUG] });
    openGift(s, B, "g9");
    expect(unlockedFor(s, B).rugs).toEqual([DEFAULT_RUG, "rug-night-sky"]);
    expect(unlockedFor(s, C)).toEqual({ backs: [DEFAULT_BACK], rugs: [DEFAULT_RUG] });
  });

  it("show the next milestone and the condo stage", () => {
    const s = pairOn();
    keepDays(s, D0, 7);
    expect(view(s, A, at(day(6), "11:00"))).toMatchObject({ count: 7, next: 14, condoStage: 3, lifetimeKept: 7, best: 7 });
  });
});

describe("toys", () => {
  it("drop one per kept day and finish the set with the golden yarn back", () => {
    const s = pairOn();
    keepDays(s, D0, 30);
    const v = view(s, A, at(day(29), "11:00"));
    expect(new Set(v.toys).size).toBe(TOYS.length);
    expect(v.unlocked.backs).toContain(FULL_SET_BACK);
    expect(unlockedFor(s, B).backs).toContain(FULL_SET_BACK);
  });

  it("are the same for the same seed", () => {
    const a = pairOn();
    const b = pairOn();
    keepDays(a, D0, 10);
    keepDays(b, D0, 10);
    expect(a.owned).toEqual(b.owned);
    expect(a.gifts).toEqual(b.gifts);
  });
});

describe("the view", () => {
  it("shows a week of plain day outcomes and names nobody", () => {
    const s = pairOn();
    keepDays(s, D0, 2);
    pass(s, at(day(1), "11:00"), C);
    settle(s, day(2));
    const v = view(s, B, at(day(3), "09:00"));
    expect(v.week.map((d) => d.state)).toEqual(["none", "none", "none", "kept", "kept", "held", "live"]);
    expect(v.week.at(-1)?.day).toBe(day(3));
    expect(JSON.stringify(v)).not.toContain(A);
    expect(JSON.stringify(v)).not.toContain(B);
    expect(v.partner).toEqual({ name: "JD", cat: 1 });
    expect(v.pounce).toEqual({ sent: false, resting: false });
  });

  it("shows an unsettled past day as live", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    expect(view(s, A, at(day(1), "04:05")).week.slice(-2)).toEqual([
      { day: D0, state: "live" },
      { day: day(1), state: "live" },
    ]);
  });

  it("lists whose move it is at each shared table", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B, "ROOM1");
    play(s, B, at(D0, "09:30"), A, "ROOM2");
    play(s, A, at(D0, "09:40"), C, "ROOM3");
    expect(view(s, A, at(D0, "10:00"))).toMatchObject({ myMove: ["ROOM2"], theirMove: ["ROOM1"] });
    expect(view(s, B, at(D0, "10:00"))).toMatchObject({ myMove: ["ROOM1"], theirMove: ["ROOM2"] });
  });

  it("follows a person's new name, cat, zone and quiet hours", () => {
    const s = pairOn();
    setPerson(s, { ...person(B, NY), name: "Mimi", cat: 5 }, at(D0, "09:00"));
    expect(view(s, A, at(D0, "09:00")).partner).toEqual({ name: "Mimi", cat: 5 });
    expect(s.people[1].zone).toBe(NY);
    setPerson(s, person(C), at(D0, "09:00"));
    expect(s.people.map((p) => p.id)).toEqual([A, B]);
  });
});

describe("merging and re-pointing", () => {
  it("re-points every trace of a merged player", () => {
    const s = pairOn();
    keepDays(s, D0, 3);
    openGift(s, B, s.gifts[0]?.id as string);
    openGift(s, A, s.gifts[0]?.id as string);
    s.streak.pausedBy = B;
    repoint(s, B, P);
    expect(s.people.map((p) => p.id)).toEqual([A, P]);
    expect(s.days[D0]?.turns).toEqual({ [A]: 1, [P]: 1 });
    expect(s.moves.ROOM1?.holder).toBe(A);
    expect(s.gifts[0]?.openedBy).toEqual([P, A]);
    expect(s.streak.pausedBy).toBe(P);
    repoint(s, C, P);
    expect(s.people.map((p) => p.id)).toEqual([A, P]);
  });

  it("re-sorts the people when the new id sorts first", () => {
    const s = pairOn();
    play(s, B, at(D0, "09:00"), B);
    repoint(s, B, "p_0000000000000000000000");
    expect(s.people.map((p) => p.id)).toEqual(["p_0000000000000000000000", A]);
    expect(s.moves.ROOM1?.holder).toBe("p_0000000000000000000000");
  });

  it("never makes a pair of one player", () => {
    expect(() => repoint(pairOn(), B, A)).toThrow();
  });

  it("merges two streaks with the same partner: the longer streak wins, the rest is pooled", () => {
    const long = pairOn();
    keepDays(long, D0, 7);
    long.streak.naps = 1;
    const short = pairOn();
    keepDays(short, D0, 3);
    short.streak.lifetimeKept = 40;
    short.streak.best = 20;
    short.streak.naps = 2;
    short.owned.push("rug-fish-pond");
    play(short, A, at(day(2), "12:00"), B, "ROOM9");
    const merged = mergeStates(long, short);
    expect(merged.id).toBe(long.id);
    expect(merged.streak).toMatchObject({ count: 7, best: 20, lifetimeKept: 40, naps: 2, perfectWeeks: 1 });
    expect(merged.owned).toContain("rug-fish-pond");
    expect(new Set(merged.owned).size).toBe(merged.owned.length);
    expect(merged.moves.ROOM9?.holder).toBe(B);
    expect(merged.gifts.map((g) => g.milestone).sort((x, y) => x - y)).toEqual([3, 3, 7]);
    expect(new Set(merged.gifts.map((g) => g.id)).size).toBe(3);

    const flipped = mergeStates(short, long);
    expect(flipped.id).toBe(short.id);
    expect(flipped.streak.count).toBe(7);
  });

  it("drops gifts both people already opened", () => {
    const a = pairOn();
    const b = pairOn();
    keepDays(b, D0, 3);
    for (const who of [A, B]) openGift(b, who, b.gifts[0]?.id as string);
    expect(mergeStates(a, b).gifts).toEqual([]);
  });

  it("keeps the later last turn", () => {
    const a = pairOn();
    const b = pairOn(D0, [person(A, LA), person(B, LA)]);
    keepDay(b, day(4));
    expect(mergeStates(a, b).lastTurnAt).toBe(b.lastTurnAt);
  });
});
