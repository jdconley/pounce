import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import {
  boardStep,
  boardToKeep,
  EMPTY_SCREEN,
  keptBoard,
  notNow,
  offerWords,
  resultWords,
  stopWatching,
  tick,
  visibleRows,
  watch,
  type BoardScreen,
} from "../src/ui/tv/tv-board-model";

import type { BoardAnswer, BoardMessage } from "@pounce/play-api/daily/messages";
import type { DailyResult } from "@pounce/play-api/daily/module";

/** Every board socket message, as the server makes them (docs/daily-protocol.md). */
const socket = JSON.parse(readFileSync(new URL("../../play-api/fixtures/daily/protocol/socket.json", import.meta.url), "utf8")) as Record<string, BoardMessage>;
const msg = <T extends BoardMessage["t"]>(t: T) => structuredClone(socket[t]) as Extract<BoardMessage, { t: T }>;
const board = msg("board").board;
const KID = "pr_8tGqLm2vXc9RzK1wYb4NdA";
const GRANDPA = "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA";

const run = (messages: BoardMessage[], now = 1000, from: BoardScreen = EMPTY_SCREEN) => messages.reduce((s, m) => boardStep(s, m, now), from);

const result = (r: Partial<DailyResult>): DailyResult => ({ game: "test", date: "2026-11-23", number: 12, outcome: "solved", timeMs: 125_000, hints: 0, progress: 1, tooFast: false, ...r });

describe("the board on the TV", () => {
  test("a snapshot is the board shown", () => {
    expect(run([msg("board")]).board).toEqual(board);
  });

  test("a result, then its board, cheers that person's row", () => {
    const s = run([msg("board"), msg("result"), msg("board")], 5000);
    expect(s.cheer).toEqual({ player: KID, game: "test", solved: true, until: 5000 + 2400 });
    expect(tick(s, 5000 + 2401).cheer).toBeNull();
  });

  test("a run that wasn't solved cheers quietly", () => {
    const missed = { ...msg("result"), result: result({ outcome: "gaveUp" }) };
    expect(run([msg("board"), missed]).cheer?.solved).toBe(false);
  });

  test("progress moves a playing row in place, and never adds anyone", () => {
    const s = run([msg("board"), { t: "progress", player: GRANDPA, game: "test", progress: 0.75 }, { t: "progress", player: "pr_nobody", game: "test", progress: 0.5 }]);
    const rows = s.board!.games[0]!.rows;
    expect(rows.find((r) => r.player === GRANDPA)?.playing).toEqual({ progress: 0.75 });
    expect(rows).toHaveLength(3);
  });

  test("tvs, pong and kinds it doesn't know change nothing", () => {
    const s = run([msg("board")]);
    expect(run([{ t: "tvs", count: 3 }, { t: "pong" } as unknown as BoardMessage, { t: "later" } as unknown as BoardMessage], 1000, s)).toBe(s);
  });
});

