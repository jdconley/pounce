import { describe, expect, it } from "vitest";

import { mergeSection } from "./state";

const NOW = 1_000_000;

describe("mergeSection", () => {
  it("takes the newer entry and keeps keys the patch doesn't name", () => {
    expect(
      mergeSection({ a: { v: 1, at: 10 }, b: { v: 2, at: 10 } }, { a: { v: 3, at: 11 } }, NOW),
    ).toEqual({ a: { v: 3, at: 11 }, b: { v: 2, at: 10 } });
  });

  it("keeps the current entry on a tie or an older patch", () => {
    const current = { a: { v: 1, at: 10 } };
    expect(mergeSection(current, { a: { v: 9, at: 10 } }, NOW)).toEqual(current);
    expect(mergeSection(current, { a: { v: 9, at: 9 } }, NOW)).toEqual(current);
  });

  it("clamps a far-future time to a minute ahead, so one bad clock can't win forever", () => {
    expect(mergeSection({}, { a: { v: 1, at: NOW * 10 } }, NOW)).toEqual({ a: { v: 1, at: NOW + 60_000 } });
  });

  it("does not change its inputs", () => {
    const current = { a: { v: 1, at: 1 } };
    mergeSection(current, { a: { v: 2, at: 2 } }, NOW);
    expect(current).toEqual({ a: { v: 1, at: 1 } });
  });
});
