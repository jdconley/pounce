import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";

import { Clock, FakeSocket, flush } from "./fake-socket";

/**
 * A TV table, read by the store as it is today: a snapshot says `screen: true` (applied as any
 * other), and the server relays `aim` messages, which the store skips. The samples are play-api's
 * `fixtures/protocol/screen-server-messages.json`.
 */
const samples = JSON.parse(
  readFileSync(new URL("../../play-api/fixtures/protocol/screen-server-messages.json", import.meta.url), "utf8"),
) as Record<"snapshot" | "tilesSnapshot" | "aim" | "tilesAim" | "aimClear", { t: string; room?: { screen?: boolean; code: string } }>;

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

  test("aims change nothing, and break nothing after them", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive(samples.snapshot);
    const before = structuredClone(store.state);
    for (const name of ["aim", "tilesAim", "aimClear"] as const) {
      expect(samples[name].t).toBe("aim");
      expect(() => sockets[0]!.receive(samples[name])).not.toThrow();
      expect(store.state, name).toEqual(before);
    }
    // Still reading: the next snapshot lands.
    sockets[0]!.receive(samples.tilesSnapshot);
    expect(store.state.room).toEqual(samples.tilesSnapshot.room);
    expect(store.state.error).toBeNull();
  });
});
