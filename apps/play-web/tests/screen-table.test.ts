import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";

import { Clock, FakeSocket, flush } from "./fake-socket";

/**
 * A TV table, read by the store as it is today: a snapshot says `screen: true` (applied as any
 * other), and the server relays `aim` messages, which the store keeps in `aims` and nowhere else.
 * The samples are play-api's `fixtures/protocol/screen-server-messages.json`.
 */
const samples = JSON.parse(
  readFileSync(new URL("../../play-api/fixtures/protocol/screen-server-messages.json", import.meta.url), "utf8"),
) as Record<"snapshot" | "tilesSnapshot" | "aim" | "tilesAim" | "aimClear", { t: string; seat?: number; aim?: unknown; room?: { screen?: boolean; code: string } }>;

function setup() {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const socket = new RoomSocket({
    code: "BCDFG",
    origin: "http://x",
    token: async () => "tok",
    factory: (url, p) => {
      const s = new FakeSocket(url, p);
      sockets.push(s);
      return s;
    },
    now: () => clock.now,
    setTimer: clock.set,
    clearTimer: clock.clear,
  });
  const store = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, setTimer: clock.set, clearTimer: clock.clear });
  return { clock, sockets, store };
}

describe("a TV table, to the store as it is", () => {
  test.each(["snapshot", "tilesSnapshot"] as const)("a %s with screen: true is applied as it is", async (name) => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    expect(samples[name].room?.screen).toBe(true);
    sockets[0]!.receive(samples[name]);
    expect(store.state.phase).toBe("playing");
    expect(store.state.room).toEqual(samples[name].room);
    expect(store.state.error).toBeNull();
  });

  test("a table that doesn't list this screen (4403) ends it: not found, no reconnect", async () => {
    const { clock, sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive(samples.snapshot);
    sockets[0]!.drop(4403);
    expect(store.state.phase).toBe("notFound");
    clock.advance(60_000);
    await flush();
    expect(sockets).toHaveLength(1);
  });

  test("an aim sets only aims; a snapshot after it lands; a clear removes it", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive(samples.snapshot);
    const before = structuredClone(store.state);
    for (const name of ["aim", "tilesAim"] as const) {
      expect(samples[name].t).toBe("aim");
      sockets[0]!.receive(samples[name]);
      expect(store.state, name).toEqual({ ...before, aims: { [samples[name].seat!]: samples[name].aim } });
    }
    // Still reading: the next snapshot lands.
    sockets[0]!.receive(samples.tilesSnapshot);
    expect(store.state.room).toEqual(samples.tilesSnapshot.room);
    expect(store.state.error).toBeNull();
    // A clear takes the seat's aim away, and nothing else.
    sockets[0]!.receive(samples.tilesAim);
    const aimed = structuredClone(store.state);
    expect(aimed.aims[0]).toEqual(samples.tilesAim.aim);
    expect(samples.aimClear.aim).toBeUndefined();
    sockets[0]!.receive(samples.aimClear);
    expect(store.state).toEqual({ ...aimed, aims: {} });
  });
});
