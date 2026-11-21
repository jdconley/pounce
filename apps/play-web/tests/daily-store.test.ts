import { describe, expect, test } from "vitest";

import http from "../../play-api/fixtures/daily/protocol/http.json";
import { DishStore, myRow } from "../src/daily/dish-store";
import { ApiError } from "../src/net/api";

import { flush } from "./fake-socket";

import type { BoardEvent } from "../src/daily/board-socket";
import type { BoardAnswer } from "@pounce/play-api/daily/messages";

const BOARD = (http as { board: BoardAnswer }).board;
const STATS = (http as { stats: unknown }).stats;

function setup(answer: (path: string) => unknown) {
  const calls: string[] = [];
  let on: ((e: BoardEvent) => void) | null = null;
  let stopped = 0;
  const store = new DishStore({
    call: async (_m, path) => {
      calls.push(path);
      const a = answer(path);
      if (a instanceof Error) throw a;
      return new Response(JSON.stringify(a), { status: 200 });
    },
    socket: () => ({
      start: (fn) => void (on = fn),
      stop: () => void stopped++,
    }),
  });
  return { store, calls, emit: (e: BoardEvent) => on?.(e), stopped: () => stopped };
}

describe("the Dish store", () => {
  test("off on 404: no socket, nothing shown", async () => {
    const { store, calls } = setup(() => new ApiError(404, "not_found"));
    const release = store.retain("pe_1");
    await flush();
    expect(store.state.status).toBe("off");
    expect(calls).toEqual(["/v1/daily/board?person=pe_1"]);
    release();
  });

  test("on with the board, its stats and its TV count", async () => {
    const { store } = setup((p) => (p.startsWith("/v1/daily/board") ? BOARD : STATS));
    store.retain("pe_1");
    await flush();
    await flush();
    expect(store.state.status).toBe("on");
    expect(store.state.board).toEqual(BOARD);
    expect(store.state.tvs).toBe(1);
    expect(store.state.stats?.test?.played).toBe(1);
  });

  test("offline keeps it unknown, and a later load turns it on", async () => {
    let up = false;
    const { store } = setup((p) => (!up ? new ApiError(0, "offline") : p.startsWith("/v1/daily/board") ? BOARD : STATS));
    store.retain("pe_1");
    await flush();
    expect(store.state.status).toBe("unknown");
    up = true;
    await store.refresh();
    expect(store.state.status).toBe("on");
  });

  test("a 403 before the first profile save lands: hidden, then loaded once it lands", async () => {
    let saved = false;
    const { store } = setup((p) => (!saved ? new ApiError(403, "forbidden") : p.startsWith("/v1/daily/board") ? BOARD : STATS));
    store.retain("pe_1");
    await flush();
    expect(store.state.status).toBe("unknown");
    saved = true;
    store.profileSaved("pe_1");
    await flush();
    await flush();
    expect(store.state.status).toBe("on");
  });

  test("the profile save landing while a refused load is still out loads again after it", async () => {
    let saved = false;
    let answer: () => void = () => {};
    const calls: string[] = [];
    const store = new DishStore({
      call: async (_m, path) => {
        calls.push(path);
        if (!saved) {
          // The refused load is still on its way when the save lands.
          await new Promise<void>((done) => (answer = done));
          throw new ApiError(403, "forbidden");
        }
        return new Response(JSON.stringify(path.startsWith("/v1/daily/board") ? BOARD : STATS), { status: 200 });
      },
      socket: () => ({ start: () => {}, stop: () => {} }),
    });
    store.retain("pe_1");
    await flush();
    saved = true;
    store.profileSaved("pe_1");
    answer();
    await flush();
    await flush();
    await flush();
    expect(store.state.status).toBe("on");
    expect(calls.filter((c) => c.startsWith("/v1/daily/board"))).toHaveLength(2);
  });

  test("a 404 answered while the save was landing (the player still being made) loads again", async () => {
    let made = false;
    let answer: () => void = () => {};
    const calls: string[] = [];
    const store = new DishStore({
      call: async (_m, path) => {
        calls.push(path);
        if (!made) {
          await new Promise<void>((done) => (answer = done));
          throw new ApiError(404, "no_player");
        }
        return new Response(JSON.stringify(path.startsWith("/v1/daily/board") ? BOARD : STATS), { status: 200 });
      },
      socket: () => ({ start: () => {}, stop: () => {} }),
    });
    store.retain("pe_1");
    await flush();
    made = true;
    store.profileSaved("pe_1");
    answer();
    await flush();
    await flush();
    await flush();
    expect(store.state.status).toBe("on");
  });

  test("the profile save landing while a load that works is out asks nothing more", async () => {
    let answer: () => void = () => {};
    const calls: string[] = [];
    const store = new DishStore({
      call: async (_m, path) => {
        calls.push(path);
        if (path.startsWith("/v1/daily/board")) await new Promise<void>((done) => (answer = done));
        return new Response(JSON.stringify(path.startsWith("/v1/daily/board") ? BOARD : STATS), { status: 200 });
      },
      socket: () => ({ start: () => {}, stop: () => {} }),
    });
    store.retain("pe_1");
    await flush();
    store.profileSaved("pe_1");
    answer();
    await flush();
    await flush();
    await flush();
    expect(store.state.status).toBe("on");
    expect(calls.filter((c) => c.startsWith("/v1/daily/board"))).toHaveLength(1);
  });

  test("the profile saving again leaves a shown Dish alone, and another person's save does nothing", async () => {
    const { store, calls } = setup((p) => (p.startsWith("/v1/daily/board") ? BOARD : STATS));
    store.retain("pe_1");
    await flush();
    await flush();
    const before = calls.length;
    store.profileSaved("pe_1");
    store.profileSaved("pe_2");
    await flush();
    expect(calls).toHaveLength(before);
  });

  test("live: a result fills its row, progress moves it, tvs counts, the next board replaces it", async () => {
    const { store, emit } = setup((p) => (p.startsWith("/v1/daily/board") ? BOARD : STATS));
    store.retain("pe_1");
    await flush();
    await flush();
    const grandpa = BOARD.games[0]!.rows[2]!.player;
    emit({ kind: "progress", player: grandpa, game: "test", progress: 0.75 });
    expect(store.state.board!.games[0]!.rows[2]!.playing).toEqual({ progress: 0.75 });
    const result = { ...BOARD.games[0]!.rows[0]!.result!, outcome: "solved" as const, timeMs: 1000 };
    emit({ kind: "result", player: grandpa, result });
    expect(store.state.board!.games[0]!.rows[2]!.result).toEqual(result);
    expect(store.state.board!.games[0]!.rows[2]!.playing).toBeNull();
    emit({ kind: "tvs", count: 0 });
    expect(store.state.tvs).toBe(0);
    emit({ kind: "board", board: { ...BOARD, tvs: 2 } });
    expect(store.state.board!.tvs).toBe(2);
    expect(store.state.tvs).toBe(2);
  });

  test("the socket closes when the last screen lets go, and a new person starts over", async () => {
    const { store, stopped, calls } = setup((p) => (p.startsWith("/v1/daily/board") ? BOARD : STATS));
    const a = store.retain("pe_1");
    const b = store.retain("pe_1");
    await flush();
    a();
    expect(stopped()).toBe(0);
    b();
    expect(stopped()).toBe(1);
    store.retain("pe_2");
    await flush();
    expect(calls.at(-2)).toBe("/v1/daily/board?person=pe_2");
  });

  test("myRow is the board owner's row for a game", () => {
    expect(myRow(BOARD, "test")?.name).toBe("Mom");
    expect(myRow(BOARD, "sniff")).toBeNull();
  });
});
