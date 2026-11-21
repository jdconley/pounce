import { describe, expect, test } from "vitest";

import { Run, type RunEvent, type StartAnswer } from "../src/daily/client";
import { ApiError } from "../src/net/api";

import { Clock, flush } from "./fake-socket";

import type { TestMove, TestState } from "@pounce/play-api/daily/test-game";

type Call = { method: string; path: string; body?: unknown };
type Answer = unknown | Error;

const START: StartAnswer<{ target: number }, TestState> = {
  run: "R".repeat(43),
  game: "test",
  date: "2026-11-23",
  number: 12,
  level: 1,
  startedAt: 1_000_000,
  now: 1_005_000,
  puzzle: { target: 4 },
  state: { n: 0 },
  seq: 0,
  hints: 0,
  result: null,
  closesAt: 9_000_000,
};

const step = (n: number): TestMove => ({ k: "step", n });
const ok = (seq: number, extra: object = {}) => ({ ok: true, seq, reveals: [], progress: seq / 4, result: null, ...extra });
const solved = { game: "test", date: "2026-11-23", number: 12, outcome: "solved", timeMs: 9000, hints: 0, progress: 1, tooFast: false };

/** A run whose server is a list of answers the test hands out, in order, as calls arrive. */
function setup(answers: Answer[] = [], start = START) {
  const clock = new Clock();
  clock.now = 1_000_000; // the device's clock is 5 s behind the server's
  const calls: Call[] = [];
  const queue = [...answers];
  const call = async (method: string, path: string, body?: unknown) => {
    calls.push({ method, path, body });
    const a = queue.shift();
    if (a === undefined) throw new Error(`no answer for ${method} ${path}`);
    if (a instanceof Error) throw a;
    return new Response(JSON.stringify(a), { status: 200 });
  };
  const run = new Run(start, { call, person: "pe_1", now: () => clock.now, setTimer: clock.set, clearTimer: clock.clear });
  const events: RunEvent<TestState, unknown>[] = [];
  run.subscribe((e) => events.push(e));
  return { clock, calls, run, events, answer: (...more: Answer[]) => queue.push(...more) };
}

const MOVES = `/v1/daily/runs/${"R".repeat(43)}/moves?person=pe_1`;

