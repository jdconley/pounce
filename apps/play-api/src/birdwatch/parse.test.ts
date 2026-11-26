import { expect, test } from "vitest";

import { parseAction, parseOptions } from "./parse";

test("each action as it is", () => {
  for (const a of [
    { type: "bid", amount: 85 },
    { type: "pass" },
    { type: "nest", discard: [1, 2, 56] },
    { type: "trump", suit: "bell" },
    { type: "partner", card: 0 },
    { type: "play", card: 56 },
    { type: "nextHand" },
    { type: "forfeit" },
  ]) {
    expect(parseAction(a)).toEqual(a);
  }
});

test("anything else is refused", () => {
  for (const a of [
    null,
    [],
    "pass",
    { type: "pass", extra: 1 },
    { type: "bid" },
    { type: "bid", amount: "80" },
    { type: "bid", amount: 80.5 },
    { type: "bid", amount: -5 },
    { type: "bid", amount: 1005 },
    { type: "trump", suit: "bird" },
    { type: "play", card: 57 },
    { type: "partner", card: -1 },
    { type: "nest", discard: [] },
    { type: "nest", discard: [1, 2, 3, 4, 5, 6, 7, 8] },
    { type: "nest", discard: [1, "2"] },
    { type: "nest", discard: 1 },
    { type: "nest" },
    { type: "draw" },
  ]) {
    expect(parseAction(a), JSON.stringify(a)).toBeNull();
  }
});

test("a table's rule set", () => {
  expect(parseOptions({ rules: "friesen" })).toEqual({ rules: "friesen" });
  for (const o of [null, {}, { rules: "house" }, { rules: "tucker", more: 1 }, "tucker"]) expect(parseOptions(o)).toBeNull();
});
