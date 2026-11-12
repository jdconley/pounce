import { describe, expect, test } from "vitest";

import { cacheUrl, LOCAL_READ_MS, remembered, type CacheLike } from "./memory";
import {
  APP_STORE_ID,
  appStatus,
  enforcedMinimum,
  FOUND_TTL_S,
  gameUnsupported,
  KEEP_S,
  known,
  lookupDue,
  lookupUrl,
  MISSING_TTL_S,
  readLookup,
  refreshLookup,
  refusalFor,
  RETIRED_SNAPSHOT,
  storeId,
  storeVersion,
  type LookupRecord,
  type Remembered,
} from "./status";
import { parseApp } from "./version";

const STORE = "https://apps.apple.com/app/id6829560061";
const BETA = "https://testflight.apple.com/join/abc";

/** A `Remembered` over a map, counting what it was asked. */
function memory(): Remembered & { kept: Map<string, { value: string; ttl: number }> } {
  const kept = new Map<string, { value: string; ttl: number }>();
  return {
    kept,
    get: (key) => Promise.resolve(kept.get(key)?.value ?? null),
    put: (key, value, ttl) => {
      kept.set(key, { value, ttl });
      return Promise.resolve();
    },
  };
}

/** A fake Apple: answers each lookup with the next body, and writes down what it was asked. */
function apple(...answers: (unknown | Error | number)[]) {
  const asked: { url: string; headers: Record<string, string> }[] = [];
  const fetcher = ((url: string, init?: RequestInit) => {
    asked.push({ url, headers: Object.fromEntries(new Headers(init?.headers)) });
    const next = answers.length > 1 ? answers.shift() : answers[0];
    if (next instanceof Error) return Promise.reject(next);
    if (typeof next === "number") return Promise.resolve(new Response("nope", { status: next }));
    return Promise.resolve(new Response(typeof next === "string" ? next : JSON.stringify(next)));
  }) as unknown as typeof fetch;
  return { asked, fetcher };
}

const listing = (version: unknown) => ({ resultCount: 1, results: [{ trackId: 6829560061, version }] });

describe("readLookup", () => {
  test("is the listing's version", () => {
    expect(readLookup(listing("1.1"))).toBe("1.1");
    expect(readLookup(listing("1.2.0"))).toBe("1.2.0");
  });

  test.each([
    ["no listing", { resultCount: 0, results: [] }],
    ["two listings", { resultCount: 2, results: [{ version: "1.1" }, { version: "9.9" }] }],
    ["a count with no results", { resultCount: 1 }],
    ["a result that isn't an object", { resultCount: 1, results: ["1.1"] }],
    ["a null result", { resultCount: 1, results: [null] }],
    ["no version", { resultCount: 1, results: [{}] }],
    ["a version that isn't one", listing("soon")],
    ["a number for a version", listing(1.1)],
    ["null", null],
    ["text", "1.1"],
  ])("%s is nothing", (_, body) => {
    expect(readLookup(body)).toBeNull();
  });
});

describe("storeId", () => {
  test("is the id in APP_STORE_URL, else Pounce's own", () => {
    expect(storeId({})).toBe(APP_STORE_ID);
    expect(storeId({ APP_STORE_URL: "" })).toBe(APP_STORE_ID);
    expect(storeId({ APP_STORE_URL: "https://apps.apple.com/us/app/pounce/id1234567890?mt=8" })).toBe("1234567890");
    expect(storeId({ APP_STORE_URL: "http://apps.apple.com/app/id1234567890" })).toBe(APP_STORE_ID);
    expect(storeId({ APP_STORE_URL: "https://example.com/nothing" })).toBe(APP_STORE_ID);
  });
});

const HOUR = 3_600_000;
const KEY = `app-latest:${APP_STORE_ID}`;

/** A clock a test moves by hand. */
function clock(start = 1_800_000_000_000) {
  let t = start;
  return { now: () => t, pass: (ms: number) => void (t += ms) };
}

/** What a test's `background` was handed: the lookups that outlive the answer. */
function later() {
  const work: Promise<void>[] = [];
  return { work, background: (w: Promise<void>) => void work.push(w), settle: () => Promise.all(work) };
}

const recordIn = (m: ReturnType<typeof memory>) => JSON.parse(m.kept.get(KEY)?.value ?? "null") as LookupRecord | null;

