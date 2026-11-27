import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { purrtrait } from "../src/games/purrtrait";
import { parseClientMessage } from "../src/protocol";
import { WORDS } from "../src/purrtrait/words";
import { RoomCore, SCREEN_GRACE_MS, STALL_END_MS, type Outbound } from "../src/room/core";
import { createRng } from "../src/rules/rng";

import type { ClientMessage, ErrorCode, Person, ServerMessage } from "../src/protocol";
import type { PurrEvent, PurrState } from "../src/purrtrait/engine";
import type { InkOp } from "../src/purrtrait/ink";
import type { PurrView } from "../src/purrtrait/view";

/**
 * Purrtrait's wire samples, for the Swift client (PounceKit) and the web player the way
 * Birdwatch's are: they decode every server sample and encode every client sample, by `name`.
 * Made from real rooms: a TV makes the table, phones sit, and every sample is what the room sent
 * to that device. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/purrtrait-protocol-fixtures.test.ts`.
 */
type Sample<M> = { name: string; message: M };
type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Room = RoomCore<PurrState>;

const write = process.env.UPDATE_FIXTURES === "1";
const ON = ["cat-tower", "tiles", "birdwatch", "purrtrait"] as const;
const T0 = Date.UTC(2026, 10, 26, 19);

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const NAMES = ["Alice", "Bob", "Cleo", "Dev", "Eli", "Fay"];
const people: Person[] = NAMES.map((name, i) => ({ id: `${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}${i + 1}-1111-4111-8111-111111111111`, name, cat: i }));
const playerOf = (seat: number) => `p_player${seat}`;
/** Each seat's phone. "devA2" is Alice's iPad: it speaks for her too, so it controls seat 0. */
const device = (seat: number) => `dev${"ABCDEF"[seat]}`;
const speaksFor = (seat: number) => ({ [(people[seat] as Person).id]: playerOf(seat) });
const game = (r: Room) => r.state.gameState as PurrState;
const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));

/** A clock each room shares with its test. */
type Clock = { now: number };

/** A table the TV ("tv") made, `seats` people on their own phones; Alice's iPad "devA2" too when `ipad`. */
function table(clock: Clock, seats: number, options: { ipad?: boolean; kitten?: boolean; timer?: 45 | 60 | 90 } = {}): Room {
  const state = RoomCore.create<PurrState>("BCDFG", "", clock.now, "Game Night", undefined, "purrtrait", "tv");
  const r = new RoomCore<PurrState>(state, () => clock.now, createRng([1, 2, 3, 4]), undefined, 1, { streaks: false, tv: true, games: ON });
  r.connect("tv");
  if (options.kitten) r.setKitten(device(0), true);
  for (let seat = 0; seat < seats; seat++) {
    if (r.state.seats[seat]?.kind === "closed") r.handle(device(0), { t: "configure", seat, kind: "open" });
    r.connect(device(seat), speaksFor(seat));
    const out = r.handle(device(seat), { t: "claim", seat, person: people[seat] as Person });
    if (errorsOf(out).length > 0) throw new Error(`claim ${seat}: ${errorsOf(out).join()}`);
  }
  if (options.ipad) r.connect("devA2", speaksFor(0));
  for (let seat = seats; seat < r.state.seats.length; seat++) {
    if (r.state.seats[seat]?.kind !== "closed") r.handle(device(0), { t: "configure", seat, kind: "closed" });
  }
  if (options.timer) r.handle(device(0), { t: "setOptions", options: { timer: options.timer } });
  return r;
}

/** The room's answer must hold no error: a sample built on a refused message would be a lie. */
function ok(out: Outbound[], what: string): Outbound[] {
  const refused = errorsOf(out);
  if (refused.length > 0) throw new Error(`${what} refused: ${refused.join()}`);
  return out;
}

function start(r: Room): Outbound[] {
  return ok(r.handle(device(0), { t: "start" }), "start");
}

/** What the drawer's phone sends; `from` is the device (Alice's iPad, say). */
function act(r: Room, action: unknown, from?: string): Outbound[] {
  const seat = game(r).drawer as number;
  return ok(r.handle(from ?? device(seat), { t: "act", seat, action } as ClientMessage), JSON.stringify(action));
}

function ink(r: Room, ops: InkOp[], from?: string, last?: true): Outbound[] {
  const seat = game(r).drawer as number;
  const turn = (r.snapshotFor("tv").room.purrtrait as PurrView).turn;
  return ok(r.handle(from ?? device(seat), { t: "ink", seat, turn, ops, ...(last ? { last } : {}) } as ClientMessage), "ink");
}

