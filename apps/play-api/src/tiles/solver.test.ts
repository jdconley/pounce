import { describe, expect, test } from "vitest";

import { bell, feather, fish, mouse, YARN, YARN2 } from "../../tests/tiles-helpers";

import { readSet } from "./sets";
import { addYarnSets, borrowFromTable, findSets, placeOnTable, pointsOf } from "./solver";

const sorted = (ids: number[]) => [...ids].sort((a, b) => a - b);

describe("pointsOf", () => {
  test("adds up what each set is worth, a Yarn as the piece it stands for", () => {
    expect(pointsOf([])).toBe(0);
    expect(pointsOf([[fish(9), fish(10), fish(11)]])).toBe(30);
    expect(pointsOf([[fish(9), YARN, fish(11)], [mouse(2), feather(2), bell(2)]])).toBe(36);
  });

  test("a set that is not one is worth nothing", () => {
    expect(pointsOf([[fish(9), fish(10)], [fish(1), fish(2), fish(3)]])).toBe(6);
  });
});

describe("findSets", () => {
  test("finds a run and leaves the rest", () => {
    const rack = [fish(7), bell(2), fish(5), fish(6), mouse(11)];
    expect(findSets(rack, "runs")).toEqual({ sets: [[fish(5), fish(6), fish(7)]], rest: [bell(2), mouse(11)] });
  });

  test("takes a run as long as it goes, up to 13", () => {
    const rack = [fish(13), fish(12), fish(11), fish(10), fish(8)];
    expect(findSets(rack, "runs")).toEqual({ sets: [[fish(10), fish(11), fish(12), fish(13)]], rest: [fish(8)] });
  });

  test("finds a group of three and a group of four", () => {
    const rack = [fish(4), mouse(4), bell(4), fish(8), mouse(8), feather(8), bell(8)];
    const found = findSets(rack, "groups");
    expect(found.sets).toEqual([[fish(4), mouse(4), bell(4)], [fish(8), mouse(8), feather(8), bell(8)]]);
    expect(found.rest).toEqual([]);
  });

  test("two of one suit do not make a group", () => {
    const rack = [fish(4), fish(4, true), mouse(4)];
    expect(findSets(rack, "groups")).toEqual({ sets: [], rest: rack });
  });

  test("the twins make a second run and a second group", () => {
    const runs = [fish(3), fish(4), fish(5), fish(3, true), fish(4, true), fish(5, true)];
    expect(findSets(runs, "runs").sets).toEqual([[fish(3), fish(4), fish(5)], [fish(3, true), fish(4, true), fish(5, true)]]);
    const groups = [fish(9), mouse(9), bell(9), fish(9, true), mouse(9, true), feather(9)];
    // Not a group of four, which would strand the two twins.
    expect(findSets(groups, "groups")).toEqual({
      sets: [[fish(9), mouse(9), feather(9)], [fish(9, true), mouse(9, true), bell(9)]],
      rest: [],
    });
  });

  test("three suits held twice and one once: a group of four and a group of three", () => {
    const rack = [fish(9), mouse(9), bell(9), fish(9, true), mouse(9, true), bell(9, true), feather(9)];
    const { sets, rest } = findSets(rack, "groups");
    expect(sets.map((set) => set.length)).toEqual([4, 3]);
    expect(rest).toEqual([]);
  });

  test("the order decides who gets a piece that fits both", () => {
    // The fish 5 can finish the run 3-4-5 or the group of 5s, not both.
    const rack = [fish(3), fish(4), fish(5), mouse(5), bell(5)];
    expect(findSets(rack, "runs")).toEqual({ sets: [[fish(3), fish(4), fish(5)]], rest: [mouse(5), bell(5)] });
    expect(findSets(rack, "groups")).toEqual({ sets: [[fish(5), mouse(5), bell(5)]], rest: [fish(3), fish(4)] });
  });

  test("uses both orders' leftovers: runs, then groups from what is left", () => {
    const rack = [fish(3), fish(4), fish(5), fish(5, true), mouse(5), bell(5)];
    expect(findSets(rack, "runs").sets).toEqual([[fish(3), fish(4), fish(5)], [fish(5, true), mouse(5), bell(5)]]);
  });

  test("never uses a Yarn: it stays in the rest", () => {
    const rack = [YARN, fish(5), fish(6), fish(7), YARN2];
    expect(findSets(rack, "runs")).toEqual({ sets: [[fish(5), fish(6), fish(7)]], rest: [YARN, YARN2] });
  });

  test("every set it returns is a set, and no piece is used twice or lost", () => {
    const rack = [
      fish(1), fish(2), fish(3), fish(4), fish(4, true), mouse(4), bell(4), feather(4), feather(5), feather(6),
      feather(7), bell(12), bell(13), mouse(12), fish(12), YARN,
    ];
    for (const first of ["runs", "groups"] as const) {
      const { sets, rest } = findSets(rack, first);
      for (const set of sets) expect(readSet(set), JSON.stringify(set)).not.toBeNull();
      expect(sorted([...sets.flat(), ...rest])).toEqual(sorted(rack));
      expect(sets.length).toBeGreaterThanOrEqual(3);
    }
  });

  test("an empty rack has no sets", () => {
    expect(findSets([], "runs")).toEqual({ sets: [], rest: [] });
  });
});

