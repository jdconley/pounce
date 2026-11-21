import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { bundle, call, mint, worker } from "./play-helpers";

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
