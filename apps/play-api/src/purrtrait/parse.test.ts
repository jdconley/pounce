import { describe, expect, it } from "vitest";

import { DEFAULT_OPTIONS, isRoomOnly, parseAction, parseOptions, parseRoomAction } from "./parse";

describe("parseAction", () => {
  it("parses every client action", () => {
    expect(parseAction({ type: "choose", level: "easy" })).toEqual({ type: "choose", level: "easy" });
    expect(parseAction({ type: "choose", level: "tricky" })).toEqual({ type: "choose", level: "tricky" });
    expect(parseAction({ type: "gotIt", seat: 3 })).toEqual({ type: "gotIt", seat: 3 });
    expect(parseAction({ type: "giveUp" })).toEqual({ type: "giveUp" });
    expect(parseAction({ type: "forfeit" })).toEqual({ type: "forfeit" });
  });

  it("rejects bad shapes", () => {
    expect(parseAction(null)).toBeNull();
    expect(parseAction({ type: "choose" })).toBeNull();
    expect(parseAction({ type: "choose", level: "hard" })).toBeNull();
    expect(parseAction({ type: "gotIt", seat: -1 })).toBeNull();
    expect(parseAction({ type: "gotIt", seat: 10 })).toBeNull();
    expect(parseAction({ type: "gotIt", seat: 1.5 })).toBeNull();
    expect(parseAction({ type: "giveUp", extra: 1 })).toBeNull();
    expect(parseAction({ type: "pounce" })).toBeNull();
  });

  it("refuses the room-only actions from a client", () => {
    expect(parseAction({ type: "timeUp" })).toBeNull();
    expect(parseAction({ type: "nextTurn" })).toBeNull();
  });
});

describe("parseRoomAction", () => {
  it("parses timeUp and nextTurn and flags them room-only", () => {
    const t = parseRoomAction({ type: "timeUp" });
    const n = parseRoomAction({ type: "nextTurn" });
    expect(t).toEqual({ type: "timeUp" });
    expect(n).toEqual({ type: "nextTurn" });
    expect(isRoomOnly(t!)).toBe(true);
    expect(isRoomOnly(n!)).toBe(true);
    expect(isRoomOnly({ type: "giveUp" })).toBe(false);
  });

  it("still parses client actions", () => {
    expect(parseRoomAction({ type: "gotIt", seat: 2 })).toEqual({ type: "gotIt", seat: 2 });
    expect(parseRoomAction({ type: "nextTurn", x: 1 })).toBeNull();
  });
});

describe("parseOptions", () => {
  it("accepts the three timers", () => {
    for (const timer of [45, 60, 90]) expect(parseOptions({ timer })).toEqual({ timer });
    expect(DEFAULT_OPTIONS).toEqual({ timer: 60 });
  });

  it("rejects anything else", () => {
    expect(parseOptions({ timer: 30 })).toBeNull();
    expect(parseOptions({})).toBeNull();
    expect(parseOptions({ timer: 60, x: 1 })).toBeNull();
    expect(parseOptions("60")).toBeNull();
  });
});
