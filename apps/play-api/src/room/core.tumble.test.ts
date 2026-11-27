import { beforeEach, describe, expect, it } from "vitest";

import { newBox } from "../tumble/box";
import { restingY } from "../tumble/box";
import { toyAt } from "../tumble/queue";
import { DROP_MS } from "../tumble/round";

import { RoomCore, TUMBLE_BETWEEN_MS, TUMBLE_COUNTDOWN_MS, TUMBLE_PLAY_WITHOUT_MS, type Outbound, type RoomFeatures } from "./core";

import type { GameAction, GameOptions } from "../games";
import type { TumbleAction, TumbleState, TumbleView } from "../games/tumble";
import type { Person, ServerMessage } from "../protocol";
import type { Seed } from "../rules/rng";
import type { ClientEvent, TumbleSync } from "../tumble/wire";

/* A Toy Tumble room: its rounds, who may write a box, and where the round's messages go. */

const T0 = 1_000_000;
const ON = ["cat-tower", "tiles", "birdwatch", "tumble"] as const;
const PLAYERS = ["p_AAAAAAAAAAAAAAAAAAAAAA", "p_BBBBBBBBBBBBBBBBBBBBBB", "p_CCCCCCCCCCCCCCCCCCCCCC", "p_DDDDDDDDDDDDDDDDDDDDDD"];
const DEVICES = ["phone", "tablet", "laptop", "desk"];

const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });
const players = (seat: number) => ({ [person(seat + 1).id]: PLAYERS[seat] as string });

type Room = RoomCore<TumbleState>;

/** Toy Tumble's actions and options travel outside the wire's card-game types. */
const action = (a: TumbleAction) => a as unknown as GameAction;

let clock = T0;
let draws = 0;
/** A different number each call, so each round's seeds differ. */
const rng = () => {
  draws += 1;
  return ((draws * 0.6180339887) % 1) * 0.999 + 0.0005;
};

