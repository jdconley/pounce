import { describe, expect, it } from "vitest";

import { DEVICE_JOIN_RULE, IP_JOIN_RULE, lockedUntil, miss, take, type Misses } from "./backoff";

const rule = { free: 2, baseMs: 1000, maxMs: 8000, forgetMs: 60_000 };

describe("miss", () => {
  it("lets the free misses through, then doubles the lockout up to the cap", () => {
    let m: Misses | null = null;
    const locks: number[] = [];
    for (let i = 0; i < 8; i++) {
      m = miss(m, 100, rule);
      locks.push(m.lockedUntil === 0 ? 0 : m.lockedUntil - 100);
    }
    expect(locks).toEqual([0, 0, 1000, 2000, 4000, 8000, 8000, 8000]);
    expect((m as Misses).count).toBe(8);
  });

  it("forgets after a quiet spell", () => {
    let m = miss(miss(miss(null, 0, rule), 1, rule), 2, rule);
    expect(m.lockedUntil).toBe(1002);
    m = miss(m, 2 + 60_000, rule);
    expect(m).toEqual({ count: 1, last: 60_002, lockedUntil: 0 });
  });

  it("never overflows however many misses", () => {
    let m: Misses | null = null;
    for (let i = 0; i < 2000; i++) m = miss(m, 5, rule);
    expect((m as Misses).lockedUntil).toBe(8005);
  });

  it("an address gets more free misses than one device", () => {
    expect(IP_JOIN_RULE.free).toBeGreaterThan(DEVICE_JOIN_RULE.free);
  });
});

describe("lockedUntil", () => {
  it("is the lock's end while it lasts", () => {
    expect(lockedUntil(null, 0)).toBeNull();
    expect(lockedUntil({ count: 3, last: 0, lockedUntil: 1000 }, 999)).toBe(1000);
    expect(lockedUntil({ count: 3, last: 0, lockedUntil: 1000 }, 1000)).toBeNull();
    expect(lockedUntil({ count: 1, last: 0, lockedUntil: 0 }, 0)).toBeNull();
  });
});

describe("take", () => {
  it("allows max takes per window, then a fresh window", () => {
    let w = take(null, 0, 2, 1000);
    expect(w).toEqual({ window: { count: 1, start: 0 }, ok: true });
    w = take(w.window, 10, 2, 1000);
    expect(w.ok).toBe(true);
    w = take(w.window, 20, 2, 1000);
    expect(w).toEqual({ window: { count: 3, start: 0 }, ok: false });
    w = take(w.window, 1000, 2, 1000);
    expect(w).toEqual({ window: { count: 1, start: 1000 }, ok: true });
  });
});
