import { beforeEach, describe, expect, test } from "vitest";

import { store } from "../src/lib/kv";
import { Api, ApiError } from "../src/net/api";
import { ScreenLink, type ScreenLinkEvent } from "../src/net/screen-link";

import { Clock, FakeSocket, flush } from "./fake-socket";

type Call = { url: string; method: string; headers: Record<string, string>; body: unknown };

function fakeFetch(respond: (call: Call) => { status: number; body?: unknown }) {
  const calls: Call[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    const call: Call = {
      url: url.replace("http://x", ""),
      method: String(init.method),
      headers: init.headers as Record<string, string>,
      body: init.body ? JSON.parse(String(init.body)) : undefined,
    };
    calls.push(call);
    const r = respond(call);
    return new Response(r.body === undefined ? null : JSON.stringify(r.body), { status: r.status });
  }) as typeof fetch;
  return { calls, fetcher };
}

const CRED = { deviceId: "d1", token: "tok" };

beforeEach(() => {
  store.remove("pounce.device");
  store.remove("pounce.tv.device");
});

describe("a credential key", () => {
  test("an Api with its own key reads and writes only that key", async () => {
    store.set("pounce.device", JSON.stringify({ deviceId: "phone", token: "phone-token" }));
    const { calls, fetcher } = fakeFetch((c) => (c.url === "/v1/devices" ? { status: 201, body: CRED } : { status: 200, body: {} }));
    const tv = new Api("http://x", fetcher, "pounce.tv.device");
    expect(tv.stored()).toBeNull();
    await tv.credential();
    expect(calls).toHaveLength(1);
    expect(store.json("pounce.tv.device")).toEqual(CRED);
    expect(store.json("pounce.device")).toEqual({ deviceId: "phone", token: "phone-token" });
    expect(new Api("http://x", fetcher).stored()?.token).toBe("phone-token");
  });

  test("a refused token drops only its own key", async () => {
    store.set("pounce.device", JSON.stringify({ deviceId: "phone", token: "phone-token" }));
    store.set("pounce.tv.device", JSON.stringify({ deviceId: "tv", token: "old" }));
    let minted = 0;
    const { fetcher } = fakeFetch((c) => {
      if (c.url === "/v1/devices") return { status: 201, body: { deviceId: "tv2", token: `new${++minted}` } };
      return c.headers.authorization === "Bearer old" ? { status: 401, body: { error: "unauthorized" } } : { status: 200, body: { tables: [] } };
    });
    const tv = new Api("http://x", fetcher, "pounce.tv.device");
    await tv.listTables();
    expect(store.json<{ token: string }>("pounce.tv.device")?.token).toBe("new1");
    expect(store.json<{ token: string }>("pounce.device")?.token).toBe("phone-token");
  });
});

describe("a socket's refused token", () => {
  test("forget() drops the kept credential (only its own key), and the next call mints a new one", async () => {
    store.set("pounce.device", JSON.stringify({ deviceId: "phone", token: "phone-token" }));
    store.set("pounce.tv.device", JSON.stringify({ deviceId: "tv", token: "old" }));
    const { calls, fetcher } = fakeFetch(() => ({ status: 201, body: { deviceId: "tv2", token: "new" } }));
    const tv = new Api("http://x", fetcher, "pounce.tv.device");
    expect((await tv.credential()).token).toBe("old");
    tv.forget();
    expect(store.json("pounce.tv.device")).toBeNull();
    expect(store.json<{ token: string }>("pounce.device")?.token).toBe("phone-token");
    expect((await tv.credential()).token).toBe("new");
    expect(calls.map((c) => c.url)).toEqual(["/v1/devices"]);
  });
});