describe("lookupDue", () => {
  test("Apple is asked when it never was, and again when the last answer has had its time", () => {
    expect(lookupDue(null, 0)).toBe(true);
    const found = { version: "1.1", tried: 1000, ok: true };
    expect(lookupDue(found, 1000 + FOUND_TTL_S * 1000 - 1)).toBe(false);
    expect(lookupDue(found, 1000 + FOUND_TTL_S * 1000)).toBe(true);
    const failed = { version: "1.1", tried: 1000, ok: false };
    expect(lookupDue(failed, 1000 + MISSING_TTL_S * 1000 - 1)).toBe(false);
    expect(lookupDue(failed, 1000 + MISSING_TTL_S * 1000)).toBe(true);
    // A clock set back: ask rather than wait for it to catch up.
    expect(lookupDue(found, 0)).toBe(true);
    expect(FOUND_TTL_S).toBeGreaterThanOrEqual(3600);
    expect(KEEP_S).toBeGreaterThan(FOUND_TTL_S * 10);
  });
});

describe("storeVersion never waits on Apple", () => {
  test("cold, with Apple hanging: it answers 'unknown' at once and hands the lookup to the background", async () => {
    const asked: string[] = [];
    const hang = ((url: string) => {
      asked.push(url);
      return new Promise<Response>(() => undefined);
    }) as unknown as typeof fetch;
    const bg = later();
    const c = clock();
    const started = Date.now();
    // (Another listing's id, so this lookup, which never ends, holds nobody else's back.)
    const env = { APP_STORE_URL: "https://apps.apple.com/app/id1111111111" };
    expect(await storeVersion(env, memory(), hang, c.now, bg.background)).toBeNull();
    expect(Date.now() - started).toBeLessThan(200);
    expect(bg.work).toHaveLength(1);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(asked).toEqual(["https://itunes.apple.com/lookup?id=1111111111"]);
    // Asked again at once, with the first still out: the same nothing, and no second lookup.
    expect(await storeVersion(env, memory(), hang, c.now, bg.background)).toBeNull();
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(asked).toHaveLength(1);
  });

  test("the lookup's answer is for the next asker", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    const kept = memory();
    const bg = later();
    const c = clock();
    expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBeNull();
    await bg.settle();
    expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBe("1.1");
    expect(asked).toEqual([{ url: `https://itunes.apple.com/lookup?id=${APP_STORE_ID}`, headers: { accept: "application/json" } }]);
    expect(lookupUrl("42")).toBe("https://itunes.apple.com/lookup?id=42");
    // Kept far longer than it is fresh: a stale answer beats none.
    expect(kept.kept.get(KEY)?.ttl).toBe(KEEP_S);
  });

  test("a stale answer is still the answer, while a fresh one is fetched behind it", async () => {
    const { asked, fetcher } = apple(listing("1.1"), listing("1.2"));
    const kept = memory();
    const bg = later();
    const c = clock();
    await storeVersion({}, kept, fetcher, c.now, bg.background);
    await bg.settle();
    c.pass(FOUND_TTL_S * 1000 - 1);
    expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBe("1.1");
    expect(asked).toHaveLength(1);
    c.pass(1);
    // Due now: the old answer comes back at once, and Apple is asked behind it.
    expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBe("1.1");
    await bg.settle();
    expect(asked).toHaveLength(2);
    expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBe("1.2");
  });

  test.each([
    ["Apple is down", 503],
    ["Apple can't be reached", new Error("network")],
    ["Apple answers something that isn't JSON", "<html>"],
    ["Apple answers far too much", `{"pad":"${"x".repeat(300_000)}"}`],
    ["Apple says the app isn't listed", { resultCount: 0, results: [] }],
  ])("the last good answer outlives a lookup where %s: what was known stays known", async (_, failure) => {
    const { asked, fetcher } = apple(listing("1.2"), failure);
    const kept = memory();
    const bg = later();
    const c = clock();
    await storeVersion({}, kept, fetcher, c.now, bg.background);
    await bg.settle();
    for (let round = 0; round < 3; round++) {
      c.pass(FOUND_TTL_S * 1000);
      expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBe("1.2");
      await bg.settle();
    }
    expect(asked.length).toBeGreaterThan(1);
    expect(recordIn(kept)).toMatchObject({ version: "1.2", ok: false });
    // So a minimum that was being enforced goes on being enforced: nothing flaps.
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, { store: await storeVersion({}, kept, fetcher, c.now, bg.background) })).toBe("1.2");
  });

  test("before the app is listed nothing is known, and Apple is asked again only every quarter hour", async () => {
    const { asked, fetcher } = apple({ resultCount: 0, results: [] });
    const kept = memory();
    const bg = later();
    const c = clock();
    for (let i = 0; i < 10; i++) {
      expect(await storeVersion({}, kept, fetcher, c.now, bg.background)).toBeNull();
      await bg.settle();
      c.pass(60_000);
    }
    expect(asked).toHaveLength(1);
    c.pass(MISSING_TTL_S * 1000);
    await storeVersion({}, kept, fetcher, c.now, bg.background);
    await bg.settle();
    expect(asked).toHaveLength(2);
  });

  test("APP_LOOKUP=off never asks Apple and knows nothing", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    const bg = later();
    expect(await storeVersion({ APP_LOOKUP: "Off" }, memory(), fetcher, clock().now, bg.background)).toBeNull();
    expect(asked).toEqual([]);
    expect(bg.work).toEqual([]);
  });

  test("looks up the id in APP_STORE_URL once there is one", async () => {
    const { asked, fetcher } = apple(listing("2.0"));
    const bg = later();
    await storeVersion({ APP_STORE_URL: "https://apps.apple.com/app/id1234567890" }, memory(), fetcher, clock().now, bg.background);
    await bg.settle();
    expect(asked[0]?.url).toBe("https://itunes.apple.com/lookup?id=1234567890");
  });

  test("a memory that fails is an empty one: nothing is known, nothing throws", async () => {
    const { fetcher } = apple(listing("1.1"));
    const broken: Remembered = { get: () => Promise.reject(new Error("no cache")), put: () => Promise.reject(new Error("no cache")) };
    const bg = later();
    expect(await storeVersion({}, broken, fetcher, clock().now, bg.background)).toBeNull();
    await expect(bg.settle()).resolves.toBeDefined();
  });

  test("something unreadable in memory is nothing known", async () => {
    for (const junk of ["garbage", "[]", "null", '{"version":"1.1"}', '{"tried":"soon"}']) {
      const kept = memory();
      kept.kept.set(KEY, { value: junk, ttl: 1 });
      const bg = later();
      expect(await storeVersion({}, kept, apple(503).fetcher, clock().now, bg.background)).toBeNull();
      await bg.settle();
    }
  });
});

