/**
 * Birdwatch on the wire: every sample the server made from real rooms
 * (apps/play-api/fixtures/protocol/birdwatch-*.json) goes through the room store as the page gets
 * it, and every event folds into the shown view the way the next snapshot will say.
 */
import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { eventPause, foldEvent, RoomStore } from "../src/store/room";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { BirdEvent } from "@pounce/play-api/birdwatch/engine";
import type { BirdView } from "@pounce/play-api/birdwatch/view";
import type { RoomEvent, RoomView, ServerMessage } from "@pounce/play-api/protocol";

type Sample = { name: string; message: ServerMessage };
const samples = JSON.parse(readFileSync(new URL("../../play-api/fixtures/protocol/birdwatch-server-messages.json", import.meta.url), "utf8")) as Sample[];
export const sample = (name: string): ServerMessage => {
  const found = samples.find((s) => s.name === name);
  if (!found) throw new Error(`no sample ${name}`);
  return structuredClone(found.message);
};
const snapshotRoom = (name: string): RoomView => (sample(name) as Extract<ServerMessage, { t: "snapshot" }>).room;
const bird = (name: string): BirdView => snapshotRoom(name).birdwatch!;
const ev = (e: BirdEvent): RoomEvent => ({ kind: "birdwatch", event: e });

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
  const store = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, setTimer: clock.set, clearTimer: clock.clear, now: () => clock.now });
  return { clock, sockets, store };
}