beforeEach(() => {
  clock = T0;
  draws = 0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const tumbleOf = (r: Room) => r.state.gameState as TumbleState;
const viewOf = (r: Room, device = "phone") => r.snapshotFor(device).room.tumble as TumbleView;
const syncsTo = (out: Outbound[], to: string) =>
  out.flatMap((o) => (o.to === to && o.message.t === "tumbleSync" ? [o.message] : [])) as TumbleSync[];
const sent = (out: Outbound[], t: ServerMessage["t"]) => out.filter((o) => o.message.t === t);

/** `humans` people, one per device, then `cats` House Cats, then the lobby's other seats closed. */
function lobby(humans = 2, cats = 0, features: Partial<RoomFeatures> = {}): Room {
  const state = RoomCore.create<TumbleState>("BCDFG", "phone", clock, undefined, undefined, "tumble");
  const r = new RoomCore<TumbleState>(state, () => clock, rng, undefined, 1, { streaks: true, games: ON, ...features });
  for (let seat = 0; seat < humans; seat++) {
    if (seat >= 2) r.handle("phone", { t: "configure", seat, kind: "open" });
    r.connect(DEVICES[seat] as string, players(seat));
    expect(errorsOf(r.handle(DEVICES[seat] as string, { t: "claim", seat, person: person(seat + 1) }))).toEqual([]);
  }
  for (let seat = humans; seat < humans + cats; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  for (let seat = humans + cats; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  return r;
}

function started(humans = 2, cats = 0, features: Partial<RoomFeatures> = {}): Room {
  const r = lobby(humans, cats, features);
  expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
  return r;
}

/** Runs the clock to the countdown's end: the round plays. */
function play(r: Room): Room {
  expect(tumbleOf(r).status).toBe("countdown");
  clock = tumbleOf(r).startsAt;
  r.tick();
  expect(tumbleOf(r).status).toBe("playing");
  return r;
}

const batch = (r: Room, device: string, ev: ClientEvent[] = [], socket = "s1") =>
  r.handle(device, { t: "tumble", r: tumbleOf(r).r, ev }, undefined, socket);

/** Everyone but `winner`'s device goes quiet until their boxes are out; the round ends on the tick. */
function win(r: Room, winner: number): Outbound[] {
  clock += DROP_MS;
  batch(r, DEVICES[winner] as string);
  return r.tumbleTick().out;
}

/** A legal set-down of seat `seat`'s first toy, where it first rests. */
function firstDrop(r: Room, seat: number): ClientEvent {
  const s = tumbleOf(r);
  const box = newBox(s.trickSeeds[seat] as Seed);
  const toy = toyAt(s.roundSeed, box.next);
  for (let x = -2; x < 12; x++) {
    const y = restingY(box, toy, 0, x);
    if (y !== null) return ["l", box.next, 0, x, y, 1000, []];
  }
  throw new Error("nowhere");
}

describe("starting a Toy Tumble table", () => {
  it("waits for every person's device to be connected", () => {
    const r = lobby(2);
    r.disconnect("tablet");
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual(["not_connected"]);
    r.connect("tablet", players(1));
    expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
    expect(r.state.status).toBe("playing");
  });

  it("a device holding a seat can't take another by code", () => {
    const r = lobby(2);
    const code = r.handle("tablet", { t: "moveSeat", seat: 1 }).flatMap((o) => (o.message.t === "moveCode" ? [o.message.code] : []))[0] as string;
    expect(errorsOf(r.handle("phone", { t: "claimMove", code }))).toEqual(["not_allowed"]);
    r.connect("desk");
    expect(errorsOf(r.handle("desk", { t: "claimMove", code }))).toEqual([]);
  });

  it("a device holds one seat at most", () => {
    const state = RoomCore.create<TumbleState>("BCDFG", "phone", clock, undefined, undefined, "tumble");
    const r = new RoomCore<TumbleState>(state, () => clock, rng, undefined, 1, { streaks: false, games: ON });
    r.connect("phone", players(0));
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(errorsOf(r.handle("phone", { t: "claim", seat: 1, person: person(2) }))).toEqual(["not_allowed"]);
    expect(r.state.seats[1]?.kind).toBe("open");
  });

  it("counts down 3 seconds with the round's seeds, then plays", () => {
    const r = started(2, 1);
    const s = tumbleOf(r);
    expect(s).toMatchObject({ status: "countdown", r: 1, startsAt: T0 + TUMBLE_COUNTDOWN_MS, wins: [0, 0, 0], cats: "easy" });
    expect(TUMBLE_COUNTDOWN_MS).toBe(3000);
    expect(s.trickSeeds).toHaveLength(3);
    expect(viewOf(r).roundSeed).toEqual(s.roundSeed);
    expect(r.snapshotFor("phone").room.gameId).toBe("tumble");
    expect(r.actor()).toBeNull();
    expect(r.nextAlarm()).toBe(s.startsAt);
    expect(r.tumblePlaying()).toBe(false);
    play(r);
    expect(r.tumblePlaying()).toBe(true);
  });

  it("keeps the lobby's House Cat level", () => {
    const r = lobby(1, 1);
    r.handle("phone", { t: "setOptions", options: { cats: "quick" } as unknown as GameOptions });
    r.handle("phone", { t: "start" });
    expect(tumbleOf(r).cats).toBe("quick");
  });
});

describe("rounds", () => {
  it("a round ends on the tick: the last box standing wins, then 5 seconds of standings", () => {
    const r = play(started(2));
    const out = win(r, 0);
    expect(tumbleOf(r)).toMatchObject({ status: "between", winner: 0, wins: [1, 0], outs: [1] });
    expect(sent(out, "snapshot").length).toBeGreaterThan(0);
    expect(r.tumblePlaying()).toBe(false);
    expect(TUMBLE_BETWEEN_MS).toBe(5000);
    expect(r.nextAlarm()).toBe(clock + TUMBLE_BETWEEN_MS);
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    expect(tumbleOf(r)).toMatchObject({ status: "countdown", r: 2, wins: [1, 0], outs: [], winner: null });
  });

  it("nothing changes on a tick that decides nothing", () => {
    const r = play(started(2));
    const seq = r.state.seq;
    clock += 100;
    expect(r.tumbleTick().changed).toBe(false);
    expect(r.state.seq).toBe(seq);
  });

  it("the game is first to 3 wins", () => {
    const r = play(started(2));
    for (let round = 1; round <= 3; round++) {
      win(r, 1);
      if (round < 3) {
        clock += TUMBLE_BETWEEN_MS;
        r.tick();
        play(r);
      }
    }
    expect(tumbleOf(r)).toMatchObject({ status: "over", winner: 1, wins: [0, 3] });
    expect(r.state.status).toBe("over");
    expect(r.tumblePlaying()).toBe(false);
  });

  it("each round a person plays counts as their turn for streaks", () => {
    const r = play(started(2));
    r.drainStreakIntents();
    win(r, 0);
    const by = r.drainStreakIntents().flatMap((i) => (i.by ? [i.by] : []));
    expect(by.sort()).toEqual([PLAYERS[0], PLAYERS[1]].sort());
  });

  it("nothing about the boxes is stored", () => {
    const r = play(started(2));
    batch(r, "phone", [firstDrop(r, 0)]);
    const stored = JSON.stringify(r.state);
    expect(stored).not.toContain("cells");
  });
});

describe("a missing device between rounds", () => {
  it("the next countdown waits, and after 20 seconds the host plays without them", () => {
    const r = play(started(3));
    win(r, 0);
    r.disconnect("laptop");
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    expect(tumbleOf(r)).toMatchObject({ status: "between", waitingSince: clock });
    expect(r.state.timers.nextRoundAt).toBeNull();
    expect(r.nextAlarm()).toBeGreaterThan(clock + 60_000);
    expect(r.tumbleTick()).toEqual({ out: [], changed: false });
    // Someone else coming and going doesn't restart the wait.
    const since = clock;
    clock += 1000;
    r.disconnect("tablet");
    r.connect("tablet", players(1));
    expect(tumbleOf(r).waitingSince).toBe(since);
    clock = since;

    const without = { t: "act" as const, seat: 1, action: action({ k: "playWithout" }) };
    expect(errorsOf(r.handle("tablet", without))).toEqual(["not_allowed"]);
    clock += TUMBLE_PLAY_WITHOUT_MS - 1;
    expect(errorsOf(r.handle("phone", { ...without, seat: 0 }))).toEqual(["too_soon"]);
    clock += 1;
    expect(errorsOf(r.handle("phone", { ...without, seat: 0 }))).toEqual([]);
    expect(tumbleOf(r)).toMatchObject({ status: "countdown", r: 2, away: [false, false, true], waitingSince: null });

    // The away seat sits this round out; back by the next countdown, it plays again.
    play(r);
    expect(syncsTo(batch(r, "phone"), "phone")[0]?.boxes.map((b) => b.s)).toEqual([0, 1]);
    r.connect("laptop", players(2));
    expect(tumbleOf(r).status).toBe("playing");
    win(r, 0);
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    expect(tumbleOf(r)).toMatchObject({ status: "countdown", r: 3, away: [false, false, false] });
  });

  it("a device back while waiting starts the countdown", () => {
    const r = play(started(2));
    win(r, 0);
    r.disconnect("tablet");
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    expect(tumbleOf(r).waitingSince).toBe(clock);
    clock += 1000;
    r.connect("tablet", players(1));
    expect(tumbleOf(r)).toMatchObject({ status: "countdown", r: 2, waitingSince: null, startsAt: clock + TUMBLE_COUNTDOWN_MS });
  });

  it("playing without the only other seat leaves one: the countdown keeps waiting", () => {
    const r = play(started(2));
    win(r, 0);
    r.disconnect("tablet");
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    clock += TUMBLE_PLAY_WITHOUT_MS;
    const out = r.handle("phone", { t: "act", seat: 0, action: action({ k: "playWithout" }) });
    expect(errorsOf(out)).toEqual([]);
    expect(sent(out, "snapshot").length).toBeGreaterThan(0);
    expect(tumbleOf(r)).toMatchObject({ status: "between", away: [false, true] });
    r.connect("tablet", players(1));
    expect(tumbleOf(r)).toMatchObject({ status: "countdown", away: [false, false] });
  });

  it("with no person's device connected, nothing runs and no alarm is set", () => {
    const r = play(started(2));
    win(r, 0);
    r.disconnect("phone");
    r.disconnect("tablet");
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    expect(tumbleOf(r)).toMatchObject({ status: "between", waitingSince: null });
    expect(r.tumblePlaying()).toBe(false);
    expect(r.state.timers.nextRoundAt).toBeNull();
    expect(r.nextAlarm()).toBeGreaterThan(clock + 60_000);
  });
});

describe("leaving", () => {
  const leave = (r: Room, seat: number) => r.handle(DEVICES[seat] as string, { t: "act", seat, action: action({ k: "leave" }) });

  it("takes the seat out for the game, its wins kept, with no House Cat for it", () => {
    const r = play(started(3));
    win(r, 2);
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    play(r);
    expect(errorsOf(leave(r, 2))).toEqual([]);
    expect(tumbleOf(r)).toMatchObject({ left: [false, false, true], wins: [0, 0, 1], status: "playing" });
    expect(r.state.seats[2]?.kind).toBe("human");
    expect(errorsOf(batch(r, "laptop"))).toEqual(["not_allowed"]);
    // The round goes on without it: the last of the others standing wins.
    win(r, 0);
    expect(tumbleOf(r)).toMatchObject({ status: "between", winner: 0, wins: [1, 0, 1] });
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    play(r);
    expect(syncsTo(batch(r, "phone"), "phone")[0]?.boxes.map((b) => b.s)).toEqual([0, 1]);
  });

  it("a box left mid-round doesn't hold the round up", () => {
    const r = play(started(3));
    clock += 2000;
    batch(r, "laptop");
    leave(r, 2);
    // The box that left is out of the round at once.
    r.tumbleTick();
    expect(tumbleOf(r)).toMatchObject({ status: "playing", outs: [2] });
    // The tablet is out at 15 seconds.
    clock = tumbleOf(r).startsAt + DROP_MS;
    batch(r, "phone");
    r.tumbleTick();
    expect(tumbleOf(r)).toMatchObject({ status: "between", winner: 0, outs: [2, 1] });
  });

  it("a box that left never wins the round", () => {
    const r = play(started(3));
    clock += 2000;
    batch(r, "laptop");
    leave(r, 2);
    clock = tumbleOf(r).startsAt + DROP_MS;
    r.tumbleTick();
    expect(tumbleOf(r)).toMatchObject({ status: "between", winner: null, wins: [0, 0, 0] });
  });

  it("with only House Cats left in a round, the one that cleared the most rows wins it", () => {
    const r = play(started(2, 2));
    clock += 2000;
    batch(r, "phone");
    leave(r, 0);
    clock = tumbleOf(r).startsAt + DROP_MS;
    r.tumbleTick();
    expect(tumbleOf(r)).toMatchObject({ status: "between", winner: 2, outs: [0, 1] });
  });

  it("with one seat left the game is over, and the seat left with the most wins wins", () => {
    const r = play(started(2));
    expect(errorsOf(leave(r, 1))).toEqual([]);
    expect(tumbleOf(r)).toMatchObject({ status: "over", winner: 0 });
    expect(r.state.status).toBe("over");
    expect(r.tumblePlaying()).toBe(false);
  });

  it("with no person left the game is over", () => {
    const r = play(started(2, 2));
    leave(r, 0);
    expect(tumbleOf(r).status).toBe("playing");
    leave(r, 1);
    expect(tumbleOf(r)).toMatchObject({ status: "over", left: [true, true, false, false] });
    expect(r.state.status).toBe("over");
  });
});

describe("the live stream", () => {
  it("a set-down goes to every other device and screen, never back to its own", () => {
    const r = play(started(2, 0, { tv: true }));
    r.addScreen("tv");
    r.connect("tv");
    const out = batch(r, "phone", [firstDrop(r, 0)]);
    const relays = out.filter((o) => o.message.t === "tumble");
    expect(relays.map((o) => o.to).sort()).toEqual(["tablet", "tv"]);
    expect(errorsOf(out)).toEqual([]);
  });

  it("a screen may not write, but its empty batch gets every box, to it alone", () => {
    const r = play(started(2, 0, { tv: true }));
    r.addScreen("tv");
    r.connect("tv");
    expect(errorsOf(batch(r, "tv", [firstDrop(r, 0)]))).toEqual(["not_allowed"]);
    const asked = batch(r, "tv");
    expect(errorsOf(asked)).toEqual([]);
    expect(asked.map((o) => o.to)).toEqual(["tv"]);
    expect(syncsTo(asked, "tv")[0]?.boxes.map((b) => b.s)).toEqual([0, 1]);
  });

  it("a screen that connects mid-round gets every box", () => {
    const r = play(started(2, 1, { tv: true }));
    r.addScreen("tv");
    const out = r.connect("tv");
    expect(syncsTo(out, "tv")[0]?.boxes.map((b) => b.s)).toEqual([0, 1, 2]);
  });

  it("a seat's device back mid-round gets every box", () => {
    const r = play(started(2));
    r.disconnect("tablet");
    clock += 4000;
    const out = r.connect("tablet", players(1));
    expect(syncsTo(out, "tablet").some((s) => s.boxes.length === 2)).toBe(true);
  });

  it("a quiet device is shown reconnecting; any message from it, or a ping it answered, brings it back", () => {
    const r = play(started(2));
    clock += 3000;
    const lag = r.tumbleTick().out.filter((o) => o.message.t === "tumbleSeat");
    expect(lag.map((o) => [o.to, o.message])).toEqual([
      ["all", { t: "tumbleSeat", r: 1, s: 0, st: "lag" }],
      ["all", { t: "tumbleSeat", r: 1, s: 1, st: "lag" }],
    ]);
    // Never written to this round: its sync goes to the device holding the seat.
    const back = r.handle("tablet", { t: "presence", state: "active" });
    expect(back.find((o) => o.message.t === "tumbleSeat")).toEqual({ to: "all", message: { t: "tumbleSeat", r: 1, s: 1, st: "ok" } });
    expect(syncsTo(back, "tablet")).toHaveLength(1);
    // A ping from before the round, or one already heard, changes nothing.
    expect(r.tumblePing("phone", "s1", T0)).toEqual([]);
    expect(r.tumblePing("phone", "s1", clock).find((o) => o.message.t === "tumbleSeat")?.message).toMatchObject({ s: 0, st: "ok" });
    expect(r.tumblePing("phone", "s1", clock)).toEqual([]);
    expect(r.tumblePing("tv", "s1", clock)).toEqual([]);
  });

  it("only the first socket of a device to send this round writes its box", () => {
    const r = play(started(2));
    expect(errorsOf(batch(r, "phone", [], "a"))).toEqual([]);
    const second = batch(r, "phone", [firstDrop(r, 0)], "b");
    expect(second).toEqual([{ to: "phone", socket: "b", message: { t: "error", code: "not_allowed" } }]);
    expect(errorsOf(batch(r, "phone", [firstDrop(r, 0)], "a"))).toEqual([]);
  });

  it("a writer gone quiet for 3 seconds, or closed, hands over", () => {
    const r = play(started(2));
    batch(r, "phone", [], "a");
    r.tumbleClosed("phone", "z");
    expect(errorsOf(batch(r, "phone", [], "b"))).toEqual(["not_allowed"]);
    r.tumbleClosed("phone", "a");
    expect(errorsOf(batch(r, "phone", [], "b"))).toEqual([]);
    clock += 3000;
    expect(errorsOf(batch(r, "phone", [], "c"))).toEqual([]);
    expect(errorsOf(batch(r, "phone", [], "b"))).toEqual(["not_allowed"]);
  });

  it("over 30 batches a second, a device gets a sync of its box", () => {
    const r = play(started(2));
    for (let i = 0; i < 30; i++) expect(syncsTo(batch(r, "phone"), "phone").at(-1)?.boxes).toHaveLength(2);
    const over = batch(r, "phone", [firstDrop(r, 0)]);
    expect(sent(over, "tumble")).toEqual([]);
    expect(syncsTo(over, "phone").map((s) => s.boxes.map((b) => b.s))).toEqual([[0]]);
    clock += 1000;
    expect(sent(batch(r, "phone", [firstDrop(r, 0)]), "tumble")).toHaveLength(1);
  });

  it("a batch with no round, or at another game's table, goes nowhere", () => {
    const r = started(2);
    expect(r.handle("phone", { t: "tumble", r: 7, ev: [] }, undefined, "s")).toEqual([]);
    const other = new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng, undefined, 1, { streaks: false });
    other.connect("phone");
    expect(errorsOf(other.handle("phone", { t: "tumble", r: 1, ev: [] }))).toEqual(["bad_message"]);
  });
});

describe("a restart mid-round", () => {
  const reload = (r: Room): Room =>
    new RoomCore<TumbleState>(JSON.parse(JSON.stringify(r.state)) as typeof r.state, () => clock, rng, undefined, 1, { streaks: true, games: ON });

  it("replays the round from a new countdown, with new seeds and the wins kept", () => {
    const r = play(started(2));
    win(r, 1);
    clock += TUMBLE_BETWEEN_MS;
    r.tick();
    play(r);
    const before = tumbleOf(r);
    clock += 30_000;
    const back = reload(r);
    expect(back.tumblePlaying()).toBe(false);
    back.restartRound();
    const after = tumbleOf(back);
    expect(after).toMatchObject({ status: "countdown", r: 2, wins: [0, 1], startsAt: clock + TUMBLE_COUNTDOWN_MS, outs: [] });
    expect(after.roundSeed).not.toEqual(before.roundSeed);
    expect(back.nextAlarm()).toBe(after.startsAt);
    play(back);
    expect(back.tumblePlaying()).toBe(true);
  });

  it("a countdown lost to a restart counts down again", () => {
    const r = started(2);
    const back = reload(r);
    clock += 1000;
    back.restartRound();
    expect(tumbleOf(back)).toMatchObject({ status: "countdown", r: 1, startsAt: clock + TUMBLE_COUNTDOWN_MS });
  });

  it("a countdown's alarm with its round lost counts down again", () => {
    const back = reload(started(2));
    clock = tumbleOf(back).startsAt;
    back.tick();
    expect(tumbleOf(back)).toMatchObject({ status: "countdown", r: 1, startsAt: clock + TUMBLE_COUNTDOWN_MS });
  });

  it("a round still in memory, a lobby and other games have nothing to replay", () => {
    const r = play(started(2));
    expect(r.restartRound()).toEqual([]);
    expect(lobby(2).restartRound()).toEqual([]);
    expect(new RoomCore(RoomCore.create("BCDFG", "phone", clock), () => clock, rng).restartRound()).toEqual([]);
  });

  it("standings between rounds are left as they are", () => {
    const r = play(started(2));
    win(r, 0);
    const back = reload(r);
    const before = JSON.stringify(back.state);
    expect(back.restartRound()).toEqual([]);
    expect(JSON.stringify(back.state)).toBe(before);
  });
});
