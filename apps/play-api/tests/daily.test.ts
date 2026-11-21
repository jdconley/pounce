import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { addDays, localToInstant } from "../src/streaks/clock";

import { BASE, bundle, call, eventually, LA, mint, newPerson, PLAYER_ID_JSON, profile, tokenOf, worker, type Device, type Person, type Sent } from "./play-helpers";


import type { Miniflare } from "miniflare";

/** The Daily Dish through the Worker and its Durable Objects (spec §3). */
let script = "";
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./daily-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

async function start(options: { daily?: boolean; sent?: Sent[] } = {}): Promise<Miniflare> {
  const mf = await worker(script, { sent: options.sent ?? [], trophy: true, daily: options.daily ?? true, dailyTest: true });
  open.push(mf);
  return mf;
}

describe("the DAILY flag", () => {
  test("every /v1/daily route is a 404 with DAILY off", async () => {
    const mf = await start({ daily: false });
    const device = await mint(mf);
    for (const [method, path] of [
      ["POST", "/v1/daily/sniff/start"],
      ["POST", "/v1/daily/test/start"],
      ["POST", "/v1/daily/runs/x/moves"],
      ["GET", "/v1/daily/board"],
      ["GET", "/v1/daily/board/ws"],
    ] as const) {
      const res = await call(mf, device, method, path);
      expect(res.status, `${method} ${path}`).toBe(404);
    }
  });
});

describe("DailyPuzzle", () => {
  const read = async (mf: Miniflare, game: string, date: string) =>
    (await mf.dispatchFetch(`${BASE}/__test/puzzle?game=${game}&date=${date}`)).json();

  test("the same game and date give the same puzzle from two isolates", async () => {
    const [a, b] = [await start(), await start()];
    const first = await read(a, "test", "2026-11-23");
    expect(first).toEqual({ target: 4 });
    expect(await read(b, "test", "2026-11-23")).toEqual(first);
    expect(await read(a, "test", "2026-11-23")).toEqual(first);
  });

  test("different dates give different puzzles", async () => {
    const mf = await start();
    // The test game's puzzle is its level: Monday 4, Tuesday 5.
    expect(await read(mf, "test", "2026-11-23")).toEqual({ target: 4 });
    expect(await read(mf, "test", "2026-11-24")).toEqual({ target: 5 });
  });

  test("its alarm makes the next date's puzzle ahead of time", async () => {
    const mf = await start();
    const res = await mf.dispatchFetch(`${BASE}/__test/puzzle-warm?game=test&date=2026-11-23`);
    expect(await res.json()).toEqual({ next: true });
  });
});

/** A device with one person on it; returns the device, the person and their player id. */
async function someone(mf: Miniflare, name = "Mom", zone = LA): Promise<{ device: Device; person: Person; id: string }> {
  const device = await mint(mf);
  const person = newPerson(name, 3);
  const ids = await profile(mf, device, [person], { zone });
  return { device, person, id: ids[person.id] as string };
}

type Start = {
  run: string;
  game: string;
  date: string;
  number: number;
  level: number;
  startedAt: number;
  now: number;
  puzzle: unknown;
  state: unknown;
  seq: number;
  hints: number;
  result: Record<string, unknown> | null;
  closesAt: number;
};

const startRun = async (mf: Miniflare, device: Device, person: Person, game = "test"): Promise<Response> =>
  call(mf, device, "POST", `/v1/daily/${game}/start?person=${person.id}`);
const begin = async (mf: Miniflare, device: Device, person: Person): Promise<Start> => {
  const res = await startRun(mf, device, person);
  expect(res.status).toBe(200);
  return (await res.json()) as Start;
};
const send = async (mf: Miniflare, device: Device, person: Person, run: string, body: unknown) =>
  call(mf, device, "POST", `/v1/daily/runs/${run}/moves?person=${person.id}`, body);
const steps = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => ({ k: "step", n: from + i }));

/** A start at a made-up now, through the test hook. */
async function startAt(mf: Miniflare, playerId: string, now: number): Promise<Start> {
  const res = await mf.dispatchFetch(`${BASE}/__test/start?player=${playerId}&game=test&now=${now}`);
  expect(res.status).toBe(200);
  return (await res.json()) as Start;
}

