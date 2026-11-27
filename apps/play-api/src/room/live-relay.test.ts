import { beforeEach, describe, expect, it } from "vitest";

import { LiveRelay, LiveStream } from "./live-relay";

import type { ServerMessage } from "../protocol";

/* The generic stream, with a toy game: ops are numbers, 0 wipes, the tally counts ops since a wipe. */

type Op = number;
let clock = 0;
beforeEach(() => {
  clock = 1_000_000;
});

const compact = (log: readonly Op[]): Op[] => log.slice(log.lastIndexOf(0) + 1);
function relay(perSecond = 3, resendMs?: number): LiveStream<Op, { n: number; rebuilt: boolean }> {
  return new LiveStream<Op, { n: number; rebuilt: boolean }>(
    { perSecond, start: (rebuilt) => ({ n: 0, rebuilt }), compact, ...(resendMs === undefined ? {} : { resendMs }) },
    () => clock,
  );
}
const pong: ServerMessage = { t: "pong" };
const sync = (key: string, ops: Op[]) => ({ t: "sync", key, ops }) as unknown as ServerMessage;
const resend = (key: string) => ({ t: "resend", key }) as unknown as ServerMessage;

describe("LiveRelay", () => {
  it("allows perSecond a key over any rolling second, each key its own, and clear starts afresh", () => {
    const r = new LiveRelay(2);
    expect(r.allow("a", 0)).toBe(true);
    expect(r.allow("a", 500)).toBe(true);
    expect(r.allow("a", 999)).toBe(false);
    expect(r.allow("b", 999)).toBe(true);
    expect(r.allow("a", 1001)).toBe(true);
    expect(r.allow("a", 1400)).toBe(false);
    r.clear();
    expect(r.allow("a", 1400)).toBe(true);
  });
});

