// @vitest-environment happy-dom
/**
 * The Toy Tumble screens drawn from a snapshot and the live stream, as a page that opens mid-round
 * would: the player's box with every opponent as a mini (chips at a TV table), the tray and the
 * 3-2-1; round over; watching once out; and the TV page joining mid-round, drawing every box from
 * one sync, with names, wins, held tricks and a junk meter.
 */
import { newBox, type Box } from "@pounce/play-api/tumble/box";
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";
import { TumbleTable } from "../src/tumble/screen";
import { TvTable } from "../src/ui/tv/tv-table";

import { FakeSocket, flush } from "./fake-socket";

import type { TumbleRoom } from "../src/tumble/store";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Seed } from "@pounce/play-api/rules/rng";

const NAMES = ["Alice", "Bob", "Cleo", "Dev", "Esme", "Finn"];

beforeAll(() => {
  (Element.prototype as unknown as { animate: () => unknown }).animate = () => ({ cancel() {}, finished: Promise.resolve(), onfinish: null });
  globalThis.ResizeObserver ??= class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
  globalThis.matchMedia ??= ((q: string) => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {} })) as unknown as typeof matchMedia;
});

function room(n: number, mine: number, t: Partial<TumbleRoom> = {}, extra: Partial<RoomView> = {}): RoomView {
  return {
    code: "BCDFG",
    name: "Toy Box",
    status: "playing",
    youAreHost: true,
    seats: NAMES.slice(0, n).map((name, i) => ({ kind: "human" as const, person: { id: `${i}1111111-1111-4111-8111-111111111111`, name, cat: i }, yours: i === mine, presence: "awake" as const })),
    game: null,
    gameId: "tumble" as never,
    ...extra,
    tumble: {
      seats: n,
      cats: "easy",
      wins: Array<number>(n).fill(0),
      left: Array<boolean>(n).fill(false),
      away: Array<boolean>(n).fill(false),
      status: "playing",
      r: 2,
      startsAt: Date.now() - 5000,
      roundSeed: [1, 2, 3, 4],
      trickSeeds: Array.from({ length: n }, (_, i): Seed => [i + 1, 2, 3, 4]),
      outs: [],
      winner: null,
      waitingSince: null,
      ...t,
    },
  } as RoomView;
}

async function storeWith(r: RoomView, role?: "screen") {
  const sockets: FakeSocket[] = [];
  const socket = new RoomSocket({
    code: "BCDFG",
    origin: "http://x",
    token: async () => "tok",
    role,
    factory: (url, p) => {
      const s = new FakeSocket(url, p);
      sockets.push(s);
      return s;
    },
  });
  const store = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, role });
  store.start();
  await flush();
  sockets[0]!.open();
  sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: r });
  return { store, ws: sockets[0]! };
}

let root: HTMLDivElement;
let stop: (() => void) | null = null;
afterEach(() => {
  act(() => render(null, root));
  root.remove();
  stop?.();
});

async function draw(r: RoomView, which: "phone" | "tv" = "phone") {
  const { store, ws } = await storeWith(r, which === "tv" ? "screen" : undefined);
  stop = () => store.stop();
  root = document.createElement("div");
  document.body.append(root);
  const paint = () => act(() => render(which === "tv" ? h(TvTable, { store, state: store.state, offline: false }) : h(TumbleTable, { store, state: store.state }), root));
  paint();
  return { store, ws, paint };
}