describe("screens and links", () => {
  const api = (respond: Parameters<typeof fakeFetch>[0]) => {
    store.set("pounce.device", JSON.stringify(CRED));
    const f = fakeFetch(respond);
    return { ...f, api: new Api("http://x", f.fetcher) };
  };

  test("screens() posts an empty body, or the room it shows", async () => {
    const out = { token: "t", code: "ABCD", url: "https://x/tv/t", expiresIn: 600_000 };
    const { api: a, calls } = api(() => ({ status: 201, body: out }));
    expect(await a.screens()).toEqual(out);
    await a.screens("BCDFG");
    expect(calls.map((c) => [c.method, c.url, c.body])).toEqual([
      ["POST", "/v1/screens", {}],
      ["POST", "/v1/screens", { showing: "BCDFG" }],
    ]);
    expect(calls[0]!.headers.authorization).toBe("Bearer tok");
  });

  test("linkScreen() sends a token or a code, the room, and move", async () => {
    const { api: a, calls } = api(() => ({ status: 200, body: { linked: true } }));
    expect(await a.linkScreen({ token: "t1" }, "BCDFG")).toBe("linked");
    expect(await a.linkScreen({ code: "ABCD" }, "BCDFG", true)).toBe("linked");
    expect(calls.map((c) => [c.url, c.body])).toEqual([
      ["/v1/screens/link", { token: "t1", room: "BCDFG" }],
      ["/v1/screens/link", { code: "ABCD", room: "BCDFG", move: true }],
    ]);
  });

  test("a screen already showing another table is 'showing', not an error", async () => {
    const { api: a } = api(() => ({ status: 409, body: { error: "showing" } }));
    expect(await a.linkScreen({ code: "ABCD" }, "BCDFG")).toBe("showing");
  });

  test("404, 403 and 429 are ApiErrors; 429 carries retryAfter", async () => {
    for (const [status, body] of [
      [404, { error: "not_found" }],
      [403, { error: "not_seated" }],
    ] as const) {
      const { api: a } = api(() => ({ status, body }));
      await expect(a.linkScreen({ code: "ABCD" }, "BCDFG")).rejects.toMatchObject({ status, code: body.error });
    }
    const { api: a } = api(() => ({ status: 429, body: { error: "too_many_attempts", retryAfter: 42 } }));
    const error = await a.linkScreen({ code: "ABCD" }, "BCDFG").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 429, code: "too_many_attempts", retryAfter: 42 });
  });

  test("createRoom asks for a screen with no name", async () => {
    const { api: a, calls } = api(() => ({ status: 201, body: { code: "BCDFG" } }));
    expect(await a.createRoom("tiles", { screen: true })).toBe("BCDFG");
    await a.createRoom("tiles", "Sardines");
    await a.createRoom("tiles");
    expect(calls.map((c) => c.body)).toEqual([{ game: "tiles", screen: true }, { game: "tiles", name: "Sardines" }, { game: "tiles" }]);
  });
});

