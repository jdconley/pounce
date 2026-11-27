import { describe, expect, it } from "vitest";

import { parseClientMessage } from "../protocol";

import { parseTumble } from "./wire";

describe("parseTumble", () => {
  it("takes a batch of every event kind", () => {
    const msg = { t: "tumble", r: 2, ev: [["m", 14, 1, 5, 9], ["l", 14, 1, 5, 3, 41250, [7]], ["a", 31], ["u", 0, 3]] };
    expect(parseTumble(msg)).toEqual(msg);
    expect(parseTumble({ t: "tumble", r: 0, ev: [] })).toEqual({ t: "tumble", r: 0, ev: [] });
  });

  it.each([
    ["an extra key", { t: "tumble", r: 1, ev: [], x: 1 }],
    ["a missing round", { t: "tumble", ev: [] }],
    ["a float", { t: "tumble", r: 1, ev: [["m", 1.5, 0, 0, 0]] }],
    ["a bad turn", { t: "tumble", r: 1, ev: [["m", 1, 4, 0, 0]] }],
    ["a position far outside", { t: "tumble", r: 1, ev: [["m", 1, 0, 40, 0]] }],
    ["a negative id", { t: "tumble", r: 1, ev: [["a", -1]] }],
    ["an unknown event", { t: "tumble", r: 1, ev: [["z", 1]] }],
    ["an event too long", { t: "tumble", r: 1, ev: [["a", 1, 2]] }],
    ["a seat past 5", { t: "tumble", r: 1, ev: [["u", 0, 6]] }],
    ["a slot past 5", { t: "tumble", r: 1, ev: [["u", 6, 0]] }],
    ["too many landed", { t: "tumble", r: 1, ev: [["l", 1, 0, 0, 0, 0, Array.from({ length: 17 }, (_, i) => i)]] }],
    ["a clock past 10 minutes", { t: "tumble", r: 1, ev: [["l", 1, 0, 0, 0, 600_001, []]] }],
    ["too many events", { t: "tumble", r: 1, ev: Array.from({ length: 65 }, () => ["a", 1]) }],
    ["not an object", ["tumble"]],
  ])("refuses %s", (_, msg) => {
    expect(parseTumble(msg)).toBeNull();
  });

  it("is what parseClientMessage takes for t: tumble", () => {
    const msg = { t: "tumble", r: 3, ev: [["a", 9]] };
    expect(parseClientMessage(JSON.stringify(msg))).toEqual(msg);
    expect(parseClientMessage(JSON.stringify({ t: "tumble", r: 3, ev: [["a", "9"]] }))).toEqual({ error: "bad_message" });
  });
});
