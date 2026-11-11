import { setFlagsFromString } from "node:v8";
import { runInNewContext } from "node:vm";

import { afterAll, beforeAll, describe, expect, test } from "vitest";

import { bundle, call, mint, newPerson, worker } from "./play-helpers";

import type { Miniflare } from "miniflare";

setFlagsFromString("--expose-gc");
const gc = runInNewContext("gc") as () => void;

/** Collects garbage and lets the finalizers that follow it run. */
async function collect(): Promise<void> {
  for (let i = 0; i < 5; i += 1) {
    gc();
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

let mf: Miniflare;

beforeAll(async () => {
  mf = await worker(await bundle("./pounce-entry.ts"), { sent: [] });
});

afterAll(async () => {
  await mf.dispose();
});

describe("call", { timeout: 30_000 }, () => {
  // Miniflare wraps undici's response and drops the original; undici cancels a body nobody has
  // started reading once that original is collected. A test that makes another request before
  // reading the first one's body then fails with "Body has already been read", now and then.
  test("a response's body is still there after a garbage collection", async () => {
    const device = await mint(mf);
    const mia = newPerson("Mia", 2);
    const res = await call(mf, device, "PUT", "/v1/devices/me/profile", { timeZone: "America/Los_Angeles", ageBand: "adult", people: [mia] });
    await collect();
    const body = (await res.json()) as { players: Record<string, string> };
    expect(body.players[mia.id]).toMatch(/^p_/);
  });

  test("a response without a body comes back as it is", async () => {
    const device = await mint(mf);
    const res = await call(mf, device, "PUT", "/v1/devices/me/push", { apnsToken: "a".repeat(64) });
    expect(res.status).toBe(204);
    expect(res.body).toBeNull();
  });
});
