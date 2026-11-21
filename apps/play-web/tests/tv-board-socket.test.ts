import { describe, expect, test } from "vitest";

import { BoardSocket, dailyOn, type BoardSocketEvent } from "../src/net/tv-board-socket";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { Api } from "../src/net/api";

const BOARD = "B".repeat(22);

function setup() {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const events: BoardSocketEvent[] = [];
  let forgot = 0;
  const api = { credential: async () => ({ deviceId: "tv", token: "tvtok" }), forget: () => void forgot++ } as unknown as Api;
  const socket = new BoardSocket({
    api,
    board: BOARD,
    origin: "https://play.example",
    factory: (url, p) => {
      const s = new FakeSocket(url, p);
      sockets.push(s);
      return s;
    },
    setTimer: clock.set,
    clearTimer: clock.clear,
  });
  socket.on((e) => events.push(e));
  return { clock, sockets, events, socket, forgot: () => forgot };
}

/** A close with a reason, as the server's revoke sends it. */
const closeWith = (s: FakeSocket, code: number, reason: string) => {
  s.readyState = 3;
  s.onclose?.({ code, reason } as CloseEvent);
};

describe("the TV's board socket", () => {
  test("opens the board's socket as the TV's device", async () => {
    const { sockets, socket } = setup();
    socket.start();
    await flush();
    const url = new URL(sockets[0]!.url);
    expect(url.protocol).toBe("wss:");
    expect(url.pathname).toBe("/v1/daily/board/ws");
    expect(url.searchParams.get("board")).toBe(BOARD);
    expect(sockets[0]!.protocols).toEqual(["pounce", "pounce.token.tvtok"]);
  });

  test("passes on each message, and drops what isn't JSON", async () => {
    const { sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.onmessage?.({ data: "nope" } as MessageEvent);
    sockets[0]!.receive({ t: "tvs", count: 1 });
    expect(events).toEqual([{ kind: "online" }, { kind: "message", message: { t: "tvs", count: 1 } }]);
  });

  test("pings to keep the socket honest", async () => {
    const { clock, sockets, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    clock.advance(25_000);
    expect(sockets[0]!.sent).toEqual([{ t: "ping" }]);
  });

  test("a board the server doesn't know (404) is gone, and not tried again", async () => {
    const { clock, sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.drop(4404);
    clock.advance(60_000);
    await flush();
    expect(events).toEqual([{ kind: "gone" }]);
    expect(sockets).toHaveLength(1);
  });

  test("an unlink or an expiry closes it for good", async () => {
    for (const reason of ["revoked", "expired"]) {
      const { clock, sockets, events, socket } = setup();
      socket.start();
      await flush();
      sockets[0]!.open();
      closeWith(sockets[0]!, 1000, reason);
      clock.advance(60_000);
      await flush();
      expect(events.at(-1)).toEqual({ kind: "gone" });
      expect(sockets).toHaveLength(1);
    }
  });

  test("a dropped socket says offline and comes back", async () => {
    const { clock, sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.drop(1006);
    expect(events.at(-1)).toEqual({ kind: "offline" });
    clock.advance(250);
    await flush();
    expect(sockets).toHaveLength(2);
  });

  test("a refused device token is forgotten, and the socket tries again", async () => {
    const { clock, sockets, socket, forgot } = setup();
    socket.start();
    await flush();
    sockets[0]!.drop(4401);
    expect(forgot()).toBe(1);
    clock.advance(250);
    await flush();
    expect(sockets).toHaveLength(2);
  });

  test("stopped, it closes and says nothing more", async () => {
    const { clock, sockets, events, socket } = setup();
    socket.start();
    await flush();
    sockets[0]!.open();
    socket.stop();
    sockets[0]!.drop(1006);
    clock.advance(60_000);
    await flush();
    expect(events).toEqual([{ kind: "online" }]);
    expect(sockets).toHaveLength(1);
  });
});

describe("whether the Dish is on", () => {
  const api = { credential: async () => ({ deviceId: "tv", token: "tvtok" }) } as unknown as Api;
  const answering = (status: number) => (async () => new Response(null, { status })) as unknown as typeof fetch;

  test("on when the board socket asks for an upgrade (426), off for anything else", async () => {
    expect(await dailyOn(api, "https://play.example", answering(426))).toBe(true);
    expect(await dailyOn(api, "https://play.example", answering(404))).toBe(false);
    expect(await dailyOn(api, "https://play.example", (async () => Promise.reject(new Error("offline"))) as unknown as typeof fetch)).toBe(false);
  });

  test("asks as the TV's device", async () => {
    let asked: { url: string; auth: string } | null = null;
    const spy = (async (url: string, init: RequestInit) => {
      asked = { url, auth: (init.headers as Record<string, string>).authorization! };
      return new Response(null, { status: 426 });
    }) as unknown as typeof fetch;
    await dailyOn(api, "https://play.example", spy);
    expect(asked).toEqual({ url: "https://play.example/v1/daily/board/ws", auth: "Bearer tvtok" });
  });
});
