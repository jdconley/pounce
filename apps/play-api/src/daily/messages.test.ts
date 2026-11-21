import { describe, expect, it } from "vitest";

import { liveMessage, resultMessages } from "./messages";

import type { DailyResult } from "./module";

const result: DailyResult = { game: "test", date: "2026-11-23", number: 12, outcome: "solved", timeMs: 61_000, hints: 0, tooFast: false, progress: 1 };
const board = { date: "2026-11-23", games: [], dish: { rows: [] } };
const face = { name: "Kid", cat: 3 };

describe("board socket messages", () => {
  it("a result, then the board as it now stands", () => {
    expect(resultMessages("pr_1", result, board)).toEqual([
      { t: "result", player: "pr_1", result },
      { t: "board", board },
    ]);
  });

  it("progress carries the number only, for every socket", () => {
    expect(liveMessage("pr_1", face, { k: "progress", game: "test", date: "2026-11-23", progress: 0.5 })).toEqual({
      to: "all",
      message: { t: "progress", player: "pr_1", game: "test", progress: 0.5 },
    });
  });

  it("watching goes to TVs only", () => {
    expect(liveMessage("me", face, { k: "watchOffer", game: "test" })).toEqual({ to: "tv", message: { t: "watchOffer", player: "me", name: "Kid", cat: 3, game: "test" } });
    expect(liveMessage("me", face, { k: "watch", game: "test", state: { n: 2 } })).toEqual({ to: "tv", message: { t: "watch", player: "me", game: "test", state: { n: 2 } } });
    expect(liveMessage("me", face, { k: "watchEnd", game: "test", result: null })).toEqual({ to: "tv", message: { t: "watchEnd", player: "me", game: "test", result: null } });
  });
});