describe("the player screen", () => {
  test("six players: your box, five minis, the tray and your number", async () => {
    await draw(room(6, 2));
    expect(root.querySelector("#tt-box")).not.toBeNull();
    expect(root.querySelectorAll(".tt-mini").length).toBe(5);
    expect(root.querySelectorAll(".tt-chip").length).toBe(0);
    expect(root.querySelectorAll(".tt-slot").length).toBe(6);
    expect(root.querySelector(".tt-rim .tt-num")?.textContent).toBe("3");
    expect([...root.querySelectorAll(".tt-mini")].map((m) => m.getAttribute("aria-label"))).toEqual(["Alice", "Bob", "Dev", "Esme", "Finn"]);
  });

  test("at a TV table, the minis are chips", async () => {
    await draw(room(4, 0, {}, { screen: true }));
    expect(root.querySelectorAll(".tt-chip").length).toBe(3);
    expect(root.querySelectorAll(".tt-mini").length).toBe(0);
  });

  test("the countdown says the round and counts down", async () => {
    await draw(room(2, 0, { status: "countdown", startsAt: Date.now() + 2500 }));
    await act(async () => {
      await new Promise((r) => requestAnimationFrame(() => r(null)));
    });
    expect(root.querySelector(".tt-count-round")?.textContent).toBe("Round 2");
    expect(root.querySelector(".tt-count-n")?.textContent).toBe("3");
  });

  test("out of the round: every box big, with yours marked Out", async () => {
    await draw(room(3, 1, { outs: [1] }));
    expect(root.querySelector("#tt-box")).toBeNull();
    expect(root.querySelectorAll(".tt-mini.watch").length).toBe(3);
    expect(root.querySelector(".tt-mini.watch.out .tt-state")?.textContent).toBe("Out");
  });

  test("round over: the winner's cat on top, and You win the round on the winner's phone", async () => {
    await draw(room(3, 1, { status: "between", winner: 1, wins: [0, 2, 1] }));
    expect(root.querySelector(".tt-over h2")?.textContent).toBe("You win the round");
    expect(root.querySelector(".tt-over-winner .name-tag")?.textContent).toBe("Bob");
    expect(root.querySelectorAll(".tt-over-paws li").length).toBe(3);
    expect(root.querySelectorAll(".tt-over-paws li.won .tt-paws i.on").length).toBe(2);
  });

  test("round over on another phone names no one as you", async () => {
    await draw(room(3, 0, { status: "between", winner: 1, wins: [0, 1, 0] }));
    expect(root.querySelector(".tt-over h2")).toBeNull();
  });
});

describe("the TV page", () => {
  test("joining mid-round, one sync of six boxes draws all six, with names, wins, tricks and the meter", async () => {
    const r = room(6, -1, { wins: [1, 0, 2, 0, 0, 1] }, { screen: true });
    const { ws, paint } = await draw(r, "tv");
    const boxes: Box[] = Array.from({ length: 6 }, (_, s) => ({ ...newBox([s + 1, 2, 3, 4]), held: s === 3 ? ["hairball", "nap"] : [], waiting: s === 4 ? [{ id: 9, rows: 2, gap: 3 }] : [] }));
    ws.receive({ t: "tumbleSync", r: 2, boxes: boxes.map((box, s) => ({ s, box, q: 10, waitingLeft: s === 4 ? [1200] : [], catnipLeft: 0, napLeft: 0, status: s === 5 ? "lag" : "ok" })) });
    paint();
    await act(async () => {
      await new Promise((res) => requestAnimationFrame(() => res(null)));
    });
    const shown = [...root.querySelectorAll(".tt-tv-box")];
    expect(shown.length).toBe(6);
    expect(shown.map((b) => b.getAttribute("aria-label"))).toEqual(NAMES);
    expect(shown.map((b) => b.querySelectorAll(".tt-paws i.on").length)).toEqual([1, 0, 2, 0, 0, 1]);
    expect(shown[3]!.querySelector(".tt-tv-tricks")?.getAttribute("aria-label")).toBe("Hairball, Nap");
    expect(shown[5]!.querySelector(".tt-state")?.textContent).toBe("Reconnecting");
    expect(shown.map((b) => b.getAttribute("data-junk"))).toEqual(["0", "0", "0", "0", "2", "0"]);
    // All in one row.
    const ys = new Set(shown.map((b) => (b as HTMLElement).style.transform.split(",")[1]));
    expect(ys.size).toBe(1);
    expect(root.querySelector(".tt-tv-round")?.textContent).toBe("Round 2");
  });
});