/** The reveal's pause runs out: the next turn begins (the room's own `nextTurn`). */
function nextTurn(r: Room, clock: Clock): Outbound[] {
  clock.now += 6_000;
  return r.tick();
}

const to = (out: Outbound[], d: string, t: ServerMessage["t"]) => out.find((o) => o.to === d && o.message.t === t)?.message as ServerMessage;
const viewIn = (snap: Snapshot) => snap.room.purrtrait as PurrView;

/** A cat: a head (with a point added), two ears, and a stray stroke undone. */
const STROKES: InkOp[][] = [
  [["s", 0, 0, 1, 384, 300, 40, 0, 30, 30, 0, 40, -30, 30, -40, 0, -30, -30, 0, -40, 30, -30]],
  [["p", 0, 2, 2]],
  [["s", 1, 0, 1, 340, 280, -20, -40, -10, 40]],
  [["s", 2, 0, 1, 430, 280, 20, -40, 10, 40]],
  [["s", 3, 3, 2, 100, 900, 50, 0]],
  [["u", 3]],
];

function snapshots() {
  const clock: Clock = { now: T0 };
  const r = table(clock, 4, { ipad: true, timer: 90 });
  const lobbyScreen = r.snapshotFor("tv");
  const lobbyHost = r.snapshotFor(device(0));
  const lobbyGuest = r.snapshotFor(device(1));
  const events: Outbound[] = [...start(r)];

  clock.now += 2_000;
  const choosingDrawer = r.snapshotFor(device(0));
  const choosingOtherDevice = r.snapshotFor("devA2");
  const choosingGuesser = r.snapshotFor(device(1));
  const choosingScreen = r.snapshotFor("tv");
  events.push(...act(r, { type: "choose", level: "tricky" }));

  clock.now += 15_000;
  const inks: Outbound[] = [];
  for (const ops of STROKES) inks.push(...ink(r, ops));
  const drawingDrawer = r.snapshotFor(device(0));
  const drawingOtherDevice = r.snapshotFor("devA2");
  const drawingGuesser = r.snapshotFor(device(1));
  const drawingScreen = r.snapshotFor("tv");

  // The TV reloads mid-turn: its snapshot, then the drawing so far.
  r.disconnect("tv");
  const reconnect = r.connect("tv");
  const inkSync = to(reconnect, "tv", "inkSync");
  // A room that wakes from storage has lost the drawing: it asks the drawer's phone for it.
  const woken = new RoomCore<PurrState>(JSON.parse(JSON.stringify(r.state)) as typeof r.state, () => clock.now, createRng([5, 6, 7, 8]), undefined, 1, { streaks: false, tv: true, games: ON });
  const inkResend = to(woken.rebuilt(), device(0), "inkResend");

  // The TV goes away: after the grace the clock stops.
  r.disconnect("tv");
  clock.now += SCREEN_GRACE_MS;
  r.tick();
  const pausedDrawer = r.snapshotFor(device(0));
  const pausedGuesser = r.snapshotFor(device(1));
  clock.now += 5 * 60_000;
  r.connect("tv");

  clock.now += 10_000;
  events.push(...act(r, { type: "gotIt", seat: 2 }));
  const revealScreen = r.snapshotFor("tv");
  const revealGuesser = r.snapshotFor(device(2));
  events.push(...nextTurn(r, clock));

  // Bob runs out of time.
  events.push(...act(r, { type: "choose", level: "easy" }));
  clock.now += 90_000;
  events.push(...r.tick());
  const revealTimeUp = r.snapshotFor("tv");
  events.push(...nextTurn(r, clock));

  // Cleo gives up.
  events.push(...act(r, { type: "choose", level: "easy" }));
  events.push(...act(r, { type: "giveUp" }));
  events.push(...nextTurn(r, clock));

  // Dev is removed by the host mid-turn: his turn is missed, and the game goes on without him.
  events.push(...act(r, { type: "choose", level: "easy" }));
  events.push(...ok(r.handle(device(0), { t: "remove", seat: 3 }), "remove"));
  const afterRemove = r.snapshotFor("tv");
  events.push(...nextTurn(r, clock));

  // Round 2 to the end: each drawer picks, the next seat in gets it.
  while (game(r).phase !== "over") {
    if (game(r).phase === "reveal") {
      events.push(...nextTurn(r, clock));
      continue;
    }
    const s = game(r);
    const drawer = s.drawer as number;
    events.push(...act(r, { type: "choose", level: drawer === 0 ? "tricky" : "easy" }));
    const guesser = s.out.findIndex((out, seat) => !out && seat !== drawer);
    events.push(...act(r, { type: "gotIt", seat: guesser }));
  }
  const overScreen = r.snapshotFor("tv");
  const overPlayer = r.snapshotFor(device(1));

  // Everyone but one leaves: the game ends at once.
  const leftClock: Clock = { now: T0 };
  const two = table(leftClock, 2);
  start(two);
  ok(two.handle(device(1), { t: "act", seat: 1, action: { type: "forfeit" } }), "forfeit");
  const overLeft = two.snapshotFor(device(0));

  // The TV is gone for 30 minutes: the game ends with the scores as they are.
  const stallClock: Clock = { now: T0 };
  const stalled = table(stallClock, 3);
  start(stalled);
  act(stalled, { type: "choose", level: "easy" });
  act(stalled, { type: "gotIt", seat: 1 });
  stalled.disconnect("tv");
  stallClock.now += SCREEN_GRACE_MS;
  stalled.tick();
  stallClock.now += STALL_END_MS;
  stalled.tick();
  const overStalled = stalled.snapshotFor(device(1));

  // A kitten's phone drawing: two Easy words to pick from.
  const kittenClock: Clock = { now: T0 };
  const kitten = table(kittenClock, 3, { kitten: true });
  start(kitten);
  const choosingKitten = kitten.snapshotFor(device(0));

  return {
    lobbyScreen, lobbyHost, lobbyGuest,
    choosingDrawer, choosingOtherDevice, choosingGuesser, choosingScreen, choosingKitten,
    drawingDrawer, drawingOtherDevice, drawingGuesser, drawingScreen,
    pausedDrawer, pausedGuesser,
    revealScreen, revealGuesser, revealTimeUp, afterRemove,
    overScreen, overPlayer, overLeft, overStalled,
    events, inks, inkSync, inkResend,
  };
}

