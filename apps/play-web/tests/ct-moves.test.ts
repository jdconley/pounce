import { canHit, type Group } from "@pounce/play-api/rules/groups";
import { describe, expect, test } from "vitest";

import { aimedGroup, discardNeedsTarget, hitTargets, layDownGroups, skipTargets, targetLabel } from "../src/table/ct-moves";

import type { RoomView } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";

// Card ids: 0-95 are numbers, value = id % 12 + 1, coat = floor(id / 24) (0-23 tabby, 24-47 tuxedo,
// 48-71 calico, 72-95 gray); 96-103 Yarn; 104-107 Cucumber.
const YARN = 96;
const CUCUMBER = 104;
const threes: Group = { kind: "set", cards: [2, 14, 26], value: 3 };
const fourToSeven: Group = { kind: "run", cards: [3, 4, 5, 6], start: 4, end: 7 };
const sevenToTen: Group = { kind: "run", cards: [6, 7, 8, 9], start: 7, end: 10 };
const twelves: Group = { kind: "set", cards: [11, 23, 35], value: 12 };
const tabbies: Group = { kind: "coat", cards: [0, 1, 2, 13, 14, 20, 23], coat: "tabby" };

const game = (over: Partial<CatTowerView>): CatTowerView => ({
  round: 1,
  dealer: 0,
  turn: 0,
  step: "play",
  status: "playing",
  deckCount: 40,
  discardTop: 1,
  discardCount: 2,
  phase: [0, 0, 0, 0],
  scores: [0, 0, 0, 0],
  laid: [null, null, null, null],
  handCounts: [10, 10, 10, 10],
  hands: {},
  pendingSkip: [false, false, false, false],
  winners: [],
  forfeited: [false, false, false, false],
  ...over,
});

const human = (name: string, yours: boolean): RoomView["seats"][number] => ({ kind: "human", person: { id: `id-${name}`, name, cat: 1 }, yours, presence: "awake" });

const room = (g: CatTowerView, seats: RoomView["seats"]): RoomView => ({ code: "BCDFG", name: "Home", status: "playing", youAreHost: true, seats, game: g });

describe("hitTargets: where a card can go on the laid groups", () => {
  const laid: (Group[] | null)[] = [[threes, fourToSeven], null];

  /** Every (seat, group, side) canHit takes, the long way. */
  const byCanHit = (id: number) =>
    laid.flatMap((groups, seat) =>
      (groups ?? []).flatMap((g, group) =>
        g.kind === "run"
          ? (["start", "end"] as const).filter((side) => canHit(g, id, side).ok).map((side) => ({ seat, group, side }))
          : canHit(g, id).ok
            ? [{ seat, group }]
            : [],
      ),
    );

  test("a 3 goes on the set of 3s and below the run of 4 to 7", () => {
    expect(hitTargets(50, laid)).toEqual([
      { seat: 0, group: 0 },
      { seat: 0, group: 1, side: "start" },
    ]);
  });

  test("an 8 goes only on the run's high end", () => {
    expect(hitTargets(7, laid)).toEqual([{ seat: 0, group: 1, side: "end" }]);
  });

  test("a Yarn fits the set and both ends of the run", () => {
    expect(hitTargets(YARN, laid)).toEqual([
      { seat: 0, group: 0 },
      { seat: 0, group: 1, side: "start" },
      { seat: 0, group: 1, side: "end" },
    ]);
  });

  test("a Cucumber goes nowhere, and a seat that hasn't laid down has no targets", () => {
    expect(hitTargets(CUCUMBER, laid)).toEqual([]);
    expect(hitTargets(YARN, [null, null])).toEqual([]);
    expect(hitTargets(50, laid).some((t) => t.seat === 1)).toBe(false);
  });

  test("matches canHit for every card", () => {
    for (let id = 0; id < 108; id++) expect(hitTargets(id, laid)).toEqual(byCanHit(id));
  });
});

