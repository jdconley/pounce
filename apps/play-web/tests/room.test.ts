import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { foldEvent, RoomStore, type Paced } from "../src/store/room";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { RoomView } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";

const game: CatTowerView = {
  round: 1,
  dealer: 0,
  turn: 1,
  step: "draw",
  status: "playing",
  deckCount: 80,
  discardTop: 5,
  discardCount: 1,
  phase: [0, 0],
  scores: [0, 0],
  laid: [null, null],
  handCounts: [10, 10],
  hands: { 0: [1, 2, 3] },
  pendingSkip: [false, false],
  winners: [],
  forfeited: [false, false],
};
const room = (over: Partial<RoomView> = {}): RoomView => ({
  code: "BCDFG",
  name: "t",
  status: "playing",
  youAreHost: true,
  seats: [
    { kind: "human", person: { id: "11111111-1111-4111-8111-111111111111", name: "Mia", cat: 1 }, yours: true, presence: "awake" },
    { kind: "bot", yours: false, presence: null },
  ],
  game,
  ...over,
});

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
  const played: Paced[] = [];
  store.subscribe({ event: (e) => played.push(e) });
  return { clock, sockets, store, played };
}

describe("the room store (RoomStore.swift)", () => {
  test("events play one at a time; the snapshot that follows lands after them", async () => {
    const { clock, sockets, store, played } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room() });
    expect(store.state.phase).toBe("playing");
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "game", event: { kind: "drew", seat: 1, from: "deck" } } });
    sockets[0]!.receive({ t: "event", seq: 3, event: { kind: "game", event: { kind: "discarded", seat: 1, card: 9 } } });
    const truth = room({ game: { ...game, turn: 0, discardTop: 9, discardCount: 2, deckCount: 79 } });
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 3, room: truth });
    expect(played.length).toBe(1);
    expect(store.state.room?.game?.handCounts[1]).toBe(11);
    clock.advance(420);
    expect(played.length).toBe(2);
    expect(store.state.room?.game?.discardTop).toBe(9);
    clock.advance(420);
    expect(store.state.room).toEqual(truth);
    // An event already applied is never played again.
    sockets[0]!.receive({ t: "event", seq: 3, event: { kind: "game", event: { kind: "turn", seat: 0 } } });
    expect(played.length).toBe(2);
  });

  test("a move carries an id, and is sent again after a reconnect unless the server applied it", async () => {
    const { clock, sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room({ link: { ping: 3000, acks: [] } }) });
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(true);
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(false);
    const sent = sockets[0]!.sent.find((m) => (m as { t: string }).t === "act") as { id: string };
    expect(sent.id).toMatch(/^[0-9a-f-]{32,36}$/);
    sockets[0]!.drop();
    clock.advance(250);
    await flush();
    sockets[1]!.open();
    sockets[1]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room({ link: { ping: 3000, acks: [] } }) });
    expect(sockets[1]!.sent).toContainEqual({ t: "act", seat: 0, action: { type: "draw", from: "deck" }, id: sent.id });
    sockets[1]!.receive({ t: "snapshot", protocol: 1, seq: 2, room: room({ link: { ping: 3000, acks: [sent.id] } }) });
    expect(store.state.pending).toBeNull();
  });

  test("a move stays in flight until its whole answer has played, so it can't be sent twice", async () => {
    const { clock, sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room({ link: { ping: 3000, acks: [] } }) });
    store.act(0, { type: "discard", card: 1 });
    const id = store.state.pending!.id;
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "game", event: { kind: "discarded", seat: 0, card: 1 } } });
    sockets[0]!.receive({ t: "event", seq: 3, event: { kind: "game", event: { kind: "turn", seat: 1 } } });
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 3, room: room({ link: { ping: 3000, acks: [id] } }) });
    expect(store.state.pending).not.toBeNull();
    expect(store.act(0, { type: "discard", card: 2 })).toBe(false);
    // Our own discard shows quickly (80 ms); the move settles when its answer's last event (the
    // turn passing) is shown, not before.
    clock.advance(79);
    expect(store.state.pending).not.toBeNull();
    clock.advance(1);
    expect(store.state.pending).toBeNull();
  });

  test("once the server has applied our move, a tap the table shows as live counts, even with events still playing", async () => {
    const { clock, sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    const linked = (acks: string[], over: Partial<RoomView> = {}) => room({ link: { ping: 3000, acks }, ...over });
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: linked([], { game: { ...game, turn: 0, step: "play" } }) });
    expect(store.act(0, { type: "discard", card: 1 })).toBe(true);
    const id = store.state.pending!.id;
    // Our discard and its ack, then the House Cat's whole turn, all before the queue has played.
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "game", event: { kind: "discarded", seat: 0, card: 1 } } });
    sockets[0]!.receive({ t: "event", seq: 3, event: { kind: "game", event: { kind: "turn", seat: 1 } } });
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 3, room: linked([id], { game: { ...game, turn: 1 } }) });
    sockets[0]!.receive({ t: "event", seq: 4, event: { kind: "game", event: { kind: "drew", seat: 1, from: "deck" } } });
    sockets[0]!.receive({ t: "event", seq: 5, event: { kind: "game", event: { kind: "discarded", seat: 1, card: 9 } } });
    sockets[0]!.receive({ t: "event", seq: 6, event: { kind: "game", event: { kind: "turn", seat: 0 } } });
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 6, room: linked([id], { game: { ...game, turn: 0, discardTop: 9 } }) });
    // Play until the turn comes back to us: the table now shows our deck as live.
    clock.advance(80 + 120 + 420 + 420);
    expect(store.state.room?.game?.turn).toBe(0);
    expect(store.state.room?.game?.step).toBe("draw");
    const sent = sockets[0]!.sent.length;
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(true);
    expect(sockets[0]!.sent.length).toBe(sent + 1);
    const draw = store.state.pending!;
    expect(draw.action).toEqual({ type: "draw", from: "deck" });
    // The deferred snapshot landing settles the old move, never the new one.
    clock.advance(500);
    expect(store.state.pending?.id).toBe(draw.id);
  });

  test("an answer already on stage settles the move at once, so a quick next move counts", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room({ link: { ping: 3000, acks: [] }, game: { ...game, turn: 0 } }) });
    store.act(0, { type: "draw", from: "deck" });
    const id = store.state.pending!.id;
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "game", event: { kind: "drew", seat: 0, from: "deck", card: 50 } } });
    // The drawn card is on stage; the server's answer follows before its pause ends.
    expect(store.state.room?.game?.hands[0]).toContain(50);
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 2, room: room({ link: { ping: 3000, acks: [id] }, game: { ...game, turn: 0, step: "play" } }) });
    expect(store.state.pending).toBeNull();
    expect(store.act(0, { type: "discard", card: 50 })).toBe(true);
  });

  test("a move the server hasn't applied still blocks a second one", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room({ link: { ping: 3000, acks: [] }, game: { ...game, turn: 0 } }) });
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(true);
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "game", event: { kind: "drew", seat: 0, from: "deck", card: 50 } } });
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(false);
  });

  test("a refused move clears; another protocol asks for the new build", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: room() });
    store.act(0, { type: "discard", card: 1 });
    sockets[0]!.receive({ t: "error", code: "bad_step" });
    expect(store.state.pending).toBeNull();
    expect(store.state.error?.code).toBe("bad_step");
    sockets[0]!.receive({ t: "snapshot", protocol: 2, seq: 5, room: room() });
    expect(store.state.phase).toBe("needsUpdate");
  });

  test("folding: tiles events move counts and the table", () => {
    const tiles = room({
      gameId: "tiles",
      game: null,
      tiles: { status: "playing", turn: 0, turns: 0, table: [], poolCount: 70, rackCounts: [14, 14], racks: { 0: [1] }, opened: [false, false], passed: [false, false], winners: [], scores: [0, 0], forfeited: [false, false] },
    });
    const after = foldEvent(tiles, { kind: "tiles", event: { kind: "played", seat: 1, table: [[1, 2, 3]], placed: [1, 2, 3], opened: true } });
    expect(after.tiles?.rackCounts).toEqual([14, 11]);
    expect(after.tiles?.table).toEqual([[1, 2, 3]]);
    expect(after.tiles?.opened).toEqual([false, true]);
  });
});
