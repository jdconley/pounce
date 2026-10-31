import { describe, expect, test } from "vitest";

import { matchPhase, PHASES } from "./phases";

// Card ids (see cards.ts): tabby v = v-1, tuxedo v = 23+v, calico v = 47+v,
// gray v = 71+v (e.g. tabby 3 = id 2, tuxedo 7 = id 30); 96-103 = Yarn.
const YARN = 96;
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;

describe("matchPhase", () => {
  test("matchPhase(0, two sets of 3) returns 2 groups", () => {
    const r = matchPhase(0, [
      { cards: [tabby(7), tuxedo(7), YARN] },
      { cards: [tabby(2), tuxedo(2), calico(2)] },
    ]);
    expect(r).toHaveLength(2);
    expect(r?.map((g) => g.kind)).toEqual(["set", "set"]);
  });
  test("matchPhase(1, groups in wrong order) returns null", () => {
    const set = { cards: [tabby(7), tuxedo(7), YARN] };
    const run = { cards: [tabby(3), tuxedo(4), calico(5), gray(6)] };
    expect(matchPhase(1, [set, run])).toHaveLength(2);
    expect(matchPhase(1, [run, set])).toBeNull();
  });
  test("matchPhase passes runStart through", () => {
    const r = matchPhase(1, [
      { cards: [tabby(7), tuxedo(7), YARN] },
      { cards: [tabby(2), YARN+1, tabby(4), tabby(5)], runStart: 2 },
    ]);
    expect(r?.[1]).toMatchObject({ kind: "run", start: 2, end: 5 });
    expect(
      matchPhase(1, [
        { cards: [tabby(7), tuxedo(7), YARN] },
        { cards: [tabby(2), YARN+1, tabby(4), tabby(5)], runStart: 3 },
      ]),
    ).toBeNull();
  });
  test("matchPhase(3, run of 7) ok, run of 6 null", () => {
    const seven = [1, 2, 3, 4, 5, 6, 7].map(tabby);
    expect(matchPhase(3, [{ cards: seven }])).toHaveLength(1);
    expect(matchPhase(3, [{ cards: seven.slice(0, 6) }])).toBeNull();
  });
  test("matchPhase rejects wrong group counts and bad phase indexes", () => {
    const set = { cards: [tabby(7), tuxedo(7), YARN] };
    expect(matchPhase(0, [set])).toBeNull();
    expect(matchPhase(0, [set, set, set])).toBeNull();
    expect(matchPhase(-1, [set])).toBeNull();
    expect(matchPhase(10, [set])).toBeNull();
    expect(matchPhase(0.5, [set, set])).toBeNull();
  });
  test("matchPhase rejects a card used in two groups", () => {
    const a = { cards: [tabby(7), tuxedo(7), YARN] };
    const b = { cards: [tabby(2), tuxedo(2), YARN] };
    expect(matchPhase(0, [a, b])).toBeNull();
  });
});

describe("PHASES", () => {
  test("has the 10 phases in order", () => {
    expect(PHASES).toEqual([
      [{ kind: "set", size: 3 }, { kind: "set", size: 3 }],
      [{ kind: "set", size: 3 }, { kind: "run", size: 4 }],
      [{ kind: "set", size: 4 }, { kind: "run", size: 4 }],
      [{ kind: "run", size: 7 }],
      [{ kind: "run", size: 8 }],
      [{ kind: "run", size: 9 }],
      [{ kind: "set", size: 4 }, { kind: "set", size: 4 }],
      [{ kind: "coat", size: 7 }],
      [{ kind: "set", size: 5 }, { kind: "set", size: 2 }],
      [{ kind: "set", size: 5 }, { kind: "set", size: 3 }],
    ]);
  });
});

