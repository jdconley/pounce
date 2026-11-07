import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { buildGroup, canHit, type Group, type Requirement } from "./groups";

/*
 * Card id cheat sheet (see cards.ts): coat = floor(id / 24) in the order
 * tabby, tuxedo, calico, gray; value = (id % 12) + 1. Each value appears twice
 * per coat, so tabby value v is id v-1 (or v+11 for the second copy):
 *   tabby 3 = id 2 (second copy 14), tabby 7 = id 6, tabby 12 = id 11
 *   tuxedo v = 23 + v (tuxedo 7 = id 30), calico v = 47 + v, gray v = 71 + v
 *   96-103 = Yarn, 104-107 = Cucumber
 */
const YARN = [96, 97, 98, 99, 100, 101, 102, 103];
const CUCUMBER = 104;
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;

const SET3: Requirement = { kind: "set", size: 3 };
const RUN3: Requirement = { kind: "run", size: 3 };
const RUN4: Requirement = { kind: "run", size: 4 };
const COAT3: Requirement = { kind: "coat", size: 3 };
const COAT7: Requirement = { kind: "coat", size: 7 };

describe("buildGroup: sets", () => {
  test("set of 3 with one yarn is valid", () => {
    const g = buildGroup(SET3, [tabby(7), tuxedo(7), YARN[0]!]);
    expect(g).toEqual({ kind: "set", cards: [6, 30, 96], value: 7 });
  });
  test("set of 3 all yarn is invalid", () => {
    expect(buildGroup(SET3, [96, 97, 98])).toBeNull();
  });
  test("set with a cucumber is invalid", () => {
    expect(buildGroup(SET3, [tabby(7), tuxedo(7), CUCUMBER])).toBeNull();
  });
  test("set with mixed values is invalid", () => {
    expect(buildGroup(SET3, [tabby(7), tuxedo(8), YARN[0]!])).toBeNull();
  });
  test("wrong size is invalid", () => {
    expect(buildGroup(SET3, [tabby(7), tuxedo(7)])).toBeNull();
    expect(buildGroup(SET3, [tabby(7), tuxedo(7), calico(7), gray(7)])).toBeNull();
  });
  test("duplicate card ids and unknown ids are invalid", () => {
    expect(buildGroup(SET3, [6, 6, 96])).toBeNull();
    expect(buildGroup(SET3, [6, 30, 999])).toBeNull();
  });
  test("the same value in two copies of one coat is a valid set", () => {
    expect(buildGroup(SET3, [tabby(3), 14, calico(3)])).not.toBeNull();
  });
});