describe("LiveStream", () => {
  it("starts with nothing live", () => {
    const r = relay();
    expect(r.key).toBeNull();
    expect(r.missing).toBe(false);
    expect(r.size).toBe(0);
    expect(r.base(false)).toBeNull();
    expect(r.catchUp("tv", sync)).toEqual([]);
  });

  it("a new key starts an empty log and a fresh tally; the same key keeps it", () => {
    const r = relay();
    r.follow("1:0");
    expect(r.key).toBe("1:0");
    expect(r.base(false)).toEqual({ n: 0, rebuilt: false });
    r.record([1, 2], { n: 2, rebuilt: false });
    r.follow("1:0");
    expect(r.base(false)).toEqual({ n: 2, rebuilt: false });
    expect(r.catchUp("tv", sync)).toEqual([{ to: "tv", message: sync("1:0", [1, 2]) }]);
    r.follow("1:1");
    expect(r.base(false)).toEqual({ n: 0, rebuilt: false });
    expect(r.catchUp("tv", sync)).toEqual([{ to: "tv", message: sync("1:1", []) }]);
    r.follow(null);
    expect(r.key).toBeNull();
    expect(r.catchUp("tv", sync)).toEqual([]);
  });

  it("the catch-up is the game's compaction of the log", () => {
    const r = relay();
    r.follow("k");
    r.record([1, 2, 0, 3], { n: 1, rebuilt: false });
    r.record([4], { n: 2, rebuilt: false });
    expect(r.catchUp("tv", sync)).toEqual([{ to: "tv", message: sync("k", [3, 4]) }]);
  });

  it("compacts the log it keeps as it grows, so it never holds much more than the catch-up", () => {
    const r = relay(1000);
    r.follow("k");
    for (let i = 0; i < 5000; i++) r.record(i % 10 === 0 ? [0] : [i], { n: 0, rebuilt: false });
    expect(r.size).toBeLessThan(600);
    expect(r.catchUp("tv", sync)).toEqual([{ to: "tv", message: sync("k", [4991, 4992, 4993, 4994, 4995, 4996, 4997, 4998, 4999]) }]);
  });

  it("fans out to each device once", () => {
    const r = relay();
    expect(r.fanOut(["tv", "a", "tv"], pong)).toEqual([
      { to: "tv", message: pong },
      { to: "a", message: pong },
    ]);
    expect(r.fanOut(new Set<string>(), pong)).toEqual([]);
  });

  it("takes perSecond messages per device in a rolling second, per device", () => {
    const r = relay(3);
    expect([r.admit("a"), r.admit("a"), r.admit("a"), r.admit("a")]).toEqual([true, true, true, false]);
    expect(r.admit("b")).toBe(true);
    clock += 999;
    expect(r.admit("a")).toBe(false);
    clock += 1;
    expect(r.admit("a")).toBe(true);
    expect(r.admit("a")).toBe(true);
    expect(r.admit("a")).toBe(true);
    expect(r.admit("a")).toBe(false);
  });

  it("a room rebuilt with a live key and no log: missing until a restart, asks for a resend", () => {
    const r = relay();
    r.lost("2:5");
    expect(r.key).toBe("2:5");
    expect(r.missing).toBe(true);
    expect(r.catchUp("tv", sync)).toEqual([]);
    expect(r.base(false)).toBeNull();
    expect(r.base(true)).toEqual({ n: 0, rebuilt: true });
    expect(r.askResend("a", resend)).toEqual([{ to: "a", message: resend("2:5") }]);
    // The same key does not end it.
    r.follow("2:5");
    expect(r.missing).toBe(true);
    r.record([0, 7], { n: 1, rebuilt: true });
    expect(r.missing).toBe(false);
    expect(r.askResend("a", resend)).toEqual([]);
    expect(r.catchUp("tv", sync)).toEqual([{ to: "tv", message: sync("2:5", [7]) }]);
  });

  it("a new key ends a missing log", () => {
    const r = relay();
    r.lost("2:5");
    r.follow("2:6");
    expect(r.missing).toBe(false);
    expect(r.base(false)).toEqual({ n: 0, rebuilt: false });
  });

  it("the resend reply is exempt from the limit once, from its first restart to its last", () => {
    const r = relay(2);
    r.lost("k");
    expect([r.admit("a"), r.admit("a"), r.admit("a")]).toEqual([true, true, false]);
    r.askResend("a", resend);
    // Not exempt until the reply begins; another device never is.
    expect(r.admit("a")).toBe(false);
    expect(r.admit("b", { restarts: true })).toBe(true);
    expect(r.admit("a", { restarts: true })).toBe(true);
    for (let i = 0; i < 40; i++) {
      clock += 100;
      expect(r.admit("a")).toBe(true);
    }
    expect(r.admit("a", { last: true })).toBe(true);
    // Spent: the limit holds again, and a second restart is not exempt.
    expect([r.admit("a"), r.admit("a"), r.admit("a", { restarts: true })]).toEqual([true, true, false]);
  });

  it("a one-message reply is its first and its last", () => {
    const r = relay(1);
    r.lost("k");
    expect(r.admit("a")).toBe(true);
    r.askResend("a", resend);
    expect(r.admit("a", { restarts: true, last: true })).toBe(true);
    expect(r.admit("a")).toBe(false);
  });

  it("a reply whose last never comes is exempt for resendMs (default 5 s)", () => {
    const r = relay(1);
    r.lost("k");
    r.askResend("a", resend);
    expect(r.admit("a", { restarts: true })).toBe(true);
    clock += 4999;
    expect(r.admit("a")).toBe(true);
    clock += 1;
    expect([r.admit("a"), r.admit("a")]).toEqual([true, false]);
    const short = relay(1, 500);
    short.lost("k");
    short.askResend("a", resend);
    short.admit("a", { restarts: true });
    clock += 500;
    expect([short.admit("a"), short.admit("a")]).toEqual([true, false]);
  });

  it("a new key drops an unused exemption", () => {
    const r = relay(1);
    r.lost("k");
    r.askResend("a", resend);
    r.follow("k2");
    expect([r.admit("a", { restarts: true }), r.admit("a", { restarts: true })]).toEqual([true, false]);
  });

  it("asks only while the log is missing", () => {
    const r = relay();
    expect(r.askResend("a", resend)).toEqual([]);
    r.follow("k");
    expect(r.askResend("a", resend)).toEqual([]);
  });
});