describe("refreshLookup asks Apple once", () => {
  test("thirty askers at once make one lookup", async () => {
    let release: (r: Response) => void = () => undefined;
    const asked: string[] = [];
    const slow = ((url: string) => {
      asked.push(url);
      return new Promise<Response>((resolve) => (release = resolve));
    }) as unknown as typeof fetch;
    const kept = memory();
    const c = clock();
    const bg = later();
    await Promise.all(Array.from({ length: 30 }, () => storeVersion({}, kept, slow, c.now, bg.background)));
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(asked).toHaveLength(1);
    release(new Response(JSON.stringify(listing("1.1"))));
    await bg.settle();
    expect(await storeVersion({}, kept, slow, c.now, bg.background)).toBe("1.1");
    expect(asked).toHaveLength(1);
  });

  test("Apple is marked as asked before the request leaves, so an isolate that looks meanwhile asks nothing", async () => {
    let release: (r: Response) => void = () => undefined;
    const slow = (() => new Promise<Response>((resolve) => (release = resolve))) as unknown as typeof fetch;
    const kept = memory();
    const c = clock();
    const first = refreshLookup({}, kept, slow, c.now);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(recordIn(kept)).toEqual({ version: null, tried: c.now(), ok: false });
    expect(lookupDue(recordIn(kept), c.now())).toBe(false);
    release(new Response("nope", { status: 503 }));
    await first;
  });

  test("a failed lookup is not tried again until its quarter hour is up, however many ask", async () => {
    const { asked, fetcher } = apple(503);
    const kept = memory();
    const c = clock();
    for (let i = 0; i < 50; i++) await refreshLookup({}, kept, fetcher, c.now);
    expect(asked).toHaveLength(1);
    c.pass(MISSING_TTL_S * 1000);
    await refreshLookup({}, kept, fetcher, c.now);
    expect(asked).toHaveLength(2);
  });

  test("a good answer is not asked for again for six hours", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    const kept = memory();
    const c = clock();
    for (let i = 0; i < 6; i++) {
      await refreshLookup({}, kept, fetcher, c.now);
      c.pass(HOUR - 1);
    }
    expect(asked).toHaveLength(1);
  });
});