describe("addYarnSets", () => {
  test("a Yarn finishes two of a number", () => {
    const found = addYarnSets({ sets: [], rest: [mouse(9), YARN, bell(9), fish(2)] });
    expect(found.rest).toEqual([fish(2)]);
    expect(found.sets).toHaveLength(1);
    expect(readSet(found.sets[0] as number[])).toEqual({ kind: "group", value: 9, points: 27 });
  });

  test("a Yarn goes after two in a row, where it is worth the most", () => {
    const found = addYarnSets({ sets: [], rest: [fish(5), fish(6), YARN] });
    expect(found.sets).toEqual([[fish(5), fish(6), YARN]]);
  });

  test("before them when they end on 13", () => {
    const found = addYarnSets({ sets: [], rest: [fish(13), fish(12), YARN] });
    expect(found.sets).toEqual([[YARN, fish(12), fish(13)]]);
  });

  test("between two that are one apart", () => {
    const found = addYarnSets({ sets: [], rest: [fish(7), fish(5), YARN] });
    expect(found.sets).toEqual([[fish(5), YARN, fish(7)]]);
  });

  test("spends it on the pair worth the most", () => {
    const found = addYarnSets({ sets: [], rest: [fish(2), fish(3), mouse(11), bell(11), YARN] });
    expect(found.rest).toEqual([fish(2), fish(3)]);
    expect(pointsOf(found.sets)).toBe(33);
  });

  test("two Yarn finish two pairs", () => {
    const found = addYarnSets({ sets: [[1, 2, 3]], rest: [fish(5), fish(6), YARN, mouse(11), bell(11), YARN2] });
    expect(found.sets).toHaveLength(3);
    expect(found.sets[0]).toEqual([1, 2, 3]);
    expect(found.rest).toEqual([]);
  });

  test("keeps the Yarn when no pair wants it, and when there is none", () => {
    const lonely = { sets: [], rest: [fish(5), fish(9), mouse(2), YARN] };
    expect(addYarnSets(lonely)).toEqual(lonely);
    const none = { sets: [[1, 2, 3]], rest: [fish(5), fish(6)] };
    expect(addYarnSets(none)).toEqual(none);
  });

  test("never puts two Yarn in one set", () => {
    const found = addYarnSets({ sets: [], rest: [fish(13), YARN, YARN2] });
    expect(found.sets).toEqual([]);
  });
});

describe("placeOnTable", () => {
  const run = [mouse(5), mouse(6), mouse(7)];
  const nines = [fish(9), mouse(9), bell(9)];

  test("a piece goes on the high end of a run, or the low end", () => {
    expect(placeOnTable([run], [mouse(8)])).toEqual({ table: [[...run, mouse(8)]], rest: [] });
    expect(placeOnTable([run], [mouse(4)])).toEqual({ table: [[mouse(4), ...run]], rest: [] });
  });

  test("a piece makes a group's fourth", () => {
    expect(placeOnTable([run, nines], [feather(9)])).toEqual({ table: [run, [...nines, feather(9)]], rest: [] });
  });

  test("a piece with no home is handed back", () => {
    expect(placeOnTable([run, nines], [mouse(10), fish(9, true), bell(2)])).toEqual({
      table: [run, nines],
      rest: [mouse(10), fish(9, true), bell(2)],
    });
  });

  test("one piece makes room for the next, whatever order they come in", () => {
    const placed = placeOnTable([run], [mouse(10), mouse(9), mouse(8)]);
    expect(placed).toEqual({ table: [[...run, mouse(8), mouse(9), mouse(10)]], rest: [] });
  });

  test("a long run splits in two around the twin of one of its pieces", () => {
    const long = [fish(3), fish(4), fish(5), fish(6), fish(7)];
    expect(placeOnTable([nines, long], [fish(5, true)])).toEqual({
      table: [nines, [fish(3), fish(4), fish(5)], [fish(5, true), fish(6), fish(7)]],
      rest: [],
    });
  });

  test("a run too short to leave two sets does not split", () => {
    const four = [fish(3), fish(4), fish(5), fish(6)];
    expect(placeOnTable([four], [fish(4, true)])).toEqual({ table: [four], rest: [fish(4, true)] });
  });

  test("a piece takes the place of a Yarn, which moves to another set", () => {
    const withYarn = [mouse(5), YARN, mouse(7)];
    const low = [bell(1), bell(2), bell(3)];
    expect(placeOnTable([withYarn, low], [mouse(6)])).toEqual({
      table: [[mouse(5), mouse(6), mouse(7)], [...low, YARN]],
      rest: [],
    });
    expect(placeOnTable([low, withYarn], [mouse(6)])).toEqual({
      table: [[...low, YARN], [mouse(5), mouse(6), mouse(7)]],
      rest: [],
    });
  });

  test("a Yarn with nowhere else to go stays where it is", () => {
    const withYarn = [mouse(5), YARN, mouse(7)];
    expect(placeOnTable([withYarn], [mouse(6)])).toEqual({ table: [withYarn], rest: [mouse(6)] });
    const full = [fish(9), mouse(9), feather(9), bell(9)];
    expect(placeOnTable([withYarn, full], [mouse(6)])).toEqual({ table: [withYarn, full], rest: [mouse(6)] });
  });

  test("a Yarn from the rack goes on the end of a set", () => {
    expect(placeOnTable([run], [YARN])).toEqual({ table: [[...run, YARN]], rest: [] });
    const top = [fish(11), fish(12), fish(13)];
    expect(placeOnTable([top], [YARN])).toEqual({ table: [[YARN, ...top]], rest: [] });
  });

  test("does not change the table it is given", () => {
    const table = [[...run]];
    placeOnTable(table, [mouse(8)]);
    expect(table).toEqual([run]);
  });

  test("an empty table takes nothing", () => {
    expect(placeOnTable([], [mouse(8)])).toEqual({ table: [], rest: [mouse(8)] });
  });
});

