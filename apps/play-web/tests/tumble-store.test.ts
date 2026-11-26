/**
 * Toy Tumble through the room store, as the page gets it: the snapshot's `tumble` field makes
 * this device's box and replays the rest, every live sample the server's fixtures hold decodes
 * and lands, and a gap, a hidden tab or a lost connection asks for a sync.
 */
import { readFileSync } from "node:fs";

import { parseClientMessage, type RoomView, type ServerMessage } from "@pounce/play-api/protocol";
import { newBox } from "@pounce/play-api/tumble/box";
import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";
import { catsOf, TumbleStore, type TumbleRoom } from "../src/tumble/store";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { ClientEvent, TumbleServer } from "@pounce/play-api/tumble/wire";

type Sample = { name: string; message: unknown };
const read = (f: string): Sample[] => JSON.parse(readFileSync(new URL(`../../play-api/fixtures/protocol/${f}`, import.meta.url), "utf8")) as Sample[];
const serverSamples = read("tumble-server-messages.json");
const clientSamples = read("tumble-client-messages.json");
const sample = (name: string): TumbleServer => structuredClone(serverSamples.find((s) => s.name === name)!.message) as TumbleServer;

const START = 1_000_000;

function tumbleRoom(t: Partial<TumbleRoom> = {}, mine = 1): RoomView {
  const people = ["Alice", "Bob", "Cleo"];
  return {
    code: "BCDFG",
    name: "Toy Box",
    status: "playing",
    youAreHost: true,
    seats: people.map((name, i) => ({ kind: "human" as const, person: { id: `${i}1111111-1111-4111-8111-111111111111`, name, cat: i }, yours: i === mine, presence: "awake" as const })),
    game: null,
    gameId: "tumble" as never,
    tumble: {
      seats: 3,
      cats: "easy",
      wins: [0, 0, 0],
      left: [false, false, false],
      away: [false, false, false],
      status: "countdown",
      r: 2,
      startsAt: START,
      roundSeed: [1, 2, 3, 4],
      trickSeeds: [[5, 6, 7, 8], [1, 1, 1, 1], [3, 3, 3, 3]],
      outs: [],
      winner: null,
      waitingSince: null,
      ...t,
    },
  } as RoomView;
}

async function setup() {
  const clock = new Clock();
  clock.now = START - 3000;
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
  const room = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, setTimer: clock.set, clearTimer: clock.clear, now: () => clock.now });
  const tumble = new TumbleStore({ room, now: () => clock.now });
  tumble.start();
  room.start();
  await flush();
  sockets[0]!.open();
  const ws = sockets[0]!;
  const snapshot = (r: RoomView, seq = 1) => ws.receive({ t: "snapshot", protocol: 1, seq, room: r } satisfies ServerMessage);
  const tumbleSent = () => ws.sent.filter((m): m is { t: "tumble"; r: number; ev: ClientEvent[] } => (m as { t: string }).t === "tumble");
  return { clock, ws, sockets, room, tumble, snapshot, tumbleSent };
}

describe("the round from the snapshot", () => {
  test("a countdown makes this device's box and replays every other one", async () => {
    const { tumble, snapshot } = await setup();
    snapshot(tumbleRoom());
    expect(tumble.r).toBe(2);
    expect(tumble.mySeat).toBe(1);
    expect(tumble.local?.seat).toBe(1);
    expect(tumble.replay?.seats()).toEqual([0, 2]);
    expect(tumble.players).toEqual([0, 1, 2]);
    expect(tumble.countdown(START - 3000)).toBe(3000);
  });

  test("a device with no seat (the TV) replays every box", async () => {
    const { tumble, snapshot } = await setup();
    snapshot(tumbleRoom({}, -1));
    expect(tumble.local).toBeNull();
    expect(tumble.replay?.seats()).toEqual([0, 1, 2]);
  });

  test("the round's end clears the boxes, and the next round makes new ones", async () => {
    const { tumble, snapshot } = await setup();
    snapshot(tumbleRoom());
    snapshot(tumbleRoom({ status: "between", winner: 0, wins: [1, 0, 0] }), 2);
    expect(tumble.local).toBeNull();
    expect(tumble.replay).toBeNull();
    expect(tumble.room?.winner).toBe(0);
    snapshot(tumbleRoom({ status: "countdown", r: 3 }), 3);
    expect(tumble.r).toBe(3);
    expect(tumble.local).not.toBeNull();
  });

  test("away and left seats sit the round out and say so; an out seat is out", async () => {
    const { tumble, snapshot } = await setup();
    snapshot(tumbleRoom({ status: "playing", away: [false, false, true], left: [true, false, false] }));
    expect(tumble.players).toEqual([1]);
    expect(tumble.seatState(2)).toBe("away");
    expect(tumble.seatState(0)).toBe("left");
    snapshot(tumbleRoom({ status: "playing", outs: [1] }), 2);
    expect(tumble.seatState(1)).toBe("out");
  });

  test("the House Cat level reads from the table's options, Easy by default", () => {
    expect(catsOf(tumbleRoom())).toBe("easy");
    expect(catsOf({ ...tumbleRoom(), options: { cats: "quick" } as never })).toBe("quick");
  });
});

