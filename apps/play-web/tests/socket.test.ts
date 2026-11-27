import { describe, expect, test } from "vitest";

import { LinkMeter, RoomSocket, socketUrl, type SocketEvent } from "../src/net/socket";

import { Clock, FakeSocket, flush } from "./fake-socket";

function setup() {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const events: SocketEvent["kind"][] = [];
  let dropped = 0;
  const socket = new RoomSocket({
    code: "BCDFG",
    origin: "https://play.conleychaos.com",
    token: async () => "v1.device.mac",
    dropToken: () => dropped++,
    factory: (url, protocols) => {
      const s = new FakeSocket(url, protocols);
      sockets.push(s);
      return s;
    },
    now: () => clock.now,
    setTimer: clock.set,
    clearTimer: clock.clear,
  });
  socket.on((e) => events.push(e.kind));
  return { clock, sockets, events, socket, dropped: () => dropped };
}

const snapshot = (ping?: number) => ({
  t: "snapshot",
  protocol: 1,
  seq: 1,
  room: { code: "BCDFG", name: "x", status: "lobby", youAreHost: true, seats: [], game: null, ...(ping ? { link: { ping, acks: [] } } : {}) },
});

describe("the room socket (RoomSocket.swift)", () => {
  test("opens wss with the token as a subprotocol and the app's headers in the query", async () => {
    const { sockets, socket } = setup();
    socket.start();
    await flush();
    expect(sockets[0]?.protocols).toEqual(["pounce", "pounce.token.v1.device.mac"]);
    const url = new URL(sockets[0]!.url);
    expect(url.protocol).toBe("wss:");
    expect(url.pathname).toBe("/v1/rooms/BCDFG/ws");
    expect(url.searchParams.get("games")).toBe("cat-tower,tiles,birdwatch,tumble,purrtrait,dish");
    expect(url.searchParams.get("app")).toMatch(/^platform=web; version=\d{4}\.\d{4}\.\d{4}; protocol=1$/);
    expect(socketUrl("http://localhost:8787", "BCDFG")).toMatch(/^ws:\/\/localhost:8787\//);
    expect(socketUrl("http://localhost:8787", "BCDFG")).not.toContain("role=");
    expect(socketUrl("http://localhost:8787", "BCDFG", "screen")).toMatch(/&role=screen$/);
  });

  test("reconnects with backoff after a drop, and resets it on a snapshot", async () => {
    const { clock, sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.drop();
    expect(events).toEqual(["connecting", "connected", "disconnected"]);
    clock.advance(249);
    await flush();
    expect(sockets.length).toBe(1);
    clock.advance(1);
    await flush();
    expect(sockets.length).toBe(2);
    sockets[1]!.drop();
    clock.advance(499);
    await flush();
    expect(sockets.length).toBe(2);
    clock.advance(1);
    await flush();
    expect(sockets.length).toBe(3);
    sockets[2]!.open();
    sockets[2]!.receive(snapshot());
    sockets[2]!.drop();
    clock.advance(250);
    await flush();
    expect(sockets.length).toBe(4);
  });

  test("close codes end it: 4404 not found, 4429 locked, 4426 refused; 4401 drops the token and retries", async () => {
    for (const [code, kind] of [[4404, "notFound"], [4429, "locked"], [4426, "refused"]] as const) {
      const { sockets, events, socket, clock } = setup();
      socket.start();
      await flush();
      sockets[0]!.drop(code);
      expect(events.at(-1)).toBe(kind);
      clock.advance(10_000);
      await flush();
      expect(sockets.length).toBe(1);
    }
    const { sockets, socket, clock, dropped } = setup();
    socket.start();
    await flush();
    sockets[0]!.drop(4401);
    expect(dropped()).toBe(1);
    clock.advance(250);
    await flush();
    expect(sockets.length).toBe(2);
  });

  test("4403 (a room that doesn't list this screen) is final: not found, never reconnects", async () => {
    const { sockets, events, socket, clock } = setup();
    socket.start();
    await flush();
    sockets[0]!.drop(4403);
    expect(events.at(-1)).toBe("notFound");
    clock.advance(60_000);
    await flush();
    expect(sockets.length).toBe(1);
  });

  test("heartbeats once the server takes them; silence for 10 s reconnects", async () => {
    const { clock, sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive(snapshot(3000));
    clock.advance(500);
    expect(sockets[0]!.sent).toContainEqual({ t: "ping" });
    sockets[0]!.receive({ t: "pong" });
    clock.advance(3000);
    expect(sockets[0]!.sent.filter((m) => (m as { t: string }).t === "ping").length).toBe(2);
    // No pong: weak after 1.5 s (the server is told), dead after 10 s.
    clock.advance(1500);
    expect(events).toContain("link");
    expect(sockets[0]!.sent).toContainEqual({ t: "link", state: "weak" });
    const before = events.length;
    clock.advance(9000);
    await flush();
    expect(events.slice(before)).toEqual(["disconnected", "connecting"]);
    expect(sockets.length).toBe(2);
  });

  test("a room that closes ends the socket", async () => {
    const { sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "error", code: "room_closed" });
    expect(events.slice(-2)).toEqual(["message", "closed"]);
  });

  test("the link meter: weak on a slow pong, good after two quick ones", () => {
    const m = new LinkMeter({ pingEvery: 3000, weakAfter: 1500, goodUnder: 1000, goodPongs: 2, deadAfter: 10_000 }, 0);
    expect(m.shouldPing(0)).toBe(true);
    m.pingSent(0);
    expect(m.shouldPing(100)).toBe(false);
    m.pong(1600);
    expect(m.quality).toBe("weak");
    m.pingSent(5000);
    m.pong(5100);
    expect(m.quality).toBe("weak");
    m.pingSent(9000);
    m.pong(9100);
    expect(m.quality).toBe("good");
    m.pingSent(12_000);
    expect(m.tick(22_000)).toBe("dead");
  });
});

describe("the API client", () => {
  test("a sign-up limit is waited out; a token the server refuses is replaced once", async () => {
    const { Api } = await import("../src/net/api");
    let mints = 0;
    let calls = 0;
    const fetcher = (async (url: string, init?: RequestInit) => {
      if (String(url).endsWith("/v1/devices")) {
        mints++;
        if (mints === 1) return new Response(JSON.stringify({ error: "rate_limited" }), { status: 429 });
        return new Response(JSON.stringify({ deviceId: `d${mints}`, token: `t${mints}` }), { status: 200 });
      }
      calls++;
      const auth = (init?.headers as Record<string, string>).authorization;
      if (auth === "Bearer t2") return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
      return new Response(JSON.stringify({ tables: [] }), { status: 200 });
    }) as typeof fetch;
    const api = new Api("http://x", fetcher);
    api.mintRetryMs = 1;
    await expect(api.listTables()).resolves.toEqual([]);
    expect(mints).toBe(3);
    expect(calls).toBe(2);
  });
});