describe("known: what Apple said, and what apps are told", () => {
  test("the same, unless APP_LATEST overrides what apps are told", () => {
    expect(known({}, "1.1")).toEqual({ store: "1.1", latest: "1.1" });
    expect(known({ APP_LATEST: "" }, null)).toEqual({ store: null, latest: null });
    expect(known({ APP_LATEST: " 1.3 " }, "1.1")).toEqual({ store: "1.1", latest: "1.3" });
    expect(known({ APP_LATEST: "1.3" }, null)).toEqual({ store: null, latest: "1.3" });
    expect(known({ APP_LATEST: "off" }, "1.1")).toEqual({ store: "1.1", latest: null });
  });
});

describe("remembered", () => {
  const ORIGIN = "https://play.conleychaos.com";

  function cache(): CacheLike & { puts: { key: string; value: string; control: string | null }[]; entries: Map<string, string>; reads: string[] } {
    const entries = new Map<string, string>();
    const puts: { key: string; value: string; control: string | null }[] = [];
    const reads: string[] = [];
    return {
      entries,
      puts,
      reads,
      match: (key) => {
        reads.push(key);
        return Promise.resolve(entries.has(key) ? new Response(entries.get(key)) : undefined);
      },
      put: async (key, value) => {
        const text = await value.clone().text();
        entries.set(key, text);
        puts.push({ key, value: text, control: value.headers.get("cache-control") });
      },
    };
  }

  test("the cache key is a path on the Worker's own host", () => {
    expect(cacheUrl(ORIGIN, "app-latest:6829560061")).toBe("https://play.conleychaos.com/__cache/app-latest%3A6829560061");
    expect(new URL(cacheUrl("http://localhost:8787", "k")).host).toBe("localhost:8787");
  });

  test("answers from this isolate until the time is up, then from the cache", async () => {
    const c = clock(1000);
    const shared = cache();
    const m = remembered(shared, ORIGIN, c.now, new Map());
    expect(await m.get("k")).toBeNull();
    await m.put("k", "1.1", 60);
    expect(shared.puts).toEqual([{ key: `${ORIGIN}/__cache/k`, value: "1.1", control: "public, max-age=60" }]);
    shared.entries.clear();
    expect(await m.get("k")).toBe("1.1");
    c.pass(60_000);
    expect(await m.get("k")).toBeNull();
    shared.entries.set(`${ORIGIN}/__cache/k`, "1.2");
    expect(await m.get("k")).toBe("1.2");
  });

  test("a new isolate reads what another one kept, and a burst of reads touches the cache once", async () => {
    const shared = cache();
    const c = clock();
    await remembered(shared, ORIGIN, c.now, new Map()).put("app-latest:1", "1.1", 60);
    const fresh = remembered(shared, ORIGIN, c.now, new Map());
    shared.reads.length = 0;
    for (let i = 0; i < 20; i++) expect(await fresh.get("app-latest:1")).toBe("1.1");
    expect(shared.reads).toHaveLength(1);
    c.pass(LOCAL_READ_MS);
    await fresh.get("app-latest:1");
    expect(shared.reads).toHaveLength(2);
  });

  test("until the Worker knows its own host, only this isolate remembers: no key on anyone else's", async () => {
    const shared = cache();
    const m = remembered(shared, null, () => 0, new Map());
    await m.put("k", "v", 1);
    expect(await m.get("k")).toBe("v");
    expect(await remembered(shared, null, () => 0, new Map()).get("k")).toBeNull();
    expect(shared.puts).toEqual([]);
    expect(shared.reads).toEqual([]);
  });

  test("works with no cache at all", async () => {
    const m = remembered(undefined, ORIGIN, () => 0, new Map());
    await m.put("k", "v", 1);
    expect(await m.get("k")).toBe("v");
  });
});

