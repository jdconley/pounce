import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { card, type CardId } from "./cards";
import { buildGroup, type Group } from "./groups";
import { matchPhase, PHASES } from "./phases";
import { createRng, shuffle } from "./rng";
import { findHits, findPhase, phaseProgress } from "./solver";

/* Card ids: tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v. */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;
const YARN = [96, 97, 98, 99, 100, 101, 102, 103];
const CUCUMBER = 104;

function expectValid(hand: CardId[], phase: number): void {
  const found = findPhase(hand, phase);
  expect(found).not.toBeNull();
  const groups = found as { cards: CardId[]; runStart?: number }[];
  expect(matchPhase(phase, groups)).not.toBeNull();
  for (const id of groups.flatMap((g) => g.cards)) expect(hand).toContain(id);
}

describe("findPhase", () => {
  test("finds two sets with a yarn", () => {
    const hand = [
      tabby(5), tuxedo(5), calico(5),
      tabby(8), tuxedo(8), YARN[0] as number,
      gray(2), gray(11), CUCUMBER, tabby(12),
    ];
    expectValid(hand, 0);
  });

  test("returns null one card short", () => {
    const hand = [
      tabby(5), tuxedo(5), calico(5),
      tabby(8), tuxedo(8),
      gray(2), gray(11), CUCUMBER, tabby(12), tabby(1),
    ];
    expect(findPhase(hand, 0)).toBeNull();
  });

  test("run of 9 with two yarn", () => {
    const hand = [
      tabby(2), tuxedo(3), calico(4), gray(5), tabby(7), tuxedo(8), calico(10),
      YARN[0] as number, YARN[1] as number, tabby(12),
    ];
    // 2..10 with yarn standing at 6 and 9.
    expectValid(hand, 5);
    const found = findPhase(hand, 5) as { cards: CardId[]; runStart?: number }[];
    expect(found[0]?.runStart).toBe(2);
  });

  test("saves yarn for the second group", () => {
    // Set of 5s needs no yarn; the run needs both yarn.
    const hand = [
      tabby(5), tuxedo(5), calico(5),
      tabby(1), tabby(2), tabby(4),
      YARN[0] as number, YARN[1] as number, tabby(9), tabby(11),
    ];
    // Phase 2: set(3) + run(4): run is 1,2,yarn,4 using one yarn.
    expectValid(hand, 1);
  });

  test("lets a run borrow a natural from the set via yarn", () => {
    // Three 6s are the only set; the run 5,6,7,8 must use yarn at 6.
    const hand = [
      tabby(6), tuxedo(6), calico(6),
      tabby(5), tabby(7), tabby(8),
      YARN[0] as number, tabby(1), tabby(12), tabby(10),
    ];
    expectValid(hand, 1);
  });

  test("finds a coat group padded with yarn", () => {
    const hand = [
      tuxedo(1), tuxedo(3), tuxedo(5), tuxedo(7), tuxedo(9), tuxedo(11),
      YARN[0] as number, tabby(2), gray(4), calico(6),
    ];
    expectValid(hand, 7);
  });

  test("rejects a coat group with no natural to anchor it", () => {
    // Seven Yarn alone are not a coat group; one natural anchors it.
    expect(findPhase([...YARN.slice(0, 7), CUCUMBER], 7)).toBeNull();
    expectValid([...YARN.slice(0, 6), tabby(1), CUCUMBER], 7);
  });

  test("returns null for an unknown phase", () => {
    expect(findPhase([tabby(1)], 10)).toBeNull();
    expect(findPhase([tabby(1)], -1)).toBeNull();
  });

  test("matches exhaustive search on random hands", () => {
    const rng = createRng(seedOf(2026));
    // A skewed pool (few values, extra Yarn) so both outcomes are common.
    const pool: CardId[] = [];
    for (let id = 0; id < 96; id++) {
      const value = (id % 12) + 1;
      if (value <= 7) pool.push(id);
    }
    pool.push(...YARN, ...YARN, CUCUMBER);

    let positives = 0;
    let negatives = 0;
    for (let i = 0; i < 200; i++) {
      const size = i % 2 === 0 ? 10 : 11;
      const hand = [...new Set(shuffle(pool, rng))].slice(0, size);
      const phase = i % PHASES.length;
      const expected = bruteForce(hand, phase);
      const actual = findPhase(hand, phase);
      expect(actual !== null, `hand ${JSON.stringify(hand)} phase ${phase}`).toBe(
        expected,
      );
      if (actual === null) {
        negatives++;
      } else {
        positives++;
        expect(matchPhase(phase, actual)).not.toBeNull();
        for (const id of actual.flatMap((g) => g.cards)) {
          expect(hand).toContain(id);
        }
      }
    }
    expect(positives).toBeGreaterThanOrEqual(40);
    expect(negatives).toBeGreaterThanOrEqual(40);
  });
});

