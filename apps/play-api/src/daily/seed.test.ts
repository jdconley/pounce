import { describe, expect, it } from "vitest";

import { addDays } from "../streaks/clock";

import { dailyKey, dailySeed, runId, seedOf } from "./seed";

import type { DailyGameId } from "./module";

const SECRET = "s".repeat(64);
const GAMES: DailyGameId[] = ["nine-lives", "box-fort", "sniff", "cat-nap"];

describe("dailySeed", () => {
  it("seed is stable", async () => {
    // Pinned on the first green run: a change here changes every day's puzzle for everyone.
    expect(await dailySeed(SECRET, "sniff", "2026-11-23")).toEqual(PINNED);
  });

  it("seeds differ by game and by date", async () => {
    const a = await dailySeed(SECRET, "sniff", "2026-11-23");
    expect(await dailySeed(SECRET, "nine-lives", "2026-11-23")).not.toEqual(a);
    expect(await dailySeed(SECRET, "sniff", "2026-11-24")).not.toEqual(a);
    expect(await dailySeed("t".repeat(64), "sniff", "2026-11-23")).not.toEqual(a);
  });

  it("seeds never repeat over 400 dates × 4 games", async () => {
    const seen = new Set<string>();
    for (let i = 0; i < 400; i++) {
      for (const game of GAMES) {
        const seed = await dailySeed(SECRET, game, addDays("2026-11-23", i));
        expect(seed).toHaveLength(4);
        for (const word of seed) expect(Number.isInteger(word) && word >= 0 && word < 2 ** 32).toBe(true);
        seen.add(seed.join(","));
      }
    }
    expect(seen.size).toBe(1600);
  });

  it("is HMAC-SHA256 over the spec's label with the HKDF key", async () => {
    const message = new TextEncoder().encode("daily.v1|sniff|2026-11-23");
    const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await dailyKey(SECRET), message));
    const view = new DataView(mac.buffer);
    expect(await dailySeed(SECRET, "sniff", "2026-11-23")).toEqual([0, 4, 8, 12].map((o) => view.getUint32(o)));
  });

  it("an all-zero MAC becomes [1, 0, 0, 0], which createRng accepts", () => {
    expect(seedOf(new ArrayBuffer(32))).toEqual([1, 0, 0, 0]);
  });

  it("derives the key once per secret", async () => {
    expect(await dailyKey(SECRET)).toBe(await dailyKey(SECRET));
  });
});

const PINNED = [3478374278, 3446170504, 1048556025, 1932777257];

describe("runId", () => {
  it("is the run's name HMAC'd with the daily key, base64url: unguessable, and the same every time", async () => {
    const id = await runId(SECRET, "p_abc", "sniff", "2026-11-23");
    expect(id).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(await runId(SECRET, "p_abc", "sniff", "2026-11-23")).toBe(id);
    expect(await runId(SECRET, "p_abd", "sniff", "2026-11-23")).not.toBe(id);
    expect(await runId(SECRET, "p_abc", "sniff", "2026-11-24")).not.toBe(id);
    expect(await runId(SECRET, "p_abc", "cat-nap", "2026-11-23")).not.toBe(id);
  });
});