type PurrEventMessage = Extract<ServerMessage, { t: "event" }> & { event: { kind: "purrtrait"; event: PurrEvent } };

/** The first event of each kind (a `missed` for each reason) the screen heard. */
function eventSamples(out: Outbound[]): Sample<ServerMessage>[] {
  const seen = new Map<string, ServerMessage>();
  for (const o of out) {
    if (o.to !== "tv" || o.message.t !== "event" || o.message.event.kind !== "purrtrait") continue;
    const e = (o.message as PurrEventMessage).event.event;
    const name = e.type === "missed" ? `event-missed-${e.reason}` : `event-${e.type}`;
    if (!seen.has(name)) seen.set(name, o.message);
  }
  const order = ["event-turn", "event-chosen", "event-guessed", "event-missed-time", "event-missed-gaveUp", "event-missed-left", "event-over"];
  return order.map((name) => {
    const message = seen.get(name);
    if (!message) throw new Error(`no ${name} in the game`);
    return { name, message };
  });
}

/** The error codes a Purrtrait client meets: the game's own, and the room's new ones. */
const ERRORS: ErrorCode[] = [
  "easel_full",
  "not_near",
  "removed",
  "no_screen",
  "not_allowed",
  "not_enough_players",
  "bad_seat",
  "bad_message",
  "wrong_phase",
  "not_your_turn",
  "game_over",
  "game_off",
];

function serverSamples(): Sample<ServerMessage>[] {
  const s = snapshots();
  const inkToScreen = s.inks.find((o) => o.to === "tv")?.message as ServerMessage;
  return [
    { name: "snapshot-lobby-screen", message: s.lobbyScreen },
    { name: "snapshot-lobby-host", message: s.lobbyHost },
    { name: "snapshot-lobby-guest", message: s.lobbyGuest },
    { name: "snapshot-choosing-drawer", message: s.choosingDrawer },
    { name: "snapshot-choosing-drawer-other-device", message: s.choosingOtherDevice },
    { name: "snapshot-choosing-guesser", message: s.choosingGuesser },
    { name: "snapshot-choosing-screen", message: s.choosingScreen },
    { name: "snapshot-choosing-kitten-drawer", message: s.choosingKitten },
    { name: "snapshot-drawing-drawer", message: s.drawingDrawer },
    { name: "snapshot-drawing-drawer-other-device", message: s.drawingOtherDevice },
    { name: "snapshot-drawing-guesser", message: s.drawingGuesser },
    { name: "snapshot-drawing-screen", message: s.drawingScreen },
    { name: "snapshot-paused-drawer", message: s.pausedDrawer },
    { name: "snapshot-paused-guesser", message: s.pausedGuesser },
    { name: "snapshot-reveal-screen", message: s.revealScreen },
    { name: "snapshot-reveal-guesser", message: s.revealGuesser },
    { name: "snapshot-reveal-time-up-screen", message: s.revealTimeUp },
    { name: "snapshot-reveal-seat-removed-screen", message: s.afterRemove },
    { name: "snapshot-over-screen", message: s.overScreen },
    { name: "snapshot-over-player", message: s.overPlayer },
    { name: "snapshot-over-left", message: s.overLeft },
    { name: "snapshot-over-stalled", message: s.overStalled },
    ...eventSamples(s.events),
    { name: "ink", message: inkToScreen },
    { name: "inkSync", message: s.inkSync },
    { name: "inkResend", message: s.inkResend },
    ...ERRORS.map((code): Sample<ServerMessage> => ({ name: `error-${code}`, message: { t: "error", code } })),
  ];
}