describe("enforcedMinimum", () => {
  const apple = (store: string | null) => ({ store });

  test("is APP_MINIMUM once Apple says the store has a version that new", () => {
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, apple("1.1"))).toBe("1.1");
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, apple("1.2"))).toBe("1.1");
    expect(enforcedMinimum({ APP_MINIMUM: "v1.1.0" }, apple("1.1"))).toBe("1.1.0");
  });

  test("is none while nobody could download a version that new", () => {
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, apple("1.1"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "11.0" }, apple("1.9"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, apple(null))).toBeNull();
  });

  test("is none when unset, empty or unreadable", () => {
    expect(enforcedMinimum({}, apple("1.1"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "" }, apple("1.1"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "soon" }, apple("1.1"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "soon", APP_MINIMUM_FORCE: "on" }, apple("1.1"))).toBeNull();
  });

  test("APP_LATEST is the server's word, not Apple's: it never satisfies the guard", () => {
    // An unreleased 1.2, announced by override: nobody below it is locked out.
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, known({ APP_LATEST: "1.2" }, "1.1"))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, known({ APP_LATEST: "1.2" }, null))).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, known({ APP_LATEST: "9.9" }, "1.2"))).toBe("1.2");
    // And "off" hides the version from apps without lifting a minimum Apple has confirmed.
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, known({ APP_LATEST: "off" }, "1.2"))).toBe("1.2");
  });

  test("only APP_MINIMUM_FORCE lifts the guard, and then whatever Apple says", () => {
    for (const on of ["on", "ON", "1", "true"]) {
      expect(enforcedMinimum({ APP_MINIMUM: "1.2", APP_MINIMUM_FORCE: on }, apple(null))).toBe("1.2");
      expect(enforcedMinimum({ APP_MINIMUM: "1.2", APP_MINIMUM_FORCE: on }, apple("1.1"))).toBe("1.2");
    }
    for (const off of ["", "off", "no", "0"]) expect(enforcedMinimum({ APP_MINIMUM: "1.2", APP_MINIMUM_FORCE: off }, apple("1.1"))).toBeNull();
  });
});

describe("appStatus", () => {
  const both = (v: string | null) => ({ store: v, latest: v });

  test("says nothing it doesn't know", () => {
    expect(appStatus({}, both(null))).toEqual({});
    expect(appStatus({ APP_STORE_URL: "", APP_MINIMUM: "", TESTFLIGHT_URL: "" }, both(null))).toEqual({});
  });

  test("before release: only where the beta is, and no store link to a listing that isn't there", () => {
    expect(appStatus({ APP_STORE_URL: STORE, TESTFLIGHT_URL: BETA, APP_MINIMUM: "1.1" }, both(null))).toEqual({ testflightUrl: BETA });
  });

  test("once the store has a version: that version and its listing", () => {
    expect(appStatus({ TESTFLIGHT_URL: BETA }, both("1.1"))).toEqual({ latest: "1.1", storeUrl: STORE, testflightUrl: BETA });
    expect(appStatus({ APP_STORE_URL: "https://apps.apple.com/us/app/pounce/id6829560061" }, both("1.1"))).toEqual({
      latest: "1.1",
      storeUrl: "https://apps.apple.com/us/app/pounce/id6829560061",
    });
  });

  test("a minimum only once it can be met", () => {
    expect(appStatus({ APP_MINIMUM: "1.1" }, both("1.2"))).toEqual({ latest: "1.2", minimum: "1.1", storeUrl: STORE });
    expect(appStatus({ APP_MINIMUM: "1.3" }, both("1.2"))).toEqual({ latest: "1.2", storeUrl: STORE });
  });

  test("APP_LATEST changes what apps are told is newest, and nothing about the minimum", () => {
    expect(appStatus({ APP_LATEST: "1.3", APP_MINIMUM: "1.3" }, known({ APP_LATEST: "1.3" }, "1.2"))).toEqual({ latest: "1.3", storeUrl: STORE });
    expect(appStatus({ APP_LATEST: "off", APP_MINIMUM: "1.2" }, known({ APP_LATEST: "off" }, "1.2"))).toEqual({ minimum: "1.2", storeUrl: STORE });
  });

  test("a link that isn't https is left out", () => {
    expect(appStatus({ TESTFLIGHT_URL: "javascript:alert(1)", APP_STORE_URL: "http://apps.apple.com/app/id6829560061" }, both("1.1"))).toEqual({
      latest: "1.1",
      storeUrl: STORE,
    });
  });
});