describe("runs", () => {
  test("start then solve, the result is the server's", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const s = await begin(mf, device, person);
    expect(s).toMatchObject({ game: "test", seq: 0, hints: 0, result: null, state: { n: 0 } });
    expect(s.run).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(s.puzzle).toEqual({ target: 3 + s.level });
    expect(s.closesAt).toBeGreaterThan(s.now);
    expect(Math.abs(s.now - Date.now())).toBeLessThan(5000);
    const target = 3 + s.level;
    const first = await send(mf, device, person, s.run, { from: 0, moves: steps(1, target - 1) });
    expect(await first.json()).toMatchObject({ ok: true, seq: target - 1, result: null });
    const res = await send(mf, device, person, s.run, { from: target - 1, moves: steps(target, target) });
    expect(res.status).toBe(200);
    const done = (await res.json()) as { ok: true; result: Record<string, unknown> };
    expect(done.result).toMatchObject({ game: "test", date: s.date, outcome: "solved", hints: 0, tooFast: false, progress: 1 });
    expect(done.result.timeMs).toBeGreaterThanOrEqual(0);
    expect(done.result.timeMs).toBeLessThan(10_000);
    // Starting again shows the ended run.
    expect(await begin(mf, device, person)).toMatchObject({ run: s.run, seq: target, result: done.result, state: { n: target } });
  });

  test("a second start returns the same run and startedAt", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const a = await begin(mf, device, person);
    await send(mf, device, person, a.run, { from: 0, moves: steps(1, 2) });
    const b = await begin(mf, device, person);
    expect(b).toMatchObject({ run: a.run, startedAt: a.startedAt, seq: 2, state: { n: 2 } });
  });

  test("two devices of one player get one run", async () => {
    const mf = await start();
    const { device, person, id } = await someone(mf);
    const other = await mint(mf);
    expect((await profile(mf, other, [person]))[person.id]).toBe(id);
    const [a, b] = await Promise.all([begin(mf, device, person), begin(mf, other, person)]);
    expect(b.run).toBe(a.run);
    expect(b.startedAt).toBe(a.startedAt);
  });

  test("someone else's run is a 404", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    const s = await begin(mf, mom.device, mom.person);
    for (const [method, action, body] of [["POST", "moves", { from: 0, moves: steps(1, 1) }], ["POST", "hint", undefined], ["POST", "giveup", undefined], ["PUT", "tv", { on: true }]] as const) {
      const res = await call(mf, kid.device, method, `/v1/daily/runs/${s.run}/${action}?person=${kid.person.id}`, body);
      expect(res.status, action).toBe(404);
    }
    // A run id that never was says the same.
    const made = await send(mf, mom.device, mom.person, "A".repeat(43), { from: 0, moves: [] });
    expect(made.status).toBe(404);
    expect((await begin(mf, mom.device, mom.person)).seq).toBe(0);
  });

  test("a device that doesn't speak for the person gets a 403", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const stranger = await mint(mf);
    expect((await startRun(mf, stranger, mom.person)).status).toBe(403);
    // No person and no account: nobody to play as.
    expect((await call(mf, stranger, "POST", "/v1/daily/test/start")).status).toBe(404);
    expect((await call(mf, stranger, "POST", "/v1/daily/test/start?person=nope")).status).toBe(400);
  });

  test("an unknown or unlisted game is a 404", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    expect((await startRun(mf, device, person, "chess")).status).toBe(404);
    expect((await startRun(mf, device, person, "sniff")).status).toBe(404);
  });

  test("a posted result field is ignored and the run is unchanged", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const s = await begin(mf, device, person);
    const forged = { game: "test", date: s.date, number: 1, outcome: "solved", timeMs: 1, hints: 0, tooFast: false, progress: 1 };
    const res = await send(mf, device, person, s.run, { from: 0, moves: [], result: forged, timeMs: 1 });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, seq: 0, reveals: [], progress: 0, result: null });
    expect(await begin(mf, device, person)).toMatchObject({ seq: 0, state: { n: 0 }, result: null });
  });

  test("a malformed body is a 400", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const s = await begin(mf, device, person);
    for (const body of [{ moves: [] }, { from: -1, moves: [] }, { from: 0.5, moves: [] }, { from: 0 }, [1]]) {
      expect((await send(mf, device, person, s.run, body)).status, JSON.stringify(body)).toBe(400);
    }
    // Over the 8 KB cap: refused before the referee sees it.
    expect((await send(mf, device, person, s.run, { from: 0, moves: steps(1, 500) })).status).toBe(400);
    // Under the cap but over 100 moves: the referee's bad_message.
    const many = await send(mf, device, person, s.run, { from: 0, moves: steps(1, 101) });
    expect(await many.json()).toEqual({ ok: false, error: "bad_message", at: 0, seq: 0 });
  });

  test("hints and giving up are answered by the referee", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const s = await begin(mf, device, person);
    const hint = await call(mf, device, "POST", `/v1/daily/runs/${s.run}/hint?person=${person.id}`);
    expect(await hint.json()).toMatchObject({ ok: true, seq: 0, reveals: [{ n: 1 }] });
    await send(mf, device, person, s.run, { from: 0, moves: steps(2, 2) });
    const up = await call(mf, device, "POST", `/v1/daily/runs/${s.run}/giveup?person=${person.id}`);
    expect(await up.json()).toMatchObject({ ok: true, result: { outcome: "gaveUp", hints: 1 } });
    const tv = await call(mf, device, "PUT", `/v1/daily/runs/${s.run}/tv?person=${person.id}`, { on: true });
    expect(tv.status).toBe(204);
    expect((await call(mf, device, "PUT", `/v1/daily/runs/${s.run}/tv?person=${person.id}`, { on: "yes" })).status).toBe(400);
  });

  test("tomorrow can't be started", async () => {
    const mf = await start();
    const { id } = await someone(mf);
    // 03:59 in LA on the 25th is still the 24th's day.
    const s = await startAt(mf, id, Date.UTC(2026, 10, 25, 11, 59));
    expect(s.date).toBe("2026-11-24");
    expect(s.level).toBe(2);
    const t = await startAt(mf, id, Date.UTC(2026, 10, 25, 12, 0));
    expect(t.date).toBe("2026-11-25");
    expect(t.run).not.toBe(s.run);
  });

  test("a run closes at 04:00 by alarm", async () => {
    const mf = await start();
    const { id } = await someone(mf);
    // A run started on a day long over: its alarm is already due.
    const s = await startAt(mf, id, Date.UTC(2026, 10, 2, 20));
    const closed = await eventually(
      async () => (await (await mf.dispatchFetch(`${BASE}/__test/run?id=${s.run}`)).json()) as { ended: { outcome: string; at: number } | null; result: { outcome: string } | null },
      (r) => r.ended !== null,
    );
    expect(closed.ended).toEqual({ outcome: "closed", at: s.closesAt });
    expect(closed.result).toMatchObject({ outcome: "closed", progress: 0 });
  });

  test("the start limit answers 429", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    for (let i = 0; i < 30; i++) expect((await startRun(mf, device, person)).status).toBe(200);
    expect((await startRun(mf, device, person)).status).toBe(429);
  });

  test("the move limit answers 429", async () => {
    const mf = await start();
    const { device, person } = await someone(mf);
    const s = await begin(mf, device, person);
    const answers = await Promise.all(Array.from({ length: 24 }, () => send(mf, device, person, s.run, { from: 0, moves: [] })));
    expect(answers.map((r) => r.status)).toContain(429);
  });
});

