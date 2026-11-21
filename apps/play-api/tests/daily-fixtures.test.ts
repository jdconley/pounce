import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { addToStats, dish, rankGame, statsView, type BoardRow } from "../src/daily/board";
import { liveMessage, resultMessages, tvsMessage, type BoardAnswer } from "../src/daily/messages";
import { giveUp, moves, newRun, startView, useHint } from "../src/daily/run-core";
import { testGame } from "../src/daily/test-game";
import { createRng } from "../src/rules/rng";

import { BASE, bundle, call, eventually, mint, newPerson, profile, worker } from "./play-helpers";

import type { DailyModule, DailyResult } from "../src/daily/module";
import type { Miniflare } from "miniflare";

/**
 * Samples of everything the Daily Dish says and hears (docs/daily-protocol.md), for the clients to
 * decode: the app's PounceKit and the web player read these files by path. They are made by the
 * server's own code from fixed inputs, so they are the same on every run; a Miniflare test checks
 * that the real Worker's answers have exactly these shapes. New, so not pinned for 1.0; they are
 * pinned by hash in `fixtures-pinned.test.ts` so a change is deliberate. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/daily-fixtures.test.ts`.
 */
const write = process.env.UPDATE_FIXTURES === "1";
const DIR = new URL("../fixtures/daily/protocol/", import.meta.url);

function check(file: string, data: unknown): void {
  const path = new URL(file, DIR);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) {
    mkdirSync(DIR, { recursive: true });
    writeFileSync(path, text);
  }
  expect(readFileSync(path, "utf8")).toBe(text);
}

const m = testGame as DailyModule;
const LA = "America/Los_Angeles";
const DATE = "2026-11-23"; // a Monday: the test game counts to 4
const T0 = Date.UTC(2026, 10, 23, 20); // 12:00 in LA
const RUN = "Xq3vL0bNw8sJ2kT9yH4mR6pD1cF7gA5eZuWiOoKnBlM";
const PAIR = "pr_8tGqLm2vXc9RzK1wYb4NdA";
const step = (n: number) => ({ k: "step", n });

