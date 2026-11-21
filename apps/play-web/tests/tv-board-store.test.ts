import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { TvBoardStore, type TvBoardNews } from "../src/store/tv-board";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { Api } from "../src/net/api";
import type { BoardMessage } from "@pounce/play-api/daily/messages";

const socket = JSON.parse(readFileSync(new URL("../../play-api/fixtures/daily/protocol/socket.json", import.meta.url), "utf8")) as Record<string, BoardMessage>;

async function setup() {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const news: TvBoardNews[] = [];
  const api = { credential: async () => ({ deviceId: "tv", token: "tvtok" }), forget: () => undefined } as unknown as Api;
  const store = new TvBoardStore({
    api,
    board: "B".repeat(22),
    origin: "https://play.example",
    factory: (url, p) => {
      const s = new FakeSocket(url, p);
      sockets.push(s);
      return s;
    },
    now: () => clock.now,
    setTimer: clock.set,
    clearTimer: clock.clear,
  });
  let changes = 0;
  store.subscribe({ change: () => changes++, news: (n) => news.push(n) });
  store.start();
  await flush();
  sockets[0]!.open();
  return { clock, sockets, news, store, changes: () => changes };
}

describe("the TV's board store", () => {
  test("shows what the socket says", async () => {
    const { sockets, store, changes } = await setup();
    sockets[0]!.receive(socket.board);
    expect(store.state.screen.board?.games[0]?.game).toBe("test");
    expect(store.state.online).toBe(true);
    expect(changes()).toBeGreaterThan(0);
  });

  test("a result cheers, and the cheer ends on its own", async () => {
    const { clock, sockets, news, store } = await setup();
    sockets[0]!.receive(socket.board);
    sockets[0]!.receive(socket.result);
    expect(news).toContainEqual({ kind: "cheer", solved: true });
    expect(store.state.screen.cheer).not.toBeNull();
    clock.advance(2401);
    expect(store.state.screen.cheer).toBeNull();
  });

  test("the watch card goes after 20 seconds", async () => {
    const { clock, sockets, news, store } = await setup();
    sockets[0]!.receive(socket.watchOffer);
    expect(news).toContainEqual({ kind: "offer" });
    clock.advance(20_000);
    expect(store.state.screen.offer).not.toBeNull();
    clock.advance(1);
    expect(store.state.screen.offer).toBeNull();
  });

  test("Watch, then the run's end, then the board", async () => {
    const { clock, sockets, store } = await setup();
    sockets[0]!.receive(socket.watchOffer);
    sockets[0]!.receive(socket.watch);
    store.watch();
    expect(store.state.screen.watching?.player).toBe("pr_8tGqLm2vXc9RzK1wYb4NdA");
    sockets[0]!.receive(socket.watchEnd);
    expect(store.state.screen.ended).not.toBeNull();
    clock.advance(6001);
    expect(store.state.screen.watching).toBeNull();
  });

  test("Not now and Back", async () => {
    const { sockets, store } = await setup();
    sockets[0]!.receive(socket.watchOffer);
    store.notNow();
    expect(store.state.screen.offer).toBeNull();
    sockets[0]!.receive(socket.watchOffer);
    store.watch();
    store.stopWatching();
    expect(store.state.screen.watching).toBeNull();
  });

  test("a gone board is news, once", async () => {
    const { sockets, news } = await setup();
    sockets[0]!.drop(4404);
    expect(news.filter((n) => n.kind === "gone")).toHaveLength(1);
  });

  test("offline while the socket is down", async () => {
    const { sockets, store } = await setup();
    sockets[0]!.drop(1006);
    expect(store.state.online).toBe(false);
  });
});
