import { describe, expect, test } from "vitest";

import { groupDrop, heldRect, type GroupSpot } from "../src/table/ct-drop";

import type { HitSide } from "@pounce/play-api/rules/groups";

// Two small laid groups side by side, as a phone lays them: 40 wide, 30 tall, 10 apart.
const spots: GroupSpot[] = [
  { seat: 0, group: 0, rect: { x: 100, y: 100, w: 40, h: 30 }, run: false },
  { seat: 1, group: 0, rect: { x: 150, y: 100, w: 40, h: 30 }, run: true },
];
/** The card fits these: seat 1's run on its high end only, unless told otherwise. */
const fitsOnly =
  (fits: Record<string, (HitSide | undefined)[]>) =>
  (seat: number, group: number): (HitSide | undefined)[] =>
    fits[`${seat}:${group}`] ?? [];
const card = (cx: number, cy: number) => ({ x: cx - 30, y: cy - 42, w: 60, h: 84 });

describe("groupDrop", () => {
  test("the group under the finger, as before", () => {
    const aim = groupDrop({ finger: { x: 120, y: 115 }, card: card(120, 115), spots, sides: fitsOnly({ "0:0": [undefined] }), onTable: true });
    expect(aim).toEqual({ seat: 0, group: 0, ok: true });
  });

  test("a group the held card covers, with the finger off its edge", () => {
    const aim = groupDrop({ finger: { x: 120, y: 60 }, card: card(120, 60), spots, sides: fitsOnly({ "0:0": [undefined] }), onTable: true });
    expect(aim).toEqual({ seat: 0, group: 0, ok: true });
  });

  test("of the groups the card covers, the one it fits", () => {
    // The finger is over seat 0's group, which the card doesn't fit; it covers seat 1's run too.
    const aim = groupDrop({ finger: { x: 135, y: 115 }, card: card(135, 115), spots, sides: fitsOnly({ "1:0": ["end"] }), onTable: true });
    expect(aim).toEqual({ seat: 1, group: 0, side: "end", ok: true });
  });

  test("a group it doesn't fit, under the finger, is a miss to show", () => {
    const aim = groupDrop({ finger: { x: 120, y: 115 }, card: card(120, 115), spots: spots.slice(0, 1), sides: fitsOnly({}), onTable: true });
    expect(aim).toEqual({ seat: 0, group: 0, ok: false });
  });

  test("a run's one end that fits, whichever half the finger is on", () => {
    const aim = groupDrop({ finger: { x: 152, y: 115 }, card: card(152, 115), spots: spots.slice(1), sides: fitsOnly({ "1:0": ["end"] }), onTable: true });
    expect(aim).toEqual({ seat: 1, group: 0, side: "end", ok: true });
  });

  test("a run that takes it at both ends: the end the finger is nearer", () => {
    const sides = fitsOnly({ "1:0": ["start", "end"] });
    expect(groupDrop({ finger: { x: 155, y: 115 }, card: card(155, 115), spots: spots.slice(1), sides, onTable: true })).toEqual({ seat: 1, group: 0, side: "start", ok: true });
    expect(groupDrop({ finger: { x: 185, y: 115 }, card: card(185, 115), spots: spots.slice(1), sides, onTable: true })).toEqual({ seat: 1, group: 0, side: "end", ok: true });
  });

  test("the one group a card fits, from anywhere on the table", () => {
    const aim = groupDrop({ finger: { x: 400, y: 400 }, card: card(400, 400), spots, sides: fitsOnly({ "0:0": [undefined] }), onTable: true });
    expect(aim).toEqual({ seat: 0, group: 0, ok: true });
  });

  test("off the table, or with two places it fits, nothing far away", () => {
    expect(groupDrop({ finger: { x: 400, y: 400 }, card: card(400, 400), spots, sides: fitsOnly({ "0:0": [undefined] }), onTable: false })).toBeNull();
    expect(groupDrop({ finger: { x: 400, y: 400 }, card: card(400, 400), spots, sides: fitsOnly({ "0:0": [undefined], "1:0": ["end"] }), onTable: true })).toBeNull();
  });

  test("nothing fits and nothing is near: nothing", () => {
    expect(groupDrop({ finger: { x: 400, y: 400 }, card: card(400, 400), spots, sides: fitsOnly({}), onTable: true })).toBeNull();
  });
});

describe("heldRect", () => {
  test("a held card is drawn scaled about its middle", () => {
    expect(heldRect({ x: 10, y: 20, s: 1.5 }, 60, 80)).toEqual({ x: -5, y: 0, w: 90, h: 120 });
  });
});