describe("buildGroup: runs", () => {
  test("run 3-4-5-6 valid", () => {
    expect(buildGroup(RUN4, [tabby(3), tuxedo(4), calico(5), gray(6)])).toEqual({
      kind: "run",
      cards: [2, 27, 52, 77],
      start: 3,
      end: 6,
    });
  });
  test("run is placed in ascending order regardless of input order", () => {
    const g = buildGroup(RUN4, [gray(6), tabby(3), calico(5), tuxedo(4)]);
    expect(g).toMatchObject({ cards: [2, 27, 52, 77], start: 3, end: 6 });
  });
  test("run 10-11-12 + yarn defaults to start 9", () => {
    expect(buildGroup(RUN4, [tabby(10), tabby(11), tabby(12), 96])).toEqual({
      kind: "run",
      cards: [96, 9, 10, 11],
      start: 9,
      end: 12,
    });
  });
  test("run 10-11-12 + yarn can start at 10 when asked", () => {
    expect(buildGroup(RUN4, [tabby(10), tabby(11), tabby(12), 96], 10)).toBeNull();
    expect(buildGroup(RUN4, [tabby(10), tabby(11), tabby(12), 96], 9)).not.toBeNull();
  });
  test("run 11-12-1 (wrap) invalid", () => {
    expect(buildGroup(RUN3, [tabby(11), tabby(12), tabby(1)])).toBeNull();
  });
  test("run with duplicate value invalid", () => {
    expect(buildGroup(RUN4, [tabby(3), 14, tuxedo(4), 96])).toBeNull();
  });
  test("run 2,yarn,4,5 valid with start 2", () => {
    expect(buildGroup(RUN4, [tabby(2), 96, tabby(4), tabby(5)], 2)).toEqual({
      kind: "run",
      cards: [1, 96, 3, 4],
      start: 2,
      end: 5,
    });
  });
  test("run yarn defaults to the lowest start that fits", () => {
    expect(buildGroup(RUN4, [tabby(5), 96, tabby(7), tabby(8)])).toMatchObject({
      start: 5,
      end: 8,
      cards: [4, 96, 6, 7],
    });
    expect(buildGroup(RUN4, [96, tabby(5), tabby(6), tabby(7)])).toMatchObject({
      start: 4,
      end: 7,
      cards: [96, 4, 5, 6],
    });
    expect(buildGroup(RUN4, [96, 97, tabby(1), tabby(2)])).toMatchObject({
      start: 1,
      end: 4,
      cards: [0, 1, 96, 97],
    });
  });
  test("an explicit runStart is validated", () => {
    const cards = [tabby(2), 96, tabby(4), tabby(5)];
    expect(buildGroup(RUN4, cards, 3)).toBeNull(); // 2 falls before the run
    expect(buildGroup(RUN4, cards, 1)).toBeNull(); // 5 falls after the run
    expect(buildGroup(RUN4, cards, 0)).toBeNull();
    expect(buildGroup(RUN4, cards, 2.5)).toBeNull();
    expect(buildGroup(RUN4, [96, 97, 98, tabby(12)], 10)).toBeNull(); // past 12
    expect(buildGroup(RUN4, [96, 97, 98, tabby(12)], 9)).toMatchObject({
      start: 9,
      end: 12,
      cards: [96, 97, 98, 11],
    });
  });
  test("run all yarn, run with a cucumber, and runs longer than 12 are invalid", () => {
    expect(buildGroup(RUN3, [96, 97, 98])).toBeNull();
    expect(buildGroup(RUN3, [tabby(1), tabby(2), CUCUMBER])).toBeNull();
    const big = { kind: "run", size: 13 } as const;
    expect(
      buildGroup(big, [...Array.from({ length: 12 }, (_, i) => i), 96]),
    ).toBeNull();
  });
  test("a full 1-12 run is valid", () => {
    const g = buildGroup(
      { kind: "run", size: 12 },
      Array.from({ length: 12 }, (_, i) => i),
    );
    expect(g).toMatchObject({ start: 1, end: 12 });
  });
});

describe("buildGroup: coats", () => {
  test("coat of 7 tuxedo with two yarn valid", () => {
    const cards = [tuxedo(1), tuxedo(3), tuxedo(5), tuxedo(7), tuxedo(9), 96, 97];
    expect(buildGroup(COAT7, cards)).toEqual({ kind: "coat", cards, coat: "tuxedo" });
  });
  test("coat mixing tabby and gray invalid", () => {
    expect(buildGroup(COAT3, [tabby(1), gray(2), 96])).toBeNull();
  });
  test("coat with a cucumber or all yarn is invalid", () => {
    expect(buildGroup(COAT3, [tabby(1), tabby(2), CUCUMBER])).toBeNull();
    expect(buildGroup(COAT3, [96, 97, 98])).toBeNull();
  });
});

