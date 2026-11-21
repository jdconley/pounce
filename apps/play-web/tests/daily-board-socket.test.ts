import { describe, expect, test } from "vitest";

import socketSamples from "../../play-api/fixtures/daily/protocol/socket.json";
import { BoardSocket, type BoardEvent } from "../src/daily/board-socket";

import { Clock, FakeSocket, flush } from "./fake-socket";

const S = socketSamples as Record<string, Record<string, unknown>>;

function setup() {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const events: BoardEvent[] = [];
  let dropped = 0;
  const socket = new BoardSocket({
    person: "pe_1",
    origin: "https://play.conleychaos.com",
    token: async () => "v1.device.mac",
    dropToken: () => dropped++,
    factory: (url, protocols) => {
      const s = new FakeSocket(url, protocols);
      sockets.push(s);
      return s;
    },
    setTimer: clock.set,
    clearTimer: clock.clear,
  });
  socket.start((e) => events.push(e));
  return { clock, sockets, events, socket, dropped: () => dropped };
}

describe("the board socket", () => {
  test("opens the person's board with the token as a subprotocol", async () => {
    const { sockets } = setup();
    await flush();
    expect(sockets[0]!.protocols).toEqual(["pounce", "pounce.token.v1.device.mac"]);
    const url = new URL(sockets[0]!.url);
    expect(url.protocol).toBe("wss:");
    expect(url.pathname).toBe("/v1/daily/board/ws");
    expect(url.searchParams.get("person")).toBe("pe_1");
    expect(url.searchParams.get("app")).toMatch(/^platform=web/);
  });

  test("hears the board, results, progress and the TV count, and skips the rest", async () => {
    const { sockets, events } = setup();
    await flush();
    const ws = sockets[0]!;
    ws.open();
    for (const key of ["board", "result", "progress", "tvs", "watchOffer", "watch", "watchEnd", "pong", "error"]) ws.receive(S[key]);
    ws.receive({ t: "somethingNew", x: 1 });
    ws.onmessage?.({ data: "not json" } as MessageEvent);
    expect(events.map((e) => e.kind)).toEqual(["board", "result", "progress", "tvs"]);
    expect(events[0]).toEqual({ kind: "board", board: S.board!.board });
    expect(events[1]).toEqual({ kind: "result", player: S.result!.player, result: S.result!.result });
    expect(events[3]).toEqual({ kind: "tvs", count: S.tvs!.count });
  });

  test("pings every 3 seconds once open", async () => {
    const { clock, sockets } = setup();
    await flush();
    sockets[0]!.open();
    clock.advance(3000);
    expect(sockets[0]!.sent).toEqual([{ t: "ping" }]);
  });

  test("reconnects with backoff after a drop", async () => {
    const { clock, sockets } = setup();
    await flush();
    sockets[0]!.open();
    sockets[0]!.drop();
    clock.advance(249);
    await flush();
    expect(sockets).toHaveLength(1);
    clock.advance(1);
    await flush();
    expect(sockets).toHaveLength(2);
  });

  test("a refused token is dropped and tried again; a 404 ends it", async () => {
    const { clock, sockets, events, dropped } = setup();
    await flush();
    sockets[0]!.drop(4401);
    expect(dropped()).toBe(1);
    clock.advance(250);
    await flush();
    sockets[1]!.drop(4404);
    expect(events.at(-1)).toEqual({ kind: "gone" });
    clock.advance(60_000);
    await flush();
    expect(sockets).toHaveLength(2);
  });

  test("stop closes it for good", async () => {
    const { clock, sockets, socket } = setup();
    await flush();
    sockets[0]!.open();
    socket.stop();
    expect(sockets[0]!.readyState).toBe(3);
    clock.advance(60_000);
    await flush();
    expect(sockets).toHaveLength(1);
  });
});