const TURN = "1:0";
const clientSamples: Sample<ClientMessage>[] = [
  { name: "setOptions", message: { t: "setOptions", options: { timer: 90 } } },
  { name: "act-choose-easy", message: { t: "act", seat: 0, action: { type: "choose", level: "easy" } } },
  { name: "act-choose-tricky", message: { t: "act", seat: 0, action: { type: "choose", level: "tricky" } } },
  { name: "act-gotIt", message: { t: "act", seat: 0, action: { type: "gotIt", seat: 2 } } },
  { name: "act-giveUp", message: { t: "act", seat: 0, action: { type: "giveUp" } } },
  { name: "act-forfeit", message: { t: "act", seat: 1, action: { type: "forfeit" } } },
  { name: "ink", message: { t: "ink", seat: 0, turn: TURN, ops: [["s", 4, 0, 1, 384, 210, 3, -1, 4, 0], ["p", 4, 2, 2, 1, 3]] } },
  { name: "ink-undo", message: { t: "ink", seat: 0, turn: TURN, ops: [["u", 4]] } },
  { name: "ink-clear", message: { t: "ink", seat: 0, turn: TURN, ops: [["c"]] } },
  // The reply to inkResend: the whole easel, from a clear, the last message marked.
  { name: "ink-resend", message: { t: "ink", seat: 0, turn: TURN, ops: [["c"], ["s", 7, 0, 1, 384, 300, 40, 0, 30, 30]] } },
  { name: "ink-resend-last", message: { t: "ink", seat: 0, turn: TURN, ops: [["s", 8, 0, 1, 340, 280, -20, -40]], last: true } },
  { name: "ink-resend-single", message: { t: "ink", seat: 0, turn: TURN, ops: [["c"], ["s", 7, 0, 1, 384, 300, 40, 0]], last: true } },
  { name: "remove", message: { t: "remove", seat: 3 } },
];

