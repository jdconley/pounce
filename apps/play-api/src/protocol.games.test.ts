import { describe, expect, it } from "vitest";

import { catTower } from "./games/cat-tower";
import { tiles } from "./games/tiles";
import { parseClientMessage } from "./protocol";

const BAD = { error: "bad_message" };
const act = (action: unknown, extra: Record<string, unknown> = {}) => JSON.stringify({ t: "act", seat: 1, action, ...extra });

describe("parseClientMessage with a game's own action parser", () => {
  it("a tile game room takes the tile game's actions", () => {
    for (const action of [{ type: "draw" }, { type: "pass" }, { type: "forfeit" }, { type: "play", table: [[3, 4, 5]] }]) {
      expect(parseClientMessage(act(action), tiles.parseAction)).toEqual({ t: "act", seat: 1, action });
    }
  });

  it("keeps the move id beside them", () => {
    expect(parseClientMessage(act({ type: "draw" }, { id: "move-7" }), tiles.parseAction)).toEqual({
      t: "act",
      seat: 1,
      action: { type: "draw" },
      id: "move-7",
    });
    expect(parseClientMessage(act({ type: "draw" }, { id: "no spaces" }), tiles.parseAction)).toEqual(BAD);
  });

  it("refuses Cat Tower's actions there, and anything malformed", () => {
    for (const action of [{ type: "draw", from: "deck" }, { type: "discard", card: 3 }, { type: "nextRound" }, { type: "play" }, { type: "play", table: [[106]] }, "draw", null]) {
      expect(parseClientMessage(act(action), tiles.parseAction), JSON.stringify(action)).toEqual(BAD);
    }
  });

  it("a Cat Tower room refuses the tile game's actions", () => {
    for (const action of [{ type: "draw" }, { type: "pass" }, { type: "play", table: [[3, 4, 5]] }]) {
      expect(parseClientMessage(act(action), catTower.parseAction), JSON.stringify(action)).toEqual(BAD);
    }
  });

  it("with no parser named, it is Cat Tower's: what every caller before there was a second game got", () => {
    const draw = { type: "draw", from: "deck" };
    expect(parseClientMessage(act(draw))).toEqual({ t: "act", seat: 1, action: draw });
    expect(parseClientMessage(act(draw))).toEqual(parseClientMessage(act(draw), catTower.parseAction));
    expect(parseClientMessage(act({ type: "pass" }))).toEqual(BAD);
  });

  it("everything that is not an act parses the same whatever the game", () => {
    for (const message of [{ t: "start" }, { t: "ping" }, { t: "leave", seat: 0 }, { t: "rematch" }, { t: "retire", seat: 1 }]) {
      expect(parseClientMessage(JSON.stringify(message), tiles.parseAction)).toEqual(message);
      expect(parseClientMessage(JSON.stringify(message))).toEqual(message);
    }
  });

  it("the size limit holds a whole table with room to spare", () => {
    const table = [...Array.from({ length: 34 }, (_, i) => [3 * i, 3 * i + 1, 3 * i + 2]), [102, 103, 104, 105]];
    const raw = act({ type: "play", table }, { id: "0f8fad5b-d9cb-469f-a165-70867728950e" });
    expect(new TextEncoder().encode(raw).length).toBeLessThan(1024);
    expect(parseClientMessage(raw, tiles.parseAction)).toMatchObject({ t: "act", action: { type: "play", table } });
  });
});