describe("watching", () => {
  test("an offer is up for 20 seconds", () => {
    const s = run([msg("board"), msg("watchOffer")], 1000);
    expect(s.offer).toEqual({ player: KID, name: "Kid", cat: 5, game: "test", until: 21_000 });
    expect(tick(s, 21_000).offer).not.toBeNull();
    expect(tick(s, 21_001).offer).toBeNull();
  });

  test("a newer offer from someone else replaces it, with its own 20 seconds", () => {
    const s = run([msg("watchOffer")], 1000);
    const next = boardStep(s, { t: "watchOffer", player: GRANDPA, name: "Grandpa", cat: 1, game: "test" }, 9000);
    expect(next.offer).toMatchObject({ player: GRANDPA, until: 29_000 });
  });

  test("frames are kept from the offer on, even after Not now", () => {
    const s = notNow(run([msg("watchOffer"), msg("watch")]));
    expect(s.offer).toBeNull();
    expect(s.frames[KID]).toEqual({ game: "test", state: { n: 2 } });
  });

  test("Watch shows the offered run, drawn from the latest frame", () => {
    const s = watch(run([msg("watchOffer"), msg("watch")]), 2000);
    expect(s.offer).toBeNull();
    expect(s.watching).toEqual({ player: KID, name: "Kid", cat: 5, game: "test" });
    expect(boardStep(s, { t: "watch", player: KID, game: "test", state: { n: 3 } }, 2500).frames[KID]?.state).toEqual({ n: 3 });
  });

  test("the watched run's end shows its result for 6 seconds, then the board", () => {
    const s = run([msg("watchEnd")], 3000, watch(run([msg("watchOffer"), msg("watch")]), 2000));
    expect(s.ended).toEqual({ result: msg("watchEnd").result, name: "Kid", until: 9000 });
    expect(s.frames[KID]).toBeUndefined();
    const after = tick(s, 9001);
    expect(after.ended).toBeNull();
    expect(after.watching).toBeNull();
  });

  test("Show on TV turned off goes back to the board at once", () => {
    const s = boardStep(watch(run([msg("watchOffer")]), 2000), { t: "watchEnd", player: KID, game: "test", result: null }, 3000);
    expect(s.watching).toBeNull();
    expect(s.ended).toBeNull();
  });

  test("an end for someone not watched clears their offer and frames", () => {
    const s = boardStep(run([msg("watchOffer"), msg("watch")]), { t: "watchEnd", player: KID, game: "test", result: null }, 3000);
    expect(s.offer).toBeNull();
    expect(s.frames[KID]).toBeUndefined();
  });

  test("Back from watching is the board", () => {
    expect(stopWatching(watch(run([msg("watchOffer")]), 2000)).watching).toBeNull();
  });

  test("the card's words", () => {
    expect(offerWords({ player: KID, name: "Mom", cat: 3, game: "sniff", until: 0 })).toBe("Mom is playing Sniff. Spoilers.");
    expect(offerWords({ player: KID, name: "Kid", cat: 3, game: "test", until: 0 })).toBe("Kid is playing Test. Spoilers.");
  });
});

describe("what a row says", () => {
  test("each game's result", () => {
    expect(resultWords(result({ timeMs: 125_000 }))).toBe("2:05");
    expect(resultWords(result({ timeMs: 3_725_000 }))).toBe("1:02:05");
    expect(resultWords(result({ game: "sniff", guesses: 4 }))).toBe("4 of 6");
    expect(resultWords(result({ game: "sniff", outcome: "missed", guesses: 6 }))).toBe("Missed");
    expect(resultWords(result({ game: "box-fort", outcome: "done", points: 1240 }))).toBe("1,240");
    expect(resultWords(result({ outcome: "gaveUp" }))).toBe("Gave up");
    expect(resultWords(result({ outcome: "closed" }))).toBe("Closed");
  });

  test("a long board shows four and counts the rest", () => {
    const rows = Array.from({ length: 9 }, (_, i) => ({ ...board.games[0]!.rows[0]!, player: `p${i}`, rank: i + 1 }));
    const shown = visibleRows({ ...board.games[0]!, rows });
    expect(shown.rows.map((r) => r.player)).toEqual(["p0", "p1", "p2", "p3"]);
    expect(shown.more).toBe(5);
    expect(visibleRows(board.games[0]!)).toEqual({ rows: board.games[0]!.rows, more: 0 });
  });
});

describe("the kept board token", () => {
  const DAY = 86_400_000;
  test("lasts 30 days", () => {
    const kept = boardToKeep("A".repeat(22), 0);
    expect(keptBoard(kept, 29 * DAY)).toBe("A".repeat(22));
    expect(keptBoard(kept, 30 * DAY + 1)).toBeNull();
  });

  test("anything else is nothing kept", () => {
    for (const raw of [null, "", "nope", "{}", '{"token":5,"until":9}', '{"token":"short","until":99999999999999}']) expect(keptBoard(raw, 0)).toBeNull();
  });
});

// The fixture's board is a valid `BoardAnswer`.
const _typed: BoardAnswer = board;
void _typed;