describe("borrowFromTable", () => {
  test("the end of a run of four finishes a pair on the rack", () => {
    const run = [fish(4), fish(5), fish(6), fish(7)];
    const out = borrowFromTable([run], [mouse(7), bell(7), bell(2)]);
    expect(out.table[0]).toEqual([fish(4), fish(5), fish(6)]);
    expect(readSet(out.table[1] as number[])).toEqual({ kind: "group", value: 7, points: 21 });
    expect(out.rest).toEqual([bell(2)]);
  });

  test("a group of four gives up a piece to a run", () => {
    const fours = [fish(4), mouse(4), feather(4), bell(4)];
    const out = borrowFromTable([fours], [mouse(5), mouse(6)]);
    expect(out.table).toEqual([[fish(4), feather(4), bell(4)], [mouse(4), mouse(5), mouse(6)]]);
    expect(out.rest).toEqual([]);
  });

  test("the borrowed piece can sit below, between or above the pair", () => {
    const fours = [fish(4), mouse(4), feather(4), bell(4)];
    expect(borrowFromTable([fours], [mouse(2), mouse(3)]).table[1]).toEqual([mouse(2), mouse(3), mouse(4)]);
    expect(borrowFromTable([fours], [mouse(3), mouse(5)]).table[1]).toEqual([mouse(3), mouse(4), mouse(5)]);
  });

  test("a set of three has nothing to spare, and nor has the middle of a run", () => {
    const three = [fish(4), fish(5), fish(6)];
    const five = [mouse(1), mouse(2), mouse(3), mouse(4), mouse(5)];
    const rack = [mouse(6, true), bell(6), feather(3), bell(3)];
    expect(borrowFromTable([three, five], rack)).toEqual({ table: [three, five], rest: rack });
  });

  test("a spare Yarn on the table finishes a pair too, and stays on the table", () => {
    const run = [fish(4), fish(5), fish(6), YARN];
    const out = borrowFromTable([run], [bell(11), mouse(11)]);
    expect(out.table[0]).toEqual([fish(4), fish(5), fish(6)]);
    expect(out.table[1]).toContain(YARN);
    expect(readSet(out.table[1] as number[])).toEqual({ kind: "group", value: 11, points: 33 });
    expect(out.rest).toEqual([]);
  });

  test("a Yarn on the rack is never spent on a borrowed piece", () => {
    const run = [fish(4), fish(5), fish(6), fish(7)];
    expect(borrowFromTable([run], [mouse(7), YARN])).toEqual({ table: [run], rest: [mouse(7), YARN] });
  });

  test("keeps borrowing while it helps", () => {
    const long = [fish(4), fish(5), fish(6), fish(7), fish(8)];
    const out = borrowFromTable([long], [mouse(8), bell(8), mouse(4), bell(4)]);
    expect(out.rest).toEqual([]);
    expect(out.table).toHaveLength(3);
    for (const set of out.table) expect(readSet(set)).not.toBeNull();
  });

  test("does not change the table it is given", () => {
    const table = [[fish(4), fish(5), fish(6), fish(7)]];
    borrowFromTable(table, [mouse(7), bell(7)]);
    expect(table).toEqual([[fish(4), fish(5), fish(6), fish(7)]]);
  });
});
