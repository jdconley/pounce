import { describe, expect, it } from "vitest";

import { pairReport } from "./pair-core";

import type { StreakIntent } from "../room/core";

const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
const C = "p_CCCCCCCCCCCCCCCCCCCCCC";

const intent = (out?: string[]): StreakIntent => ({
  code: "BCDFG",
  at: 5,
  by: A,
  holder: B,
  players: [A, B, C],
  turnedAt: { [A]: 5 },
  over: false,
  ...(out ? { out } : {}),
});

describe("pairReport", () => {
  it("passes the report through when nobody in the pair forfeited", () => {
    expect(pairReport(intent(), A, B)).toEqual({ code: "BCDFG", at: 5, by: A, holder: B, over: false });
    expect(pairReport(intent([C]), A, B)).toEqual({ code: "BCDFG", at: 5, by: A, holder: B, over: false });
  });

  it("is over, with no turn and no holder, for a pair with someone who forfeited", () => {
    expect(pairReport(intent([C]), A, C)).toEqual({ code: "BCDFG", at: 5, by: null, holder: null, over: true });
    expect(pairReport(intent([A]), A, B)).toEqual({ code: "BCDFG", at: 5, by: null, holder: null, over: true });
  });
});