/** The HTTP answers, from the run referee and the board, at fixed times. */
function http() {
  const p = testGame.make(createRng([1, 2, 3, 4]), 1, { date: DATE, key: [1, 0, 0, 0] });
  const r = newRun(m, p, { id: RUN, playerId: "p_owner", game: "test", date: DATE, zone: LA, now: T0 });
  const start = startView(m, p, r, T0);
  const movesOk = moves(m, p, r, 0, [step(1), step(2)], T0 + 20_000);
  const resumed = startView(m, p, r, T0 + 25_000);
  const movesIllegal = moves(m, p, r, 2, [step(4)], T0 + 30_000);
  const movesStale = moves(m, p, r, 5, [step(3)], T0 + 31_000);
  const hint = useHint(m, p, r, T0 + 40_000);
  const movesSolved = moves(m, p, r, 2, [step(4)], T0 + 95_000);
  const movesOver = moves(m, p, r, 3, [step(5)], T0 + 96_000);
  const solved = r.result as DailyResult;

  const q = newRun(m, p, { id: RUN, playerId: "p_owner", game: "test", date: DATE, zone: LA, now: T0 });
  moves(m, p, q, 0, [step(1)], T0 + 10_000);
  const gaveUp = giveUp(m, p, q, T0 + 50_000);

  const rows: BoardRow[] = [
    { player: "me", name: "Mom", cat: 3, rank: null, result: solved, playing: null },
    { player: PAIR, name: "Kid", cat: 5, rank: null, result: q.result, playing: null },
    { player: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA", name: "Grandpa", cat: 1, rank: null, result: null, playing: { progress: 0.5 } },
  ];
  const games = [{ game: "test" as const, number: solved.number, rows: rankGame(m, rows) }];
  const board: BoardAnswer = { date: DATE, games, dish: dish(games), tvs: 1 };
  const stats = { games: { test: statsView(addToStats(null, solved), DATE) } };

  return {
    start,
    resumed,
    movesOk,
    movesSolved,
    movesIllegal,
    movesStale,
    movesOver,
    hint,
    gaveUp,
    board,
    stats,
    linked: { linked: true },
    errors: {
      notFound: { error: "not_found" },
      badRequest: { error: "bad_request" },
      noPlayer: { error: "no_player" },
      notAllowed: { error: "not_allowed" },
      rateLimited: { error: "rate_limited" },
      upgradeRequired: { error: "upgrade_required" },
    },
    solved,
  };
}

/** What the board socket says, from the same builders the player uses. */
function socket(h: ReturnType<typeof http>) {
  const face = { name: "Kid", cat: 5 };
  const [result, board] = resultMessages(PAIR, h.solved, h.board);
  return {
    board,
    result,
    progress: liveMessage(PAIR, face, { k: "progress", game: "test", date: DATE, progress: 0.5 }).message,
    watchOffer: liveMessage(PAIR, face, { k: "watchOffer", game: "test" }).message,
    watch: liveMessage(PAIR, face, { k: "watch", game: "test", state: { n: 2 } }).message,
    watchEnd: liveMessage(PAIR, face, { k: "watchEnd", game: "test", result: h.solved }).message,
    watchEndOff: liveMessage(PAIR, face, { k: "watchEnd", game: "test", result: null }).message,
    pong: { t: "pong" },
    error: { t: "error", error: "not_allowed" },
    linkBoard: { t: "board", token: "Qm9hcmRUb2tlbkV4YW1wbG" },
    tvs: tvsMessage(1),
  };
}

/** What clients send. */
const client = {
  moves: { from: 0, moves: [step(1), step(2)] },
  hint: { hints: 0 },
  tvOn: { on: true },
  tvOff: { on: false },
  linkBoardByToken: { token: "Tm90QVJlYWxMaW5rVG9rZW", board: true },
  linkBoardByCode: { code: "BCDFGH", board: true },
  ping: { t: "ping" },
};

test("the Daily Dish's samples match the committed files", () => {
  const h = http();
  const { solved, ...answers } = h;
  void solved;
  check("http.json", answers);
  check("socket.json", socket(h));
  check("client.json", client);
});

/** A value's shape: keys and the types under them, arrays by their first item. */
function shape(v: unknown): unknown {
  if (v === null) return "null";
  if (Array.isArray(v)) return v.length === 0 ? [] : [shape(v[0])];
  if (typeof v === "object") return Object.fromEntries(Object.keys(v as object).sort().map((k) => [k, shape((v as Record<string, unknown>)[k])]));
  return typeof v;
}

describe("the real Worker", () => {
  let script = "";
  const open: Miniflare[] = [];

  beforeAll(async () => {
    script = await bundle("./daily-entry.ts");
  });

  afterEach(async () => {
    await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  });

  test("answers in exactly the samples' shapes", async () => {
    const mf = await worker(script, { sent: [], trophy: true, daily: true, dailyTest: true });
    open.push(mf);
    const samples = JSON.parse(readFileSync(new URL("http.json", DIR), "utf8")) as Record<string, unknown>;
    const device = await mint(mf);
    const mom = newPerson("Mom", 3);
    await profile(mf, device, [mom]);
    const q = `?person=${mom.id}`;
    const start = (await (await call(mf, device, "POST", `/v1/daily/test/start${q}`)).json()) as { run: string; level: number };
    expect(shape(start)).toEqual(shape(samples.start));
    const ok = await (await call(mf, device, "POST", `/v1/daily/runs/${start.run}/moves${q}`, { from: 0, moves: [step(1), step(2)] })).json();
    expect(shape(ok)).toEqual(shape(samples.movesOk));
    const illegal = await (await call(mf, device, "POST", `/v1/daily/runs/${start.run}/moves${q}`, { from: 2, moves: [step(9)] })).json();
    expect(shape(illegal)).toEqual(shape(samples.movesIllegal));
    const solved = await (await call(mf, device, "POST", `/v1/daily/runs/${start.run}/moves${q}`, { from: 2, moves: Array.from({ length: start.level + 1 }, (_, i) => step(3 + i)) })).json();
    expect(shape(solved)).toEqual(shape(samples.movesSolved));
    const board = await eventually(
      async () => (await (await call(mf, device, "GET", `/v1/daily/board${q}`)).json()) as { games: { rows: unknown[] }[] },
      (b) => (b.games[0]?.rows.length ?? 0) > 0,
    );
    const sampleBoard = samples.board as { games: { rows: unknown[] }[] };
    expect(shape(board.games[0]?.rows[0])).toEqual(shape(sampleBoard.games[0]?.rows[0]));
    expect(shape({ ...board, games: [] })).toEqual(shape({ ...sampleBoard, games: [] }));
    const stats = await (await call(mf, device, "GET", `/v1/daily/stats${q}`)).json();
    expect(shape(stats)).toEqual(shape(samples.stats));
    expect((await mf.dispatchFetch(`${BASE}/healthz`)).status).toBe(200);
  });
});
