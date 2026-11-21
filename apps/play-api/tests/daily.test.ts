import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, mint, worker } from "./play-helpers";

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