describe("the live stream", () => {
  test("every server sample decodes and lands", async () => {
    const { ws, tumble, snapshot, clock, tumbleSent } = await setup();
    // Seat 2 is this device's here, so the samples' boxes 0 and 1 are replayed.
    snapshot(tumbleRoom({ status: "playing" }, 2));
    clock.now = START + 100;
    expect(serverSamples.length).toBe(14);
    for (const s of serverSamples) ws.receive(s.message);
    // The sync's boxes landed, with seat 1's lag.
    expect(tumble.view(0)?.box.waiting).toEqual([{ id: 3, rows: 2, gap: 9 }]);
    expect(tumble.view(0)?.napLeft).toBe(6400);
    expect(tumble.seatState(1)).toBe("ok");
    // Hits to this seat (2): hairball and bath, each acked at once.
    const acks = tumbleSent().flatMap((m) => m.ev).filter((e) => e[0] === "a").map((e) => e[1]);
    expect(acks).toEqual([32, 38]);
    expect(tumble.takeFx().filter((f) => f.k === "hit").length).toBe(serverSamples.filter((s) => (s.message as { t: string }).t === "tumbleHit").length);
  });

  test("samples arrive through the socket, not paced like room events", async () => {
    const { ws, tumble, snapshot, clock } = await setup();
    snapshot(tumbleRoom({ status: "playing" }, 2));
    clock.now = START + 100;
    ws.receive(sample("tumble-sync"));
    expect(tumble.view(1)?.state).toBe("lag");
    ws.receive(sample("tumble-seat-ok"));
    expect(tumble.view(1)?.state).toBe("ok");
  });

  test("a sync that beats the snapshot is kept for the round", async () => {
    const { ws, tumble, snapshot, clock } = await setup();
    clock.now = START + 100;
    ws.receive(sample("tumble-sync"));
    snapshot(tumbleRoom({ status: "playing" }, 2));
    expect(tumble.view(0)?.box.next).toBe(1);
  });

  test("every batch this box sends is one the server's parser takes, like the client samples", async () => {
    for (const s of clientSamples) expect(parseClientMessage(JSON.stringify(s.message)), s.name).toEqual(s.message);
    const { tumble, snapshot, clock, tumbleSent } = await setup();
    snapshot(tumbleRoom({ status: "playing" }));
    for (let i = 0; i < 400 && !tumble.local!.view().box.out; i++) {
      clock.now = START + i * 30;
      tumble.frame();
      if (i % 3 === 0) tumble.local!.move(i % 2 === 0 ? -1 : 1);
      if (i % 7 === 0) tumble.local!.turn(1);
      if (i % 20 === 0) tumble.local!.drop();
    }
    expect(tumbleSent().length).toBeGreaterThan(10);
    for (const m of tumbleSent()) expect(parseClientMessage(JSON.stringify(m))).toEqual(m);
  });
});

describe("asking for a sync", () => {
  test("a gap in a box's q asks once, again after a second, and stops once the sync comes", async () => {
    const { ws, tumble, snapshot, clock, tumbleSent } = await setup();
    snapshot(tumbleRoom({ status: "playing" }));
    clock.now = START + 10;
    ws.receive({ t: "tumble", r: 2, s: 0, q: 1, ev: [] });
    ws.receive({ t: "tumble", r: 2, s: 0, q: 3, ev: [] });
    tumble.frame();
    tumble.frame();
    const asks = () => tumbleSent().filter((m) => m.ev.length === 0).length;
    expect(asks()).toBe(1);
    clock.now += 1000;
    tumble.frame();
    expect(asks()).toBe(2);
    ws.receive({ t: "tumbleSync", r: 2, boxes: [{ s: 0, box: newBox([5, 6, 7, 8]), q: 3, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }] });
    clock.now += 2000;
    tumble.frame();
    expect(asks()).toBe(2);
  });

  test("a hidden tab stops the box, and coming back asks for a sync before it steps again", async () => {
    const { ws, tumble, snapshot, clock, tumbleSent } = await setup();
    snapshot(tumbleRoom({ status: "playing" }));
    clock.now = START;
    tumble.frame();
    const y = tumble.view(1)!.toy!.y;
    tumble.setHidden(true);
    clock.now = START + 8000;
    tumble.setHidden(false);
    expect(tumbleSent().at(-1)).toEqual({ t: "tumble", r: 2, ev: [] });
    tumble.frame();
    expect(tumble.view(1)!.toy!.y).toBe(y);
    ws.receive({ t: "tumbleSync", r: 2, boxes: [{ s: 1, box: newBox([1, 1, 1, 1]), q: 0, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }] });
    clock.now += 1000;
    tumble.frame();
    expect(tumble.view(1)!.toy!.y).toBe(y - 1);
  });

  test("a lost connection holds the box; back online, it asks for a sync", async () => {
    const { ws, sockets, tumble, snapshot, clock, tumbleSent } = await setup();
    snapshot(tumbleRoom({ status: "playing" }));
    clock.now = START;
    tumble.frame();
    ws.drop();
    expect(tumble.local?.stale).toBe(true);
    expect(tumbleSent().every((m) => m.ev.length > 0)).toBe(true);
    clock.advance(2000);
    await flush();
    const again = sockets.at(-1)!;
    expect(again).not.toBe(ws);
    again.open();
    expect(again.sent).toContainEqual({ t: "tumble", r: 2, ev: [] });
  });
});
