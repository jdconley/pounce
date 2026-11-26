import { describe, expect, test } from "vitest";

import { RoomSocket } from "../src/net/socket";
import { RoomStore } from "../src/store/room";
import {
  clock,
  easelLink,
  foldPurr,
  leftNow,
  nextDrawer,
  purrOf,
  purrOverTitle,
  purrStandings,
  revealLine,
  roleOf,
  spacedCode,
  turnLine,
  type InkMessage,
  type PurrView,
} from "../src/table/purr-model";

import { Clock, FakeSocket, flush } from "./fake-socket";

import type { RoomView } from "@pounce/play-api/protocol";

export function purrView(over: Partial<PurrView> = {}): PurrView {
  return {
    seats: 4,
    timer: 60,
    rounds: 2,
    phase: "drawing",
    round: 1,
    drawer: 1,
    order: [0, 1, 2, 3],
    scores: [0, 0, 0, 0],
    out: [false, false, false, false],
    group: "animals",
    level: "easy",
    remainingMs: 42_000,
    paused: false,
    turn: "1:1",
    last: null,
    winners: [],
    ...over,
  };
}

export function purrRoom(v: PurrView | null, yours: number[] = [0], extra: Record<string, unknown> = {}): RoomView {
  const names = ["Mom", "Dad", "Ava", "Leo", "Mochi", "Bea", "Cy", "Di", "Eli", "Fay"];
  return {
    code: "BCDFG",
    name: "Couch",
    status: v === null ? "lobby" : v.phase === "over" ? "over" : "playing",
    youAreHost: yours.includes(0),
    seats: Array.from({ length: v?.seats ?? 4 }, (_, i) => ({
      kind: "human" as const,
      person: { id: `00000000-0000-4000-8000-00000000000${i}`, name: names[i]!, cat: i % 8 },
      yours: yours.includes(i),
      presence: "awake" as const,
    })),
    game: null,
    gameId: "purrtrait" as unknown as "tiles",
    options: { timer: 60 } as unknown as RoomView["options"],
    ...(v ? { purrtrait: v } : {}),
    ...extra,
  } as RoomView;
}

describe("what the screens say", () => {
  test("the clock", () => {
    expect(clock(60_000)).toBe("1:00");
    expect(clock(41_200)).toBe("0:42");
    expect(clock(0)).toBe("0:00");
    expect(clock(-5)).toBe("0:00");
    expect(clock(90_000)).toBe("1:30");
  });

  test("time left counts down from the snapshot, and stands still paused", () => {
    expect(leftNow(10_000, false, 100, 2100)).toBe(8000);
    expect(leftNow(10_000, true, 100, 2100)).toBe(10_000);
    expect(leftNow(1000, false, 0, 5000)).toBe(0);
    expect(leftNow(null, false, 0, 5000)).toBeNull();
  });

  test("the next drawer goes round, then round 2 from the first, then nobody", () => {
    expect(nextDrawer(purrView({ drawer: 1 }))).toBe(2);
    expect(nextDrawer(purrView({ drawer: 3, round: 1 }))).toBe(0);
    expect(nextDrawer(purrView({ drawer: 3, round: 2 }))).toBeNull();
    expect(nextDrawer(purrView({ drawer: 2, order: [0, 1, 3], round: 1 }))).toBe(3);
    expect(nextDrawer(purrView({ phase: "over", drawer: null }))).toBeNull();
  });

  test("who draws: the drawer's device by its fields, everyone else guesses", () => {
    const v = purrView({ word: "pizza", youDraw: true });
    expect(roleOf(purrRoom(v, [1]), v)).toBe("drawer");
    const g = purrView();
    expect(roleOf(purrRoom(g, [0]), g)).toBe("guesser");
    // The drawer's second device, after the pick: a guesser.
    expect(roleOf(purrRoom(g, [1]), g)).toBe("guesser");
    expect(roleOf(purrRoom(g, []), g)).toBe("watcher");
    const c = purrView({ phase: "choosing", choices: { easy: "cat", tricky: "shadow" } });
    expect(roleOf(purrRoom(c, [1]), c)).toBe("drawer");
  });

  test("turn and reveal lines", () => {
    const room = purrRoom(purrView());
    expect(turnLine(room, purrView())).toBe("Dad is drawing");
    expect(turnLine(room, purrView({ phase: "choosing" }))).toBe("Dad is picking");
    const got = purrView({ phase: "reveal", last: { word: "pizza", guesser: 2, points: 1 } });
    expect(revealLine(room, got, null)).toBe("Ava got it");
    const missed = purrView({ phase: "reveal", last: { word: "pizza", guesser: null, points: 0 } });
    expect(revealLine(room, missed, "time")).toBe("Time's up");
    expect(revealLine(room, missed, "gaveUp")).toBe("Gave up");
  });

  test("standings, best first, out last; the title", () => {
    const v = purrView({ phase: "over", scores: [3, 5, 5, 1], out: [false, false, false, true], winners: [1, 2] });
    const room = purrRoom(v);
    expect(purrStandings(room, v).map((r) => r.seat)).toEqual([1, 2, 0, 3]);
    expect(purrOverTitle(room, v)).toBe("A tie");
    expect(purrOverTitle(room, { ...v, winners: [1] })).toBe("Dad wins");
  });

  test("the easel link and the typed code", () => {
    expect(easelLink("https://play.conleychaos.com", "BCDFG", "KQ2X7MNP")).toBe("https://play.conleychaos.com/e/BCDFG?near=KQ2X7MNP");
    expect(spacedCode("BCDFGKQ", "BCDFG")).toBe("BCDFG KQ");
  });
});

