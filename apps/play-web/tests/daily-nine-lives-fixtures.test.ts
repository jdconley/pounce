/**
 * The web player against the server's pinned wire samples (apps/play-api/fixtures/daily/protocol:
 * `nine-lives.json`, `client.json`, `http.json`): Nine Lives' lives rules decode and play as the
 * server answers them, and the run session's bodies have the shapes the server expects.
 */
import { describe, expect, test } from "vitest";

import client from "../../play-api/fixtures/daily/protocol/client.json";
import http from "../../play-api/fixtures/daily/protocol/http.json";
import nl from "../../play-api/fixtures/daily/protocol/nine-lives.json";
import { Run, startBody, type StartAnswer } from "../src/daily/client";
import { hasLives, isOut, reveal, revealSolution, start, wrongAt, type BoardState, type MoveReveal, type Puzzle } from "../src/daily/nine-lives/model";

import { Clock, flush } from "./fake-socket";

type NLStart = StartAnswer<Puzzle, BoardState>;
const nlStart = (s: unknown) => s as NLStart;

/** A run whose server answers with `answers`, in order, recording each body. */
function runOf(first: unknown, answers: unknown[]) {
  const clock = new Clock();
  clock.now = (first as NLStart).now;
  const bodies: unknown[] = [];
  const queue = [...answers];
  const call = async (_m: string, _p: string, body?: unknown) => {
    bodies.push(body);
    return new Response(JSON.stringify(queue.shift()), { status: 200 });
  };
  const run = new Run(first as NLStart, { call, person: "pe_1", now: () => clock.now, setTimer: clock.set, clearTimer: clock.clear });
  return { run, bodies, clock };
}

const keys = (o: unknown) => Object.keys(o as object).sort();

describe("Nine Lives' lives rules, as the server sends them", () => {
  test("a start without rules plays the first rules; one with them shows three lives and three hints", () => {
    const first = nlStart(nl.firstRules);
    expect(hasLives(start(first.puzzle, first.state))).toBe(false);
    expect(first.hintMs).toBe(30_000);
    const lives = nlStart(nl.start);
    const v = start(lives.puzzle, lives.state);
    expect([v.lives, v.hintsLeft]).toEqual([3, 3]);
    expect(lives.hintMs).toBe(0);
    expect(startBody("nine-lives")).toEqual(client.startLives);
  });

  test("a wrong number and a hint, played on, read the same as the resumed run", () => {
    const s = nlStart(nl.start);
    let v = start(s.puzzle, s.state);
    expect(nl.movesRight.reveals).toEqual([]);
    for (const r of nl.movesWrong.reveals as MoveReveal[]) v = wrongAt(v, r);
    v = reveal(v, nl.hint.reveals[0] as { i: number; d: number });
    const resumed = nlStart(nl.resumed);
    const back = start(resumed.puzzle, resumed.state);
    expect([v.lives, v.hintsLeft]).toEqual([back.lives, back.hintsLeft]);
    expect(v.wrong).toEqual(back.wrong);
    expect(v.hinted).toEqual(back.hinted);
  });

  test("out of lives: the last wrong reveal carries the solution, and a resume shows it", () => {
    const resumed = nlStart(nl.resumed);
    let v = start(resumed.puzzle, resumed.state);
    for (const r of nl.movesOutOfLives.reveals as MoveReveal[]) {
      v = wrongAt(v, r);
      if (r.solution) v = revealSolution(v, r.solution);
    }
    expect(isOut(v)).toBe(true);
    expect(v.lives).toBe(0);
    expect(nl.movesOutOfLives.result).toMatchObject({ outcome: "missed", percent: 2 });
    const out = nlStart(nl.resumedOutOfLives);
    const back = start(out.puzzle, out.state);
    expect(isOut(back)).toBe(true);
    expect(back.solution).toEqual(v.solution);
    // A wrong number in a cell a hint filled since doesn't show.
    expect(out.state.hinted).toContain(2);
    expect(back.wrong[2]).toBe(0);
  });

  test("a hint with none left is refused: no reveal, and no resync", async () => {
    const { run, bodies } = runOf(nl.resumed, [nl.hintNoneLeft]);
    expect(await run.hint()).toBeNull();
    expect(bodies).toHaveLength(1);
    // The resumed clock: its active time, and free hints.
    expect(nlStart(nl.resumed).activeMs).toBe(35_000);
    expect(runOf(nl.resumed, []).run.elapsedMs()).toBe(35_000);
  });
});

describe("the run session's bodies and clock, as the server pins them", () => {
  test("moves, hint and give up carry activeMs, in the shapes the server reads", async () => {
    const { run, bodies, clock } = runOf(http.resumed, [http.movesOk, { ...http.movesOk, reveals: [{ n: 1 }] }, { ...http.movesOk, result: { outcome: "gaveUp" } }]);
    run.setShown(true);
    clock.advance(1000);
    void run.send({ k: "step", n: 3 }, { urgent: true });
    await flush();
    await run.hint();
    await run.giveUp();
    expect(bodies.map(keys)).toEqual([keys(client.movesActive), keys(client.hintActive), keys(client.giveUpActive)]);
    expect(bodies.map((b) => (b as { activeMs: number }).activeMs)).toEqual([26_000, 26_000, 26_000]);
  });

  test("start's activeMs is where the clock carries on from", () => {
    expect(runOf(http.start, []).run.elapsedMs()).toBe(0);
    expect(runOf(http.resumed, []).run.elapsedMs()).toBe(25_000);
  });
});
