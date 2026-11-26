// @vitest-environment happy-dom
/**
 * The Birdwatch table drawn from every snapshot the server's samples hold, as a page that opens
 * mid-hand would (a reload, a second device): nothing is seen first, everything comes from the
 * snapshot. And a refused play puts the card back.
 */
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { beforeAll, describe, expect, test } from "vitest";

import raw from "../../play-api/fixtures/protocol/birdwatch-server-messages.json";
import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";
import { BirdwatchTable } from "../src/table/birdwatch";
import { TvTable } from "../src/ui/tv/tv-table";


import { Clock, FakeSocket, flush } from "./fake-socket";

import type { ServerMessage } from "@pounce/play-api/protocol";

type Sample = { name: string; message: ServerMessage };
const samples = raw as unknown as Sample[];

beforeAll(() => {
  // happy-dom has no Web Animations or ResizeObserver; the table only needs them to exist.
  (Element.prototype as unknown as { animate: () => unknown }).animate = () => ({ cancel() {}, finished: Promise.resolve(), onfinish: null });
  (Element.prototype as unknown as { getAnimations: () => unknown[] }).getAnimations = () => [];
  globalThis.ResizeObserver ??= class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
  globalThis.matchMedia ??= ((q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} })) as unknown as typeof matchMedia;
});

async function storeWith(message: ServerMessage) {
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
  const store = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, setTimer: clock.set, clearTimer: clock.clear, now: () => clock.now });
  store.start();
  await flush();
  sockets[0]!.open();
  sockets[0]!.receive(message);
  return { store, socket: sockets[0]! };
}

describe("the Birdwatch table from a snapshot", () => {
  const playing = samples.filter((s) => s.message.t === "snapshot" && s.message.room.birdwatch);

  test.each(playing.map((s) => [s.name, s] as const))("%s draws on a phone and on the TV", async (_name, s) => {
    const { store } = await storeWith(s.message);
    const root = document.createElement("div");
    document.body.append(root);
    act(() => render(h(BirdwatchTable, { store, state: store.state }), root));
    const v = store.state.room!.birdwatch!;
    // The strip says every side's score; the trump badge says the trump.
    const strip = root.querySelector("#bw-strip")!.getAttribute("aria-label")!;
    for (const score of v.scores) expect(strip).toContain(String(score));
    if (v.trump) expect(root.querySelector("#bw-trump")!.getAttribute("aria-label")).toContain(v.trump);
    // Only this device's own hand is drawn, and only the cards the server lists may play.
    const mine = Object.values(v.hands).flat();
    const drawn = root.querySelectorAll(".bw-hand-card");
    expect(drawn.length).toBeLessThanOrEqual(mine.length);
    if (v.playable && drawn.length > 0) expect(root.querySelectorAll(".bw-hand-card:not(.dim)").length).toBe(v.playable.length);
    // The partner mark only on the partner's own device, before the reveal.
    expect(root.querySelector("#bw-partner-mark") !== null).toBe(v.youArePartner !== undefined && v.partner === null && drawn.length > 0);
    act(() => render(null, root));

    act(() => render(h(TvTable, { store, state: store.state, offline: false }), root));
    expect(root.querySelector(".bw-hand-card")).toBeNull();
    expect(root.querySelector("#bw-partner-mark")).toBeNull();
    act(() => render(null, root));
    root.remove();
    store.stop();
  });

  test("a refused play puts the card back", async () => {
    const s = samples.find((x) => x.name === "snapshot-play-lead")!;
    const { store, socket } = await storeWith(s.message);
    const root = document.createElement("div");
    document.body.append(root);
    const draw = () => act(() => render(h(BirdwatchTable, { store, state: store.state }), root));
    draw();
    const v = store.state.room!.birdwatch!;
    const card = v.playable![0]!;
    const seat = v.turn!;
    act(() => {
      store.act(seat, { type: "play", card });
    });
    expect(store.state.pending).not.toBeNull();
    socket.receive({ t: "error", code: "must_follow" });
    draw();
    expect(store.state.pending).toBeNull();
    expect(root.querySelectorAll(".bw-hand-card").length).toBe(v.hands[seat]!.length);
    act(() => render(null, root));
    root.remove();
    store.stop();
  });
});