describe("events fold forward", () => {
  test("a guess scores both, a turn starts choosing, over ends it", () => {
    let v = purrView({ word: "pizza", youDraw: true });
    v = foldPurr(v, { type: "guessed", drawer: 1, guesser: 2, points: 2, word: "pizza" });
    expect(v.phase).toBe("reveal");
    expect(v.scores).toEqual([0, 2, 2, 0]);
    expect(v.word).toBeUndefined();
    expect(v.last).toEqual({ word: "pizza", guesser: 2, points: 2 });
    v = foldPurr(v, { type: "turn", drawer: 2, round: 1 });
    expect(v).toMatchObject({ phase: "choosing", drawer: 2, group: null });
    v = foldPurr(v, { type: "chosen", drawer: 2, group: "food", level: "tricky" });
    expect(v).toMatchObject({ phase: "drawing", group: "food", level: "tricky" });
    v = foldPurr(v, { type: "missed", drawer: 2, word: "shadow", reason: "time" });
    expect(v.last).toEqual({ word: "shadow", guesser: null, points: 0 });
    v = foldPurr(v, { type: "over", winners: [1, 2], scores: [0, 2, 2, 0] });
    expect(v).toMatchObject({ phase: "over", drawer: null, winners: [1, 2] });
  });
});

function setup(near?: string) {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const socket = new RoomSocket({
    code: "BCDFG",
    origin: "http://x",
    near,
    token: async () => "tok",
    factory: (url, p) => {
      const s = new FakeSocket(url, p);
      sockets.push(s);
      return s;
    },
    now: () => clock.now,
    setTimer: clock.set,
    clearTimer: clock.clear,
    backoff: [0],
  });
  const store = new RoomStore({ code: "BCDFG", token: async () => "tok", socket, setTimer: clock.set, clearTimer: clock.clear, now: () => clock.now });
  return { clock, sockets, store };
}

describe("the store at a Purrtrait table", () => {
  test("the join key rides the first socket, and never one after the first snapshot", async () => {
    const { clock, sockets, store } = setup("KQ2X7MNP");
    store.start();
    await flush();
    expect(new URL(sockets[0]!.url).searchParams.get("near")).toBe("KQ2X7MNP");
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: purrRoom(null) });
    sockets[0]!.drop();
    clock.advance(1);
    await flush();
    expect(sockets.length).toBe(2);
    expect(new URL(sockets[1]!.url).searchParams.get("near")).toBeNull();
    store.stop();
  });

  test("a refused key is notNear, a removed device is removed", async () => {
    for (const [reason, phase] of [["not_near", "notNear"], ["removed", "removed"], ["not_screen", "notFound"]] as const) {
      const { sockets, store } = setup("OLDKEY99");
      store.start();
      await flush();
      sockets[0]!.open();
      sockets[0]!.readyState = 3;
      sockets[0]!.onclose?.({ code: 4403, reason } as CloseEvent);
      expect(store.state.phase).toBe(phase);
      store.stop();
    }
  });

  test("an error removed mid-game puts the device out", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: purrRoom(purrView()) });
    sockets[0]!.receive({ t: "error", code: "removed" });
    expect(store.state.phase).toBe("removed");
  });

  test("ink, inkSync and inkResend go to the ink listener, never into state", async () => {
    const { sockets, store } = setup();
    const got: InkMessage[] = [];
    let changes = 0;
    store.subscribe({ ink: (m) => got.push(m), change: () => (changes += 1) });
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: purrRoom(purrView()) });
    const before = changes;
    sockets[0]!.receive({ t: "ink", seat: 1, turn: "1:1", ops: [["s", 0, 0, 0, 1, 1]] });
    sockets[0]!.receive({ t: "inkSync", turn: "1:1", ops: [] });
    sockets[0]!.receive({ t: "inkResend", turn: "1:1" });
    expect(got.map((m) => m.t)).toEqual(["ink", "inkSync", "inkResend"]);
    expect(changes).toBe(before);
    expect(purrOf(store.state.room)?.turn).toBe("1:1");
  });

  test("sendInk sends the drawer's ops for its seat and turn", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    expect(store.sendInk(1, "1:1", [["c"]])).toBe(true);
    expect(sockets[0]!.sent.at(-1)).toEqual({ t: "ink", seat: 1, turn: "1:1", ops: [["c"]] });
  });

  test("Purrtrait events fold into the shown room at once", async () => {
    const { sockets, store } = setup();
    store.start();
    await flush();
    sockets[0]!.open();
    sockets[0]!.receive({ t: "snapshot", protocol: 1, seq: 1, room: purrRoom(purrView()) });
    sockets[0]!.receive({ t: "event", seq: 2, event: { kind: "purrtrait", event: { type: "guessed", drawer: 1, guesser: 0, points: 1, word: "cat" } } });
    expect(purrOf(store.state.room)?.phase).toBe("reveal");
    expect(purrOf(store.state.room)?.scores).toEqual([1, 1, 0, 0]);
  });
});