describe("Birdwatch samples through the store", () => {
  test("every snapshot lands, with its view under `birdwatch`", async () => {
    const snapshots = samples.filter((s) => s.message.t === "snapshot");
    expect(snapshots.length).toBe(19);
    for (const s of snapshots) {
      const { sockets, store } = setup();
      store.start();
      await flush();
      sockets[0]!.open();
      sockets[0]!.receive(s.message);
      const room = store.state.room!;
      expect(room.gameId, s.name).toBe("birdwatch");
      expect((room.options as { rules?: string } | undefined)?.rules, s.name).toMatch(/^(official|tucker|friesen)$/);
      if (room.status === "lobby") expect(room.birdwatch).toBeUndefined();
      else expect(room.birdwatch?.teams.length, s.name).toBeGreaterThan(0);
      store.stop();
    }
  });

  test("every event plays and every new error is seen", async () => {
    const { clock, sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive(sample("snapshot-play-follow"));
    const events = samples.filter((s) => s.message.t === "event");
    let seq = 100;
    for (const e of events) sockets[0]!.receive({ ...(e.message as Extract<ServerMessage, { t: "event" }>), seq: seq++ });
    clock.advance(60_000);
    for (const e of samples.filter((s) => s.message.t === "error")) {
      sockets[0]!.receive(e.message);
      expect(store.state.error?.code).toBe((e.message as { code: string }).code);
    }
  });

  test("Birdwatch events hold the stage long enough to see", () => {
    expect(eventPause(ev({ kind: "played", seat: 0, card: 3 }))).toBe(520);
    expect(eventPause(ev({ kind: "trick", winner: 0, cards: [], points: 0 }))).toBe(900);
    expect(eventPause(ev({ kind: "turn", seat: 0 }))).toBe(0);
  });
});

describe("folding Birdwatch events", () => {
  const fold = (room: RoomView, e: BirdEvent) => foldEvent(room, ev(e)).birdwatch!;

  test("a bid and a pass show on the signs", () => {
    const room = snapshotRoom("snapshot-bidding-watching");
    const after = fold(room, { kind: "bid", seat: 2, amount: 85 });
    expect(after.bids[2]).toBe(85);
    expect(after.high).toEqual({ seat: 2, amount: 85 });
    expect(after.bidRange).toBeUndefined();
    expect(fold(room, { kind: "passed", seat: 3 }).passed[3]).toBe(true);
  });

  test("a played card leaves the hand for the sill, and a trick sweeps to its winner", () => {
    const room = snapshotRoom("snapshot-play-lead");
    const v = room.birdwatch!;
    const seat = Number(Object.keys(v.hands)[0]);
    const card = v.hands[seat]![0]!;
    const played = fold(room, { kind: "played", seat, card });
    expect(played.hands[seat]).not.toContain(card);
    expect(played.handCounts[seat]).toBe(v.handCounts[seat]! - 1);
    expect(played.trick.at(-1)).toEqual({ seat, card });
    expect(played.playable).toBeUndefined();
    const swept = foldEvent({ ...room, birdwatch: played }, ev({ kind: "trick", winner: seat, cards: played.trick, points: 15 })).birdwatch!;
    expect(swept.trick).toEqual([]);
    expect(swept.lastTrick).toEqual({ cards: played.trick, winner: seat });
    expect(swept.points[seat]).toBe(v.points[seat]! + 15);
    expect(swept.leader).toBe(seat);
  });

  test("the nest comes in and goes back on the bid winner's device only", () => {
    const room = snapshotRoom("snapshot-trump-bid-winner");
    const v = room.birdwatch!;
    const seat = v.high!.seat;
    const before = { ...room, birdwatch: { ...v, phase: "nest" as const, hands: { [seat]: [1, 2, 3] } } };
    const took = fold(before, { kind: "nest", seat, cards: [40, 41] });
    expect(took.hands[seat]).toEqual([1, 2, 3, 40, 41]);
    expect(took.fromNest).toEqual([40, 41]);
    const back = foldEvent({ ...before, birdwatch: took }, ev({ kind: "putBack", seat, count: 2, cards: [1, 40] })).birdwatch!;
    expect(back.hands[seat]).toEqual([2, 3, 41]);
    expect(back.phase).toBe("trump");
    expect(back.fromNest).toBeUndefined();
    expect(back.putBack).toEqual([1, 40]);
  });

  test("trump leads to the partner call with 5 players, else to play", () => {
    expect(fold(snapshotRoom("snapshot-trump-bid-winner"), { kind: "trump", seat: 0, suit: "bell" }).phase).toBe(bird("snapshot-trump-bid-winner").seats === 5 ? "partner" : "play");
    const five = snapshotRoom("snapshot-five-partner-call");
    expect(five.birdwatch!.seats).toBe(5);
    expect(fold(five, { kind: "trump", seat: 0, suit: "bell" }).phase).toBe("partner");
    const called = fold(five, { kind: "called", seat: 0, card: 42 });
    expect(called.called).toBe(42);
    expect(called.phase).toBe("play");
    expect(fold(snapshotRoom("snapshot-five-partner-hidden"), { kind: "partner", seat: 4 }).partner).toBe(4);
  });

  test("a new deal clears the last hand", () => {
    const room = snapshotRoom("snapshot-between");
    const dealt = fold(room, { kind: "dealt", hand: 9, dealer: 2, handCounts: [9, 9, 9, 9], hands: { 0: [1, 2] } });
    expect(dealt.phase).toBe("bidding");
    expect(dealt.hand).toBe(9);
    expect(dealt.hands).toEqual({ 0: [1, 2] });
    expect(dealt.trick).toEqual([]);
    expect(dealt.trump).toBeNull();
    expect(dealt.bids.every((b) => b === null)).toBe(true);
    expect(dealt.putBack).toBeUndefined();
  });

  test("a hand's end and the game's end", () => {
    const room = snapshotRoom("snapshot-play-after-trick");
    const result = { hand: 3, bidder: 1, bid: 85, partner: null, trump: "fish" as const, made: true, taken: [30, 90], change: [30, 90], totals: [145, 210] };
    const over = fold(room, { kind: "handOver", result, putBack: [5, 7] });
    expect(over.phase).toBe("between");
    expect(over.scores).toEqual([145, 210]);
    expect(over.history.at(-1)).toEqual(result);
    const done = fold(room, { kind: "gameOver", winners: [1, 3], scores: [145, 310], reason: "target" });
    expect(done.status).toBe("over");
    expect(done.winners).toEqual([1, 3]);
    expect(done.endReason).toBe("target");
  });

  test("a House Cat takes over a seat that left", () => {
    const room = snapshotRoom("snapshot-play-watching");
    const after = foldEvent(room, { kind: "houseCat", seat: 2 });
    expect(after.seats[2]).toMatchObject({ kind: "bot", left: true, yours: false });
    expect(after.seats[2]!.person).toEqual(room.seats[2]!.person);
  });
});