type Board = {
  date: string;
  games: { game: string; number: number; rows: { player: string; name: string; cat: number; rank: number | null; result: Record<string, unknown> | null; playing: unknown }[] }[];
  dish: { rows: { player: string; name: string; points: number; crowns: string[]; ended: number; rank: number }[] };
};

/** Pairs two players, as an accepted invite does. */
async function pairUp(mf: Miniflare, a: string, b: string): Promise<void> {
  expect((await mf.dispatchFetch(`${BASE}/__test/connect?a=${a}&b=${b}`)).status).toBe(204);
}

/** Plays today's test game to the end. */
async function solve(mf: Miniflare, device: Device, person: Person): Promise<Record<string, unknown>> {
  const s = await begin(mf, device, person);
  const res = await send(mf, device, person, s.run, { from: 0, moves: steps(1, 3 + s.level) });
  return ((await res.json()) as { result: Record<string, unknown> }).result;
}

const boardOf = async (mf: Miniflare, device: Device, person: Person, query = ""): Promise<Board> => {
  const res = await call(mf, device, "GET", `/v1/daily/board?person=${person.id}${query}`);
  expect(res.status).toBe(200);
  return (await res.json()) as Board;
};

describe("the board", () => {
  test("a connection's result appears on my board", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    const result = await solve(mf, kid.device, kid.person);
    const board = await eventually(() => boardOf(mf, mom.device, mom.person), (b) => (b.games[0]?.rows.length ?? 0) > 0);
    expect(board.date).toBe(result.date);
    const test = board.games.find((g) => g.game === "test");
    expect(test?.rows).toEqual([{ player: expect.stringMatching(/^pr_/) as string, name: "Kid", cat: 3, rank: 1, result, playing: null }]);
    expect(board.dish.rows).toMatchObject([{ name: "Kid", points: 4, crowns: ["test"], ended: 1, rank: 1 }]);
    // No player ids leave the server.
    expect(JSON.stringify(board)).not.toMatch(PLAYER_ID_JSON);
    // Mom plays too, slower: both on both boards, Mom as "me" on her own.
    await solve(mf, mom.device, mom.person);
    const both = await eventually(() => boardOf(mf, kid.device, kid.person), (b) => (b.games[0]?.rows.length ?? 0) === 2);
    expect(both.games[0]?.rows.map((r) => r.name)).toHaveLength(2);
    const mine = await boardOf(mf, mom.device, mom.person);
    expect(mine.games[0]?.rows.map((r) => r.player)).toContain("me");
  });

  test("someone I'm not paired with never appears", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const stranger = await someone(mf, "Stranger");
    await solve(mf, stranger.device, stranger.person);
    await new Promise((resolve) => setTimeout(resolve, 300));
    const board = await boardOf(mf, mom.device, mom.person);
    expect(board.games.flatMap((g) => g.rows)).toEqual([]);
    expect(board.dish.rows).toEqual([]);
  });

  test("a pair that is left drops off from the next read", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    await solve(mf, kid.device, kid.person);
    const board = await eventually(() => boardOf(mf, mom.device, mom.person), (b) => (b.games[0]?.rows.length ?? 0) > 0);
    const pair = board.games[0]?.rows[0]?.player as string;
    expect((await call(mf, mom.device, "DELETE", `/v1/pairs/${pair}?person=${mom.person.id}`)).status).toBe(204);
    expect((await boardOf(mf, mom.device, mom.person)).games[0]?.rows).toEqual([]);
  });

  test("nobody who hasn't played appears", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    // Kid started but never played a move, and Mom never started.
    await begin(mf, kid.device, kid.person);
    const board = await boardOf(mf, mom.device, mom.person);
    expect(board.games.map((g) => g.game)).toEqual(["test"]);
    expect(board.games[0]?.rows).toEqual([]);
    expect(board.dish.rows).toEqual([]);
  });

  test("results past 120 days are gone", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    // A run 100 days ago, closed by its alarm at once.
    const old = Date.now() - 100 * 86_400_000;
    const s = await startAt(mf, mom.id, old);
    const read = async (now: number) =>
      (await (await mf.dispatchFetch(`${BASE}/__test/board?player=${mom.id}&date=${s.date}&now=${now}`)).json()) as Board;
    const kept = await eventually(() => read(Date.now()), (b) => (b.games[0]?.rows.length ?? 0) > 0);
    expect(kept.games[0]?.rows[0]?.result).toMatchObject({ outcome: "closed" });
    // 30 days on, it is 130 days old.
    expect((await read(Date.now() + 30 * 86_400_000)).games[0]?.rows).toEqual([]);
  });

  test("the board route takes today or the past 120 days", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const today = (await boardOf(mf, mom.device, mom.person)).date;
    expect((await boardOf(mf, mom.device, mom.person, `&date=${today}`)).date).toBe(today);
    const day = (n: number) => new Date(Date.parse(`${today}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
    expect((await boardOf(mf, mom.device, mom.person, `&date=${day(-120)}`)).date).toBe(day(-120));
    for (const bad of [day(1), day(-121), "2026-13-01", "yesterday"]) {
      expect((await call(mf, mom.device, "GET", `/v1/daily/board?person=${mom.person.id}&date=${bad}`)).status, bad).toBe(400);
    }
  });

  test("stats count my own ended runs, per game", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const result = await solve(mf, mom.device, mom.person);
    const read = async () => (await (await call(mf, mom.device, "GET", `/v1/daily/stats?person=${mom.person.id}`)).json()) as { games: Record<string, Record<string, unknown>> };
    const stats = await eventually(read, (s) => s.games.test?.played === 1);
    expect(stats.games.test).toMatchObject({ played: 1, solved: 1, streak: 1, best: 1, bestTimeMs: result.timeMs, last30: [{ date: result.date, result }] });
  });
});

describe("streaks count daily runs", () => {
  type Streaks = { own?: { count: number; kept: boolean }; pairs: { count: number; me: boolean; them: boolean }[] };
  const streaksOf = async (mf: Miniflare, d: Device, p: Person) => (await (await call(mf, d, "GET", `/v1/me/streaks?person=${p.id}`)).json()) as Streaks;

  test("your own streak counts a daily run", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    await solve(mf, mom.device, mom.person);
    const list = await eventually(() => streaksOf(mf, mom.device, mom.person), (l) => l.own?.count === 1);
    expect(list.own).toMatchObject({ count: 1, kept: true });
  });

  test("two connections who each end a daily run keep their shared day", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    await solve(mf, mom.device, mom.person);
    const half = await eventually(() => streaksOf(mf, kid.device, kid.person), (l) => l.pairs[0]?.them === true);
    expect(half.pairs[0]).toMatchObject({ count: 0, me: false, them: true });
    await solve(mf, kid.device, kid.person);
    const kept = await eventually(() => streaksOf(mf, mom.device, mom.person), (l) => l.pairs[0]?.count === 1);
    expect(kept.pairs[0]).toMatchObject({ count: 1, me: true, them: true });
  });

  test("a run given up with no moves doesn't count", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const s = await begin(mf, mom.device, mom.person);
    await call(mf, mom.device, "POST", `/v1/daily/runs/${s.run}/giveup?person=${mom.person.id}`);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect((await streaksOf(mf, mom.device, mom.person)).own).toMatchObject({ count: 0, kept: false });
  });

  test("DAILY off: reportDaily is never called", async () => {
    const mf = await start({ daily: false });
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    for (const p of [mom, kid]) expect((await mf.dispatchFetch(`${BASE}/__test/record?player=${p.id}`)).status).toBe(204);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(await streaksOf(mf, mom.device, mom.person)).toMatchObject({ own: { count: 0 }, pairs: [{ count: 0, me: false, them: false }] });
  });
});

describe("the daily reminder knows the Dish", () => {
  const remindAt = async (mf: Miniflare, playerId: string, now: number) =>
    expect((await mf.dispatchFetch(`${BASE}/__test/remind?player=${playerId}&now=${now}`)).status).toBe(204);
  const tomorrowAt1930 = () => {
    const today = new Date(Date.now() - 4 * 3_600_000).toLocaleDateString("en-CA", { timeZone: LA });
    return localToInstant(addDays(today, 1), 19 * 60 + 30, LA);
  };

  test("with no move waiting, the reminder names today's first game", async () => {
    const sent: Sent[] = [];
    const mf = await start({ sent });
    const device = await mint(mf);
    const mom = newPerson("Mom", 3);
    const id = (await profile(mf, device, [mom], { apns: tokenOf(1) }))[mom.id] as string;
    await remindAt(mf, id, tomorrowAt1930());
    const pushes = await eventually(() => sent.filter((s) => s.body.kind === "reminder"), (l) => l.length >= 1);
    expect(pushes).toHaveLength(1);
    const alert = (pushes[0]?.body.aps as { alert: { title: string; body: string } }).alert;
    expect(alert).toMatchObject({ title: "Mom" });
    expect(alert.body).toMatch(/^Today's Dish is out\. Test -?\d+ is waiting\.$/);
  });

  test("DAILY off: no Dish, so nothing", async () => {
    const sent: Sent[] = [];
    const mf = await start({ sent, daily: false });
    const device = await mint(mf);
    const mom = newPerson("Mom", 3);
    const id = (await profile(mf, device, [mom], { apns: tokenOf(2) }))[mom.id] as string;
    await remindAt(mf, id, tomorrowAt1930());
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(sent.filter((s) => s.body.kind === "reminder")).toEqual([]);
  });
});