describe("layDownGroups: the trays as a lay-down, or null", () => {
  test("phase 1: two sets of 3", () => {
    expect(layDownGroups([[2, 14, 26], [3, 15, 27]], 0)).toEqual([{ cards: [2, 14, 26] }, { cards: [3, 15, 27] }]);
    expect(layDownGroups([[2, 14, 3], [3, 15, 27]], 0)).toBeNull();
    expect(layDownGroups([[2, 14, 26]], 0)).toBeNull();
  });

  test("phase 4: a run of 7, with or without a Yarn in it", () => {
    expect(layDownGroups([[0, 1, 2, 3, 4, 5, 6]], 3)).toEqual([{ cards: [0, 1, 2, 3, 4, 5, 6] }]);
    expect(layDownGroups([[0, 1, YARN, 3, 4, 5, 6]], 3)).toEqual([{ cards: [0, 1, YARN, 3, 4, 5, 6] }]);
    expect(layDownGroups([[0, 1, 2, 3, 4, 5]], 3)).toBeNull();
    expect(layDownGroups([[0, 1, 2, 3, 4, 5, 7]], 3)).toBeNull();
  });

  test("phase 8: seven of one coat", () => {
    expect(layDownGroups([[0, 1, 2, 13, 14, 20, 23]], 7)).toEqual([{ cards: [0, 1, 2, 13, 14, 20, 23] }]);
    expect(layDownGroups([[0, 1, 2, 13, 14, 20, 30]], 7)).toBeNull();
  });

  test("no phase past the tenth", () => {
    expect(layDownGroups([[2, 14, 26], [3, 15, 27]], 10)).toBeNull();
  });
});

describe("discards", () => {
  test("only a Cucumber needs a seat to skip", () => {
    expect(discardNeedsTarget(CUCUMBER)).toBe(true);
    expect(discardNeedsTarget(107)).toBe(true);
    expect(discardNeedsTarget(YARN)).toBe(false);
    expect(discardNeedsTarget(0)).toBe(false);
  });

  const four = [human("Mom", true), human("Ava", false), { kind: "bot", yours: false, presence: null } as const, human("Grandpa", false)];

  test("a skip goes to anyone else not already skipped and still playing", () => {
    const v = game({ pendingSkip: [false, true, false, false], forfeited: [false, false, true, false] });
    expect(skipTargets(v, 0, four)).toEqual([3]);
    expect(skipTargets(v, 3, four)).toEqual([0]);
    expect(skipTargets(game({}), 2, four)).toEqual([0, 1, 3]);
  });

  test("a House Cat can be skipped; an open or closed seat can't", () => {
    const seats = [human("Mom", true), { kind: "open", yours: false, presence: null } as const, { kind: "bot", yours: false, presence: null } as const, { kind: "closed", yours: false, presence: null } as const];
    expect(skipTargets(game({}), 0, seats)).toEqual([2]);
  });
});

describe("targetLabel: a laid group in words", () => {
  const g = game({ laid: [[threes, fourToSeven], [sevenToTen], [twelves], [tabbies]] });
  const seats = [human("Mom", true), human("Ava", false), { kind: "bot", yours: false, presence: null } as const, human("Grandpa", false)];
  const r = room(g, seats);

  test("someone else's groups by their name", () => {
    expect(targetLabel(r, 1, 0)).toBe("Ava's run from 7");
    expect(targetLabel(r, 2, 0)).toBe("House Cat's 12s");
    expect(targetLabel(r, 3, 0)).toBe("Grandpa's tabbies");
  });

  test("this device's own seat is yours", () => {
    expect(targetLabel(r, 0, 0)).toBe("Your 3s");
    expect(targetLabel(r, 0, 1)).toBe("Your run");
  });

  test("a shared device names every seat", () => {
    const both = room(g, [human("Mom", true), human("Ava", true), seats[2]!, seats[3]!]);
    expect(targetLabel(both, 0, 0)).toBe("Mom's 3s");
    expect(targetLabel(both, 1, 0)).toBe("Ava's run from 7");
  });
});

describe("aimedGroup: the group the acting player points at", () => {
  const g = game({ turn: 1, laid: [[threes], [sevenToTen], null, null] });
  const aims = { 1: { target: { seat: 0, group: 0 } } };

  test("someone else's aim glows", () => {
    expect(aimedGroup(room(g, [human("Mom", true), human("Ava", false), human("Theo", false), human("Mia", false)]), aims)).toEqual({ seat: 0, group: 0 });
  });

  test("a seat this device holds never shows its own aim", () => {
    expect(aimedGroup(room(g, [human("Mom", false), human("Ava", true), human("Theo", false), human("Mia", false)]), aims)).toBeNull();
  });

  test("nothing between rounds, and nothing from a seat not acting", () => {
    const seats = [human("Mom", true), human("Ava", false), human("Theo", false), human("Mia", false)];
    expect(aimedGroup(room({ ...g, status: "roundOver" } as CatTowerView, seats), aims)).toBeNull();
    expect(aimedGroup(room({ ...g, turn: 2 }, seats), aims)).toBeNull();
  });
});