describe("refusalFor", () => {
  const ios = (version: string, protocol = 1) => parseApp(`platform=ios; version=${version}; build=1; protocol=${protocol}`);
  const never = () => Promise.reject(new Error("the store was asked"));
  const live = (version: string | null) => () => Promise.resolve(version);

  test("with no minimum everyone is served, and nothing is read", async () => {
    expect(await refusalFor(ios("1.1"), {}, 1, never)).toBeNull();
    expect(await refusalFor(null, {}, 1, never)).toBeNull();
    expect(await refusalFor(null, { APP_MINIMUM: "" }, 1, never)).toBeNull();
  });

  test("an app at or above the minimum is served without reading anything", async () => {
    expect(await refusalFor(ios("1.2"), { APP_MINIMUM: "1.2" }, 1, never)).toBeNull();
    expect(await refusalFor(ios("2.0"), { APP_MINIMUM: "1.2" }, 1, never)).toBeNull();
  });

  test("an app below it is told to update, with where", async () => {
    expect(await refusalFor(ios("1.1"), { APP_MINIMUM: "1.2", TESTFLIGHT_URL: BETA }, 1, live("1.2"))).toEqual({
      error: "update_required",
      minimum: "1.2",
      storeUrl: STORE,
      testflightUrl: BETA,
    });
  });

  test("an app that didn't say is version 1.0", async () => {
    expect(await refusalFor(null, { APP_MINIMUM: "1.1" }, 1, live("1.1"))).toEqual({ error: "update_required", minimum: "1.1", storeUrl: STORE });
    expect(await refusalFor(null, { APP_MINIMUM: "1.0" }, 1, never)).toBeNull();
  });

  test("nobody is turned away for a version they can't download yet, or while nothing is known", async () => {
    expect(await refusalFor(ios("1.1"), { APP_MINIMUM: "1.2" }, 1, live("1.1"))).toBeNull();
    expect(await refusalFor(ios("1.1"), { APP_MINIMUM: "1.2" }, 1, live(null))).toBeNull();
    expect(await refusalFor(null, { APP_MINIMUM: "1.1" }, 1, live(null))).toBeNull();
  });

  test("APP_LATEST with APP_MINIMUM for an unreleased version locks nobody out", async () => {
    const env = { APP_MINIMUM: "1.2", APP_LATEST: "1.2" };
    expect(await refusalFor(ios("1.1"), env, 1, live("1.1"))).toBeNull();
    expect(await refusalFor(ios("1.1"), env, 1, live(null))).toBeNull();
    expect(await refusalFor(null, env, 1, live(null))).toBeNull();
    // Unless the owner says so in as many words.
    expect(await refusalFor(ios("1.1"), { ...env, APP_MINIMUM_FORCE: "on" }, 1, live(null))).toEqual({ error: "update_required", minimum: "1.2", storeUrl: STORE });
  });

  test("an app speaking a protocol the server dropped is turned away whatever the store says", async () => {
    expect(await refusalFor(ios("1.1", 1), {}, 2, live(null))).toEqual({ error: "update_required" });
    expect(await refusalFor(ios("1.1", 1), { APP_MINIMUM: "1.2" }, 2, live("1.2"))).toMatchObject({ error: "update_required", minimum: "1.2", storeUrl: STORE });
    expect(await refusalFor(ios("2.0", 2), {}, 2, never)).toBeNull();
  });
});

describe("what a refusal looks like", () => {
  test("a table whose game the app can't draw names the game, in the body and in headers a refused socket can read", () => {
    expect(gameUnsupported("tiles", "Tuna Tiles")).toEqual({
      body: { error: "game_unsupported", game: "tiles", title: "Tuna Tiles" },
      headers: { "x-pounce-update": "game", "x-pounce-game": "tiles", "x-pounce-game-title": "Tuna%20Tiles" },
    });
  });

  test("the frame version 1.0 is sent is a snapshot of a protocol it doesn't speak, and nothing else", () => {
    expect(JSON.parse(RETIRED_SNAPSHOT)).toEqual({ t: "snapshot", protocol: 0 });
  });
});
