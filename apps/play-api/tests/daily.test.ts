import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, eventually, LA, mint, newPerson, profile, worker, type Device, type Person } from "./play-helpers";

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

async function start(options: { daily?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, { sent: [], trophy: true, daily: options.daily ?? true, dailyTest: true });
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