describe("the run session", () => {
  test("batches moves at most once a second", async () => {
    const { clock, calls, run } = setup([ok(2)]);
    void run.send(step(1));
    void run.send(step(2));
    clock.advance(999);
    await flush();
    expect(calls).toEqual([]);
    clock.advance(1);
    await flush();
    expect(calls).toEqual([{ method: "POST", path: MOVES, body: { from: 0, moves: [step(1), step(2)] } }]);
  });

  test("an urgent move goes at once, with what waits, and resolves with the batch's last reveal", async () => {
    const { calls, run, events } = setup([ok(2, { reveals: [{ a: 1 }, { b: 2 }] })]);
    void run.send(step(1));
    const reveal = run.send(step(2), { urgent: true });
    await flush();
    expect(calls).toHaveLength(1);
    expect(calls[0]!.body).toEqual({ from: 0, moves: [step(1), step(2)] });
    expect(await reveal).toEqual({ b: 2 });
    expect(events).toContainEqual({ kind: "accepted", seq: 2, reveals: [{ a: 1 }, { b: 2 }], progress: 0.5 });
  });

  test("one batch in flight: moves sent meanwhile go next, from the answer's seq", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const { clock, calls, run } = setup();
    const answers = [ok(1), ok(3)];
    (run as unknown as { deps: { call: unknown } }).deps.call = async (method: string, path: string, body?: unknown) => {
      calls.push({ method, path, body });
      if (calls.length === 1) await gate;
      return new Response(JSON.stringify(answers.shift()), { status: 200 });
    };
    void run.send(step(1), { urgent: true });
    await flush();
    void run.send(step(2));
    void run.send(step(3), { urgent: true });
    await flush();
    expect(calls).toHaveLength(1);
    release();
    await flush();
    await flush();
    clock.advance(0);
    await flush();
    expect(calls[1]!.body).toEqual({ from: 1, moves: [step(2), step(3)] });
  });

  test("resends the same from after a dropped connection", async () => {
    const { clock, calls, run, events } = setup([new ApiError(0, "offline"), ok(1)]);
    const reveal = run.send(step(1), { urgent: true });
    await flush();
    expect(events).toContainEqual({ kind: "link", status: "retrying" });
    clock.advance(250);
    await flush();
    expect(calls.map((c) => c.body)).toEqual([
      { from: 0, moves: [step(1)] },
      { from: 0, moves: [step(1)] },
    ]);
    expect(await reveal).toBeNull();
    expect(events).toContainEqual({ kind: "link", status: "ok" });
  });

  test("too_soon waits, then resends from seq", async () => {
    const { clock, calls, run } = setup([{ ok: false, error: "too_soon", at: 0, seq: 0 }, ok(1)]);
    void run.send(step(1), { urgent: true });
    await flush();
    clock.advance(500);
    await flush();
    expect(calls.map((c) => c.body)).toEqual([
      { from: 0, moves: [step(1)] },
      { from: 0, moves: [step(1)] },
    ]);
  });

  test("illegal sends the legal moves before it, then takes the server's state", async () => {
    const { calls, run, events } = setup([
      { ok: false, error: "illegal", at: 1, seq: 0 },
      ok(1),
      { ...START, seq: 1, state: { n: 1 } },
    ]);
    void run.send(step(1));
    const second = run.send(step(5), { urgent: true });
    await flush();
    await flush();
    await flush();
    expect(calls.map((c) => [c.path.split("?")[0]!.split("/").at(-1), c.body])).toEqual([
      ["moves", { from: 0, moves: [step(1), step(5)] }],
      ["moves", { from: 0, moves: [step(1)] }],
      ["start", undefined],
    ]);
    expect(await second).toBeNull();
    expect(events).toContainEqual({ kind: "resync", state: { n: 1 }, seq: 1 });
  });

  test("stale and over take the server's state, and its result", async () => {
    const { run, events } = setup([{ ok: false, error: "over", at: 0, seq: 4 }, { ...START, seq: 4, state: { n: 4 }, result: solved }]);
    void run.send(step(1), { urgent: true });
    await flush();
    await flush();
    await flush();
    expect(events).toContainEqual({ kind: "resync", state: { n: 4 }, seq: 4 });
    expect(events).toContainEqual({ kind: "result", result: solved });
    expect(run.result).toEqual(solved);
  });

  test("a batch that ends the run brings its result", async () => {
    const { run, events } = setup([ok(4, { result: solved, progress: 1 })]);
    void run.send(step(1), { urgent: true });
    await flush();
    expect(events.at(-1)).toEqual({ kind: "result", result: solved });
  });

  test("hint flushes waiting moves first, then counts the hint", async () => {
    const { calls, run, events } = setup([ok(1), ok(1, { reveals: [{ n: 2 }] })]);
    void run.send(step(1));
    const reveal = await run.hint();
    expect(calls.map((c) => c.path.split("?")[0]!.split("/").at(-1))).toEqual(["moves", "hint"]);
    expect(reveal).toEqual({ n: 2 });
    expect(run.hints).toBe(1);
    expect(events).toContainEqual({ kind: "hint", reveal: { n: 2 }, hints: 1 });
  });

  test("giveUp flushes, then ends the run", async () => {
    const gaveUp = { ...solved, outcome: "gaveUp", progress: 0.25 };
    const { calls, run, events } = setup([ok(1), ok(1, { result: gaveUp })]);
    void run.send(step(1));
    expect(await run.giveUp()).toEqual(gaveUp);
    expect(calls.map((c) => c.path.split("?")[0]!.split("/").at(-1))).toEqual(["moves", "giveup"]);
    expect(events.at(-1)).toEqual({ kind: "result", result: gaveUp });
  });

  test("the clock is the server's, plus 30 seconds a hint", async () => {
    const { clock, run } = setup([ok(0, { reveals: [{ n: 1 }] })]);
    expect(run.serverNow()).toBe(1_005_000);
    expect(run.elapsedMs()).toBe(5000);
    clock.advance(2000);
    expect(run.elapsedMs()).toBe(7000);
    await run.hint();
    expect(run.elapsedMs()).toBe(37_000);
  });

  test("a batch holds at most 100 moves", async () => {
    const { clock, calls, run, answer } = setup([ok(100)]);
    for (let i = 1; i <= 130; i++) void run.send(step(i));
    clock.advance(1000);
    await flush();
    expect((calls[0]!.body as { moves: unknown[] }).moves).toHaveLength(100);
    answer(ok(130));
    clock.advance(1000);
    await flush();
    expect(calls[1]!.body).toMatchObject({ from: 100 });
    expect((calls[1]!.body as { moves: unknown[] }).moves).toHaveLength(30);
  });
});