/** Exhaustive search: every way of choosing disjoint card subsets of the required sizes. */
function bruteForce(hand: CardId[], phase: number): boolean {
  const reqs = PHASES[phase] ?? [];
  const pick = (pool: CardId[], r: number): CardId[][] => {
    if (r === 0) return [[]];
    const out: CardId[][] = [];
    for (let i = 0; i + r <= pool.length; i++) {
      for (const rest of pick(pool.slice(i + 1), r - 1)) {
        out.push([pool[i] as CardId, ...rest]);
      }
    }
    return out;
  };
  const search = (pool: CardId[], index: number): boolean => {
    const req = reqs[index];
    if (req === undefined) return true;
    return pick(pool, req.size).some(
      (cards) =>
        buildGroup(req, cards) !== null &&
        search(
          pool.filter((id) => !cards.includes(id)),
          index + 1,
        ),
    );
  };
  return search(hand, 0);
}

describe("phaseProgress", () => {
  test("counts cards usable toward a set pair", () => {
    // Phase 1: set(3)+set(3). Three 5s and two 8s -> 5 cards.
    const hand = [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), tabby(1), tabby(2)];
    expect(phaseProgress(hand, 0)).toBe(5);
  });

  test("a complete phase scores its full size", () => {
    const hand = [
      tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), YARN[0] as number, gray(1),
    ];
    expect(phaseProgress(hand, 0)).toBe(6);
  });

  test("yarn only fills real gaps and Cucumbers never count", () => {
    expect(phaseProgress([YARN[0] as number, CUCUMBER], 3)).toBe(1);
    expect(phaseProgress([...YARN.slice(0, 8)], 3)).toBe(7);
  });

  test("scores runs by distinct values in the best window", () => {
    const hand = [tabby(3), tuxedo(3), tabby(4), tabby(5), tabby(9), tabby(11)];
    // Window 3..9 holds 3, 4, 5 and 9.
    expect(phaseProgress(hand, 3)).toBe(4);
  });

  test("a set leaves cards for the run", () => {
    // set(3)+run(4): 6,6,6 and 7,8,9 -> the run can use one 6.
    const hand = [tabby(6), tuxedo(6), calico(6), tabby(7), tabby(8), tabby(9)];
    expect(phaseProgress(hand, 1)).toBe(6);
  });

  test("coat counts the best coat, capped at 7", () => {
    const hand = [
      ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map(gray),
      tabby(1),
    ];
    expect(phaseProgress(hand, 7)).toBe(7);
    expect(phaseProgress([tabby(1), tuxedo(2), tuxedo(3)], 7)).toBe(2);
  });

  test("is zero for an unknown phase", () => {
    expect(phaseProgress([tabby(1)], 10)).toBe(0);
  });
});

describe("findHits", () => {
  const run = (start: number, ids: CardId[]): Group =>
    buildGroup({ kind: "run", size: ids.length }, ids, start) as Group;

  test("finds extension of opponent run", () => {
    const laid: (Group[] | null)[] = [
      null,
      [run(4, [tabby(4), tabby(5), tabby(6), tabby(7)])],
    ];
    const hits = findHits([tuxedo(8), tuxedo(3), tuxedo(10), CUCUMBER], laid);
    expect(hits).toEqual([
      { card: tuxedo(8), target: { seat: 1, group: 0 } },
      { card: tuxedo(3), target: { seat: 1, group: 0 } },
    ]);
  });

  test("lists naturals before yarn and every matching group", () => {
    const set = buildGroup({ kind: "set", size: 3 }, [tabby(9), tuxedo(9), calico(9)]) as Group;
    const laid: (Group[] | null)[] = [[set], [set]];
    const hits = findHits([YARN[0] as number, gray(9)], laid);
    expect(hits.map((h) => [card(h.card).kind, h.target.seat])).toEqual([
      ["number", 0],
      ["number", 1],
      ["yarn", 0],
      ["yarn", 1],
    ]);
  });

  test("is empty when nobody has laid down", () => {
    expect(findHits([tabby(1)], [null, null])).toEqual([]);
  });
});
