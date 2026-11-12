import { describe, expect, test } from "vitest";

import { remembered, type CacheLike } from "./memory";
import {
  APP_STORE_ID,
  appStatus,
  enforcedMinimum,
  FOUND_TTL_S,
  gameUnsupported,
  latestVersion,
  lookupUrl,
  MISSING_TTL_S,
  readLookup,
  refusalFor,
  RETIRED_SNAPSHOT,
  storeId,
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

describe("latestVersion", () => {
  test("asks Apple's public lookup for Pounce, with nothing of the asker's", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    expect(await latestVersion({}, memory(), fetcher)).toBe("1.1");
    expect(asked).toEqual([{ url: `https://itunes.apple.com/lookup?id=${APP_STORE_ID}`, headers: { accept: "application/json" } }]);
    expect(lookupUrl("42")).toBe("https://itunes.apple.com/lookup?id=42");
  });

  test("keeps the answer for hours, and asks once", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    const kept = memory();
    await latestVersion({}, kept, fetcher);
    expect(await latestVersion({}, kept, fetcher)).toBe("1.1");
    expect(asked).toHaveLength(1);
    expect([...kept.kept.values()]).toEqual([{ value: "1.1", ttl: FOUND_TTL_S }]);
    expect(FOUND_TTL_S).toBeGreaterThanOrEqual(3600);
  });

  test("says nothing while the app isn't on the store, and doesn't ask again for a while", async () => {
    const { asked, fetcher } = apple({ resultCount: 0, results: [] });
    const kept = memory();
    expect(await latestVersion({}, kept, fetcher)).toBeNull();
    expect(await latestVersion({}, kept, fetcher)).toBeNull();
    expect(asked).toHaveLength(1);
    expect([...kept.kept.values()][0]?.ttl).toBe(MISSING_TTL_S);
  });

  test.each([
    ["Apple is down", 503],
    ["Apple can't be reached", new Error("network")],
    ["Apple answers something that isn't JSON", "<html>"],
    ["Apple answers far too much", `{"pad":"${"x".repeat(300_000)}"}`],
  ])("says nothing when %s", async (_, answer) => {
    const { fetcher } = apple(answer);
    expect(await latestVersion({}, memory(), fetcher)).toBeNull();
  });

  test("a failed lookup is tried again once its short wait is over", async () => {
    const { asked, fetcher } = apple(503, listing("1.2"));
    const kept = memory();
    expect(await latestVersion({}, kept, fetcher)).toBeNull();
    kept.kept.clear();
    expect(await latestVersion({}, kept, fetcher)).toBe("1.2");
    expect(asked).toHaveLength(2);
  });

  test("APP_LATEST is believed over Apple, who is then never asked", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    expect(await latestVersion({ APP_LATEST: " 1.3 " }, memory(), fetcher)).toBe("1.3");
    expect(await latestVersion({ APP_LATEST: "off" }, memory(), fetcher)).toBeNull();
    expect(asked).toEqual([]);
  });

  test("APP_LOOKUP=off never asks Apple", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    expect(await latestVersion({ APP_LOOKUP: "Off" }, memory(), fetcher)).toBeNull();
    expect(asked).toEqual([]);
  });

  test("looks up the id in APP_STORE_URL once there is one", async () => {
    const { asked, fetcher } = apple(listing("2.0"));
    await latestVersion({ APP_STORE_URL: "https://apps.apple.com/app/id1234567890" }, memory(), fetcher);
    expect(asked[0]?.url).toBe("https://itunes.apple.com/lookup?id=1234567890");
  });

  test("a memory that fails is an empty one: the answer still comes", async () => {
    const { asked, fetcher } = apple(listing("1.1"));
    const broken: Remembered = { get: () => Promise.reject(new Error("no cache")), put: () => Promise.reject(new Error("no cache")) };
    expect(await latestVersion({}, broken, fetcher)).toBe("1.1");
    expect(asked).toHaveLength(1);
  });

  test("something unreadable in memory is nothing", async () => {
    const kept = memory();
    kept.kept.set(`app-latest:${APP_STORE_ID}`, { value: "garbage", ttl: 1 });
    expect(await latestVersion({}, kept, apple(listing("1.1")).fetcher)).toBeNull();
  });
});