describe("canHit", () => {
  const run36 = buildGroup({ kind: "run", size: 4 }, [
    tabby(3),
    tabby(4),
    tabby(5),
    tabby(6),
  ]) as Group;

  test("canHit run 3..6 accepts 2 and 7, rejects 5", () => {
    const low = canHit(run36, tuxedo(2));
    expect(low).toEqual({
      ok: true,
      group: { kind: "run", cards: [tuxedo(2), 2, 3, 4, 5], start: 2, end: 6 },
    });
    const high = canHit(run36, calico(7));
    expect(high).toEqual({
      ok: true,
      group: { kind: "run", cards: [2, 3, 4, 5, calico(7)], start: 3, end: 7 },
    });
    expect(canHit(run36, gray(5))).toEqual({ ok: false });
    expect(canHit(run36, gray(9))).toEqual({ ok: false });
  });
  test("canHit does not mutate the original group", () => {
    canHit(run36, tuxedo(2));
    expect(run36).toMatchObject({ start: 3, end: 6, cards: [2, 3, 4, 5] });
  });
  test("canHit run 3..6 with yarn extends end", () => {
    expect(canHit(run36, 96)).toEqual({
      ok: true,
      group: { kind: "run", cards: [2, 3, 4, 5, 96], start: 3, end: 7 },
    });
  });
  test("canHit run 9..12 with yarn extends start to 8", () => {
    const run912 = buildGroup({ kind: "run", size: 4 }, [
      tabby(9),
      tabby(10),
      tabby(11),
      tabby(12),
    ]) as Group;
    expect(canHit(run912, 96)).toEqual({
      ok: true,
      group: { kind: "run", cards: [96, 8, 9, 10, 11], start: 8, end: 12 },
    });
    expect(canHit(run912, tuxedo(8))).toMatchObject({ ok: true });
    expect(canHit(run912, tuxedo(1))).toEqual({ ok: false });
  });
  test("canHit rejects Yarn on a full 1..12 run", () => {
    const full = buildGroup(
      { kind: "run", size: 12 },
      Array.from({ length: 12 }, (_, i) => i),
    ) as Group;
    expect(canHit(full, 96)).toEqual({ ok: false });
    expect(canHit(full, tuxedo(1))).toEqual({ ok: false });
    expect(canHit(full, tuxedo(12))).toEqual({ ok: false });
  });
  test("canHit yarn with side start extends a run 3..6 down to 2", () => {
    expect(canHit(run36, 96, "start")).toEqual({
      ok: true,
      group: { kind: "run", cards: [96, 2, 3, 4, 5], start: 2, end: 6 },
    });
    expect(canHit(run36, 96, "end")).toEqual(canHit(run36, 96));
  });
  test("canHit with a side refuses the end that cannot take the card", () => {
    const run912 = buildGroup({ kind: "run", size: 4 }, [tabby(9), tabby(10), tabby(11), tabby(12)]) as Group;
    expect(canHit(run912, 96, "end")).toEqual({ ok: false });
    const run112 = buildGroup({ kind: "run", size: 4 }, [tabby(1), tabby(2), tabby(3), tabby(4)]) as Group;
    expect(canHit(run112, 96, "start")).toEqual({ ok: false });
    expect(canHit(run36, tuxedo(2), "end")).toEqual({ ok: false });
    expect(canHit(run36, calico(7), "start")).toEqual({ ok: false });
    expect(canHit(run36, tuxedo(2), "start")).toEqual(canHit(run36, tuxedo(2)));
  });
  test("canHit ignores the side on sets and coats", () => {
    const sevens = buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), calico(7)]) as Group;
    expect(canHit(sevens, 96, "start")).toEqual(canHit(sevens, 96));
  });
  test("canHit set of 7s accepts 7 and yarn, rejects cucumber and other values", () => {
    const sevens = buildGroup(
      { kind: "set", size: 3 },
      [tabby(7), tuxedo(7), calico(7)],
    ) as Group;
    expect(canHit(sevens, gray(7))).toEqual({
      ok: true,
      group: { kind: "set", cards: [6, 30, 54, gray(7)], value: 7 },
    });
    expect(canHit(sevens, 96)).toMatchObject({ ok: true });
    expect(canHit(sevens, CUCUMBER)).toEqual({ ok: false });
    expect(canHit(sevens, gray(8))).toEqual({ ok: false });
  });
  test("canHit coat accepts same coat or yarn, rejects others", () => {
    const g = buildGroup(COAT3, [tabby(1), tabby(5), tabby(9)]) as Group;
    expect(canHit(g, tabby(12))).toMatchObject({ ok: true });
    expect(canHit(g, 96)).toMatchObject({ ok: true });
    expect(canHit(g, gray(1))).toEqual({ ok: false });
    expect(canHit(g, CUCUMBER)).toEqual({ ok: false });
  });
});

describe("shared fixtures (fixtures/groups.json)", () => {
  type Vector = {
    name: string;
    req: Requirement;
    cards: number[];
    runStart?: number;
    valid: boolean;
    /** The run's start, where the vector pins it. */
    start?: number;
  };
  const vectors = JSON.parse(
    readFileSync(new URL("../../fixtures/groups.json", import.meta.url), "utf8"),
  ) as Vector[];

  test("covers both outcomes", () => {
    expect(vectors.some((v) => v.valid)).toBe(true);
    expect(vectors.some((v) => !v.valid)).toBe(true);
  });

  for (const v of vectors) {
    test(`fixture: ${v.name}`, () => {
      const built = buildGroup(v.req, v.cards, v.runStart);
      expect(built !== null).toBe(v.valid);
      if (v.start !== undefined) expect(built).toMatchObject({ kind: "run", start: v.start });
    });
  }
});