describe("the screen link (a TV waiting to be linked)", () => {
  /** `expiresIn` is in milliseconds, as the server sends it. */
  function setup(expiresIn = 100_000) {
    const release = { hold: false, fail: false, go: () => undefined as void, waiting: null as null | (() => void) };
    const clock = new Clock();
    const sockets: FakeSocket[] = [];
    let n = 0;
    const asked: (string | undefined)[] = [];
    const api = {
      credential: async () => ({ deviceId: "tv", token: "tvtok" }),
      screens: async (showing?: string) => {
        if (release.fail) throw new Error("offline");
        if (release.hold) await new Promise<void>((r) => (release.waiting = r));
        asked.push(showing);
        n += 1;
        return { token: `tok${n}`, code: `CODE${n}`, url: `https://x/tv/tok${n}`, expiresIn };
      },
    } as unknown as Api;
    const events: ScreenLinkEvent[] = [];
    const link = new ScreenLink({
      api,
      origin: "https://play.example",
      factory: (url, p) => {
        const s = new FakeSocket(url, p);
        sockets.push(s);
        return s;
      },
      setTimer: clock.set,
      clearTimer: clock.clear,
    });
    link.on((e) => events.push(e));
    release.go = () => release.waiting?.();
    return { clock, sockets, events, link, asked, release };
  }

  test("emits the code, and listens on the token's socket as the device", async () => {
    const { sockets, events, link } = setup();
    link.start();
    await flush();
    expect(events).toEqual([{ kind: "code", token: "tok1", code: "CODE1", url: "https://x/tv/tok1" }]);
    const url = new URL(sockets[0]!.url);
    expect(url.protocol).toBe("wss:");
    expect(url.pathname).toBe("/v1/screens/tok1/ws");
    expect(sockets[0]!.protocols).toEqual(["pounce", "pounce.token.tvtok"]);
  });

  test("asks to show a table when given one", async () => {
    const { asked, link } = setup();
    link.start("BCDFG");
    await flush();
    expect(asked).toEqual(["BCDFG"]);
  });

  test("renews at 80%: a new code, a new socket, the old one closed", async () => {
    const { clock, sockets, events, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    clock.advance(79_999);
    await flush();
    expect(sockets).toHaveLength(1);
    clock.advance(1);
    await flush();
    expect(sockets).toHaveLength(2);
    sockets[1]!.open();
    expect(sockets[0]!.readyState).toBe(3);
    expect(events.map((e) => e.kind === "code" && e.token)).toEqual(["tok1", "tok2"]);
    expect(new URL(sockets[1]!.url).pathname).toBe("/v1/screens/tok2/ws");
  });

  test("a 600000 ms link (the server's 10 minutes) renews at 480000 ms", async () => {
    const { clock, sockets, events, link } = setup(600_000);
    link.start();
    await flush();
    sockets[0]!.open();
    clock.advance(479_999);
    await flush();
    expect(events.filter((e) => e.kind === "code")).toHaveLength(1);
    clock.advance(1);
    await flush();
    expect(events.filter((e) => e.kind === "code")).toHaveLength(2);
  });

  test("the server's expired message renews at once", async () => {
    const { sockets, events, link } = setup();
    link.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "expired" });
    await flush();
    expect(sockets).toHaveLength(2);
    expect(events.filter((e) => e.kind === "code")).toHaveLength(2);
  });

  test("linked is passed on, and the link stops (no renewal, no reconnect)", async () => {
    const { clock, sockets, events, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "linked", room: "BCDFG" });
    expect(events.at(-1)).toEqual({ kind: "linked", room: "BCDFG" });
    sockets[0]!.drop(1000);
    clock.advance(200_000);
    await flush();
    expect(sockets).toHaveLength(1);
  });

  test("a board link (the Daily Dish) is passed on with its token, and the link stops", async () => {
    const { clock, sockets, events, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "board" });
    expect(events.at(-1)?.kind).toBe("code");
    sockets[0]!.receive({ t: "board", token: "B".repeat(22) });
    expect(events.at(-1)).toEqual({ kind: "board", token: "B".repeat(22) });
    clock.advance(200_000);
    await flush();
    expect(sockets).toHaveLength(1);
  });

  test("a code linked while its renewal is still asking is not lost", async () => {
    const { clock, sockets, events, link, release } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    release.hold = true;
    clock.advance(80_000);
    await flush();
    expect(sockets).toHaveLength(1);
    sockets[0]!.receive({ t: "linked", room: "BCDFG" });
    expect(events.at(-1)).toEqual({ kind: "linked", room: "BCDFG" });
    release.go();
    await flush();
    expect(sockets).toHaveLength(1);
  });

  test("a renewal that fails leaves the old socket open", async () => {
    const { clock, sockets, events, link, release } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    release.fail = true;
    clock.advance(80_000);
    await flush();
    expect(sockets[0]!.readyState).toBe(1);
    expect(events.filter((e) => e.kind === "offline")).toHaveLength(0);
    sockets[0]!.receive({ t: "linked", room: "BCDFG" });
    expect(events.at(-1)).toEqual({ kind: "linked", room: "BCDFG" });
  });

  test("the old socket closes once the new one is open, and a link on either wins", async () => {
    const { clock, sockets, events, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    clock.advance(80_000);
    await flush();
    expect(sockets).toHaveLength(2);
    expect(sockets[0]!.readyState).toBe(1);
    sockets[0]!.receive({ t: "linked", room: "BCDFG" });
    expect(events.at(-1)).toEqual({ kind: "linked", room: "BCDFG" });
    expect(sockets[1]!.readyState).toBe(3);
  });

  test("the old socket is closed when the new one opens", async () => {
    const { clock, sockets, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    clock.advance(80_000);
    await flush();
    sockets[1]!.open();
    expect(sockets[0]!.readyState).toBe(3);
  });

  test("a dropped socket reconnects to the same token with backoff", async () => {
    const { clock, sockets, events, link } = setup(1000);
    link.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.drop();
    expect(events.at(-1)).toEqual({ kind: "offline" });
    clock.advance(250);
    await flush();
    expect(sockets).toHaveLength(2);
    expect(new URL(sockets[1]!.url).pathname).toBe("/v1/screens/tok1/ws");
    sockets[1]!.drop();
    clock.advance(499);
    await flush();
    expect(sockets).toHaveLength(2);
    clock.advance(1);
    await flush();
    expect(sockets).toHaveLength(3);
  });

  test("answers a ping with a pong", async () => {
    const { sockets, link } = setup();
    link.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "ping" });
    expect(sockets[0]!.sent).toContainEqual({ t: "pong" });
  });

  test("stop closes the socket and ends renewals", async () => {
    const { clock, sockets, link } = setup(100_000);
    link.start();
    await flush();
    sockets[0]!.open();
    link.stop();
    expect(sockets[0]!.readyState).toBe(3);
    clock.advance(200_000);
    await flush();
    expect(sockets).toHaveLength(1);
  });
});