describe("remembered", () => {
  function cache(): CacheLike & { puts: { key: string; value: string; control: string | null }[]; entries: Map<string, string> } {
    const entries = new Map<string, string>();
    const puts: { key: string; value: string; control: string | null }[] = [];
    return {
      entries,
      puts,
      match: (key) => Promise.resolve(entries.has(key) ? new Response(entries.get(key)) : undefined),
      put: async (key, value) => {
        const text = await value.clone().text();
        entries.set(key, text);
        puts.push({ key, value: text, control: value.headers.get("cache-control") });
      },
    };
  }

  test("answers from this isolate until the time is up, then from the cache", async () => {
    let now = 1000;
    const shared = cache();
    const m = remembered(shared, () => now, new Map());
    expect(await m.get("k")).toBeNull();
    await m.put("k", "1.1", 60);
    expect(shared.puts).toEqual([{ key: "https://app-status.invalid/k", value: "1.1", control: "public, max-age=60" }]);
    shared.entries.clear();
    expect(await m.get("k")).toBe("1.1");
    now += 60_000;
    expect(await m.get("k")).toBeNull();
    shared.entries.set("https://app-status.invalid/k", "1.2");
    expect(await m.get("k")).toBe("1.2");
  });

  test("a new isolate reads what another one kept", async () => {
    const shared = cache();
    await remembered(shared, () => 0, new Map()).put("app-latest:1", "1.1", 60);
    expect(await remembered(shared, () => 0, new Map()).get("app-latest:1")).toBe("1.1");
  });

  test("works with no cache at all", async () => {
    const m = remembered(undefined, () => 0, new Map());
    await m.put("k", "v", 1);
    expect(await m.get("k")).toBe("v");
    expect(await remembered(undefined, () => 0, new Map()).get("k")).toBeNull();
  });
});

describe("enforcedMinimum", () => {
  test("is APP_MINIMUM once the store has a version that new", () => {
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, "1.1")).toBe("1.1");
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, "1.2")).toBe("1.1");
    expect(enforcedMinimum({ APP_MINIMUM: "v1.1.0" }, "1.1")).toBe("1.1.0");
  });

  test("is none while nobody could download a version that new", () => {
    expect(enforcedMinimum({ APP_MINIMUM: "1.2" }, "1.1")).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "11.0" }, "1.9")).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "1.1" }, null)).toBeNull();
  });

  test("is none when unset, empty or unreadable", () => {
    expect(enforcedMinimum({}, "1.1")).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "" }, "1.1")).toBeNull();
    expect(enforcedMinimum({ APP_MINIMUM: "soon" }, "1.1")).toBeNull();
  });
});

describe("appStatus", () => {
  test("says nothing it doesn't know", () => {
    expect(appStatus({}, null)).toEqual({});
    expect(appStatus({ APP_STORE_URL: "", APP_MINIMUM: "", TESTFLIGHT_URL: "" }, null)).toEqual({});
  });

  test("before release: only where the beta is, and no store link to a listing that isn't there", () => {
    expect(appStatus({ APP_STORE_URL: STORE, TESTFLIGHT_URL: BETA, APP_MINIMUM: "1.1" }, null)).toEqual({ testflightUrl: BETA });
  });

  test("once the store has a version: that version and its listing", () => {
    expect(appStatus({ TESTFLIGHT_URL: BETA }, "1.1")).toEqual({ latest: "1.1", storeUrl: STORE, testflightUrl: BETA });
    expect(appStatus({ APP_STORE_URL: "https://apps.apple.com/us/app/pounce/id6829560061" }, "1.1")).toEqual({
      latest: "1.1",
      storeUrl: "https://apps.apple.com/us/app/pounce/id6829560061",
    });
  });

  test("a minimum only once it can be met", () => {
    expect(appStatus({ APP_MINIMUM: "1.1" }, "1.2")).toEqual({ latest: "1.2", minimum: "1.1", storeUrl: STORE });
    expect(appStatus({ APP_MINIMUM: "1.3" }, "1.2")).toEqual({ latest: "1.2", storeUrl: STORE });
  });

  test("a link that isn't https is left out", () => {
    expect(appStatus({ TESTFLIGHT_URL: "javascript:alert(1)", APP_STORE_URL: "http://apps.apple.com/app/id6829560061" }, "1.1")).toEqual({
      latest: "1.1",
      storeUrl: STORE,
    });
  });
});

describe("refusalFor", () => {
  const ios = (version: string, protocol = 1) => parseApp(`platform=ios; version=${version}; build=1; protocol=${protocol}`);
  const never = () => Promise.reject(new Error("the store was asked"));
  const live = (version: string | null) => () => Promise.resolve(version);

  test("with no minimum everyone is served, and the store is never asked", async () => {
    expect(await refusalFor(ios("1.1"), {}, 1, never)).toBeNull();
    expect(await refusalFor(null, {}, 1, never)).toBeNull();
    expect(await refusalFor(null, { APP_MINIMUM: "" }, 1, never)).toBeNull();
  });

  test("an app at or above the minimum is served without asking the store", async () => {
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

  test("nobody is turned away for a version they can't download yet", async () => {
    expect(await refusalFor(ios("1.1"), { APP_MINIMUM: "1.2" }, 1, live("1.1"))).toBeNull();
    expect(await refusalFor(ios("1.1"), { APP_MINIMUM: "1.2" }, 1, live(null))).toBeNull();
    expect(await refusalFor(null, { APP_MINIMUM: "1.1" }, 1, live(null))).toBeNull();
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