test("Purrtrait's server samples match the committed file, and are real", () => {
  const samples = serverSamples();
  check("purrtrait-server-messages.json", samples);
  const snaps = samples.flatMap((s) => (s.message.t === "snapshot" ? [{ name: s.name, snap: s.message }] : []));
  for (const { name, snap } of snaps) {
    const { room } = snap;
    expect(room.gameId, name).toBe("purrtrait");
    expect(room.game, name).toBeNull();
    expect(room.options, name).toBeDefined();
    // Only the screen's snapshot carries the near key.
    expect(room.near !== undefined, name).toBe(name.endsWith("-screen") && room.status !== "over");
    const v = room.purrtrait;
    if (!v) continue;
    expect(JSON.stringify(v), name).not.toMatch(/"(seed|rngCalls|used|offer|queue|ops)":/);
    // The word and the choices reach the drawer's phone alone (and, before the pick, the drawer's other device).
    if (v.word !== undefined) expect(name, name).toMatch(/-drawer$/);
    if (v.choices !== undefined) expect(name, name).toMatch(/choosing-(kitten-)?drawer/);
  }
  const by = (name: string) => viewIn(snaps.find((s) => s.name === name)?.snap as Snapshot);
  const snap = (name: string) => snaps.find((s) => s.name === name)?.snap as Snapshot;
  expect(snap("snapshot-lobby-screen").room.near).toMatchObject({ key: expect.stringMatching(/^[A-Z0-9]{8}$/), code: expect.stringMatching(/^BCDFG[A-Z0-9]{3}$/) });
  expect(snap("snapshot-lobby-host").room.youAreHost).toBe(true);
  expect(snap("snapshot-lobby-guest").room.youAreHost).toBe(false);
  expect(by("snapshot-choosing-drawer").choices).toBeDefined();
  expect(by("snapshot-choosing-drawer-other-device").choices).toEqual(by("snapshot-choosing-drawer").choices);
  expect(by("snapshot-choosing-guesser").choices).toBeUndefined();
  expect(by("snapshot-choosing-screen").choices).toBeUndefined();
  const kitten = by("snapshot-choosing-kitten-drawer").choices as { easy: string; tricky: string };
  expect(kitten.easy).not.toBe(kitten.tricky);
  expect([kitten.easy, kitten.tricky].map((w) => WORDS.find((x) => x.word === w)?.level)).toEqual(["easy", "easy"]);
  expect(by("snapshot-drawing-drawer")).toMatchObject({ phase: "drawing", youDraw: true, level: "tricky" });
  expect(by("snapshot-drawing-drawer").word).toBeDefined();
  expect(by("snapshot-drawing-drawer-other-device")).toEqual(by("snapshot-drawing-guesser"));
  expect(by("snapshot-drawing-screen").word).toBeUndefined();
  expect(by("snapshot-paused-drawer")).toMatchObject({ paused: true, remainingMs: 90_000 - 15_000 - SCREEN_GRACE_MS });
  expect(by("snapshot-paused-guesser")).toMatchObject({ paused: true });
  expect(by("snapshot-reveal-screen")).toMatchObject({ phase: "reveal", last: { guesser: 2, points: 2 } });
  expect(by("snapshot-reveal-time-up-screen")).toMatchObject({ phase: "reveal", last: { guesser: null, points: 0 } });
  expect(by("snapshot-reveal-seat-removed-screen")).toMatchObject({ phase: "reveal", drawer: 3, order: [0, 1, 2], last: { guesser: null } });
  expect(by("snapshot-reveal-seat-removed-screen").out[3]).toBe(true);
  expect(by("snapshot-over-screen")).toMatchObject({ phase: "over", drawer: null });
  expect(by("snapshot-over-left")).toMatchObject({ phase: "over", winners: [0] });
  expect(by("snapshot-over-stalled")).toMatchObject({ phase: "over", round: 1 });
  // No event names the word before its reveal.
  for (const { name, message } of samples) {
    if (message.t !== "event" || message.event.kind !== "purrtrait") continue;
    const e = message.event.event;
    expect("word" in e, name).toBe(e.type === "guessed" || e.type === "missed");
  }
  const inkSync = samples.find((s) => s.name === "inkSync")?.message as Extract<ServerMessage, { t: "inkSync" }>;
  // The undone stroke is gone, and stroke 0 has its added point folded in.
  expect(inkSync.ops.map((op) => op.slice(0, 2))).toEqual([["s", 0], ["s", 1], ["s", 2]]);
});

test("the room really answers each new error code", () => {
  const clock: Clock = { now: T0 };
  // no_screen: a table whose TV has gone can't start.
  const r = table(clock, 2);
  r.disconnect("tv");
  clock.now += SCREEN_GRACE_MS;
  r.tick();
  expect(errorsOf(r.handle(device(0), { t: "start" }))).toEqual(["no_screen"]);
  r.connect("tv");
  // not_allowed: only the host removes a seat.
  expect(errorsOf(r.handle(device(1), { t: "remove", seat: 0 }))).toEqual(["not_allowed"]);
  start(r);
  act(r, { type: "choose", level: "easy" });
  // easel_full: past 500 strokes since the last clear.
  let refused: ErrorCode[] = [];
  for (let id = 0; refused.length === 0; id++) {
    if (id % 25 === 0) clock.now += 1_000;
    const seat = game(r).drawer as number;
    refused = errorsOf(r.handle(device(seat), { t: "ink", seat, turn: "1:0", ops: [["s", id, 0, 0, 1, 1]] }));
  }
  expect(refused).toEqual(["easel_full"]);
  // removed: a removed person is refused a seat from any phone.
  const lobby = table(clock, 3);
  ok(lobby.handle(device(0), { t: "remove", seat: 2 }), "remove");
  lobby.connect("devZ", speaksFor(2));
  expect(errorsOf(lobby.handle("devZ", { t: "claim", seat: 2, person: people[2] as Person }))).toEqual(["removed"]);
  // not_near is the socket's refusal (403, close 4403), from `knows`.
  expect(lobby.knows("devY", null, false)).toBe("not_near");
});

test("Purrtrait's client samples match the committed file, and the room's parser takes each as it is", () => {
  check("purrtrait-client-messages.json", clientSamples);
  for (const { name, message } of clientSamples) {
    const parsed = parseClientMessage(JSON.stringify(message), purrtrait.parseAction, purrtrait.parseAim, purrtrait.parseOptions);
    expect(parsed, name).toEqual(message);
  }
});
