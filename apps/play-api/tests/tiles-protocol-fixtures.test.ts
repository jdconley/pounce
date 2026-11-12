import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { tiles } from "../src/games/tiles";
import { parseClientMessage } from "../src/protocol";
import { RoomCore } from "../src/room/core";
import { createRng } from "../src/rules/rng";
import { readSet } from "../src/tiles/sets";

import { expectSound, feather, fish, mouse, piecesIn } from "./tiles-helpers";

import type { ClientMessage, Person, ServerMessage } from "../src/protocol";
import type { TilesAction, TilesState } from "../src/tiles/engine";

/**
 * The tile game's wire samples, shared with the Swift client (PounceKit) the way
 * `client-messages.json` and `server-messages.json` are for Cat Tower: it decodes every server
 * sample and encodes every client sample, looking each up by `name`. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/tiles-protocol-fixtures.test.ts`.
 */
type Sample<M> = { name: string; message: M };
type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Room = RoomCore<TilesState>;

const write = process.env.UPDATE_FIXTURES === "1";

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const alice: Person = { id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 0 };
const bob: Person = { id: "22222222-2222-4222-8222-222222222222", name: "Bob", cat: 3 };

const game = (room: Room) => room.state.gameState as TilesState;

/** A tile game room: alice (devA), bob (devB), and a House Cat when `bot`. Not yet started. */
function lobby(bot = false): Room {
  const state = RoomCore.create<TilesState>("BCDFG", "devA", 1_000, undefined, undefined, "tiles");
  const room = new RoomCore<TilesState>(state, () => 1_000, createRng([1, 2, 3, 4]));
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  if (bot) room.handle("devA", { t: "configure", seat: 2, kind: "bot" });
  return room;
}

function started(bot = false): Room {
  const room = lobby(bot);
  room.handle("devA", { t: "start" });
  return room;
}

/**
 * Puts `pieces` on `seat`'s rack, swapping each with a piece the rack doesn't need, wherever it
 * was (another rack or the pool), so every piece is still somewhere exactly once. `keep`: how
 * many other pieces the rack keeps (the rest go to the pool).
 */
function give(room: Room, seat: number, pieces: number[], keep = 14 - pieces.length): void {
  const g = game(room);
  const rack = g.racks[seat] as number[];
  for (const id of pieces) {
    if (rack.includes(id)) continue;
    const spare = rack.findIndex((other) => !pieces.includes(other));
    const home = [g.pool, ...g.racks].find((pile) => pile.includes(id)) as number[];
    home[home.indexOf(id)] = rack[spare] as number;
    rack[spare] = id;
  }
  const others = rack.filter((id) => !pieces.includes(id));
  g.pool.unshift(...others.slice(keep));
  g.racks[seat] = [...pieces, ...others.slice(0, keep)];
  expectSound(g);
}

/** A seat's action through the room, as its device sends it. A sample built on a refused move would be a lie, so it throws. */
function act(room: Room, seat: number, action: TilesAction, id?: string): void {
  const out = room.handle(seat === 0 ? "devA" : "devB", { t: "act", seat, action, ...(id ? { id } : {}) });
  const refused = out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
  if (refused.length > 0) throw new Error(`${JSON.stringify(action)} refused: ${refused.join()}`);
}

/** Whoever holds the move draws until it is `seat`'s. */
function turnOf(room: Room, seat: number): void {
  while (game(room).turn !== seat) act(room, game(room).turn, { type: "draw" });
}

const RUN = [fish(9), fish(10), fish(11)];
const GROUP = [fish(4), mouse(4, true), feather(4)];

function snapshots() {
  const waiting = lobby(true);
  const lobbySnap = waiting.snapshotFor("devB");

  const dealt = started(true);
  dealt.connect("devC");
  const withRack = dealt.snapshotFor("devA");
  const noRack = dealt.snapshotFor("devC");

  // Alice opens with 9-10-11, then bob adds a set of his own and the 12 to her run.
  const table = started();
  turnOf(table, 0);
  give(table, 0, RUN);
  act(table, 0, { type: "play", table: [RUN] }, "move-1");
  const opened = table.snapshotFor("devB");
  game(table).opened[1] = true;
  give(table, 1, [...GROUP, fish(12)]);
  act(table, 1, { type: "play", table: [[...RUN, fish(12)], GROUP] });
  const rearranged = table.snapshotFor("devA");

  // Bob lays down his last three pieces.
  const out = started();
  turnOf(out, 1);
  give(out, 1, RUN, 0);
  act(out, 1, { type: "play", table: [RUN] });
  const wentOut = out.snapshotFor("devA");

  // The pool is empty and both pass.
  const dry = started();
  turnOf(dry, 0);
  const g = game(dry);
  g.boxed.push(...g.pool.splice(0));
  act(dry, 0, { type: "pass" });
  const onePassed = dry.snapshotFor("devB");
  act(dry, 1, { type: "pass" });
  const blocked = dry.snapshotFor("devA");

  // Bob forfeits a three-seat game: he is out, the others play on.
  const three = started(true);
  act(three, 1, { type: "forfeit" });
  const forfeited = three.snapshotFor("devA");

  return { lobbySnap, withRack, noRack, opened, rearranged, wentOut, onePassed, blocked, forfeited };
}

function serverSamples(): Sample<ServerMessage>[] {
  const s = snapshots();
  const event = (seq: number, e: Extract<ServerMessage, { t: "event" }>["event"]): ServerMessage => ({ t: "event", seq, event: e });
  return [
    { name: "snapshot-lobby", message: s.lobbySnap },
    { name: "snapshot-playing-with-rack", message: s.withRack },
    { name: "snapshot-playing-no-rack", message: s.noRack },
    { name: "snapshot-playing-opened", message: s.opened },
    { name: "snapshot-playing-rearranged", message: s.rearranged },
    { name: "snapshot-playing-passed", message: s.onePassed },
    { name: "snapshot-playing-forfeited", message: s.forfeited },
    { name: "snapshot-over-out", message: s.wentOut },
    { name: "snapshot-over-blocked", message: s.blocked },
    { name: "event-drew-own", message: event(4, { kind: "tiles", event: { kind: "drew", seat: 1, tile: 17, poolCount: 77 } }) },
    { name: "event-drew-other", message: event(5, { kind: "tiles", event: { kind: "drew", seat: 0, poolCount: 76 } }) },
    {
      name: "event-played-opening",
      message: event(6, { kind: "tiles", event: { kind: "played", seat: 0, table: [RUN], placed: RUN, opened: true } }),
    },
    {
      name: "event-played",
      message: event(7, {
        kind: "tiles",
        event: { kind: "played", seat: 1, table: [[...RUN, fish(12)], [104, mouse(7), 58]], placed: [fish(12)], opened: false },
      }),
    },
    { name: "event-passed", message: event(8, { kind: "tiles", event: { kind: "passed", seat: 1 } }) },
    { name: "event-turn", message: event(9, { kind: "tiles", event: { kind: "turn", seat: 0 } }) },
    { name: "event-forfeited", message: event(10, { kind: "tiles", event: { kind: "forfeited", seat: 1 } }) },
    {
      name: "event-gameOver-out",
      message: event(11, { kind: "tiles", event: { kind: "gameOver", winners: [1], reason: "out", scores: [-35, 60, -25], left: [35, 0, 25] } }),
    },
    {
      name: "event-gameOver-blocked",
      message: event(12, { kind: "tiles", event: { kind: "gameOver", winners: [0, 1], reason: "blocked", scores: [2, 2, -9], left: [7, 7, 9] } }),
    },
    {
      name: "event-gameOver-forfeit",
      message: event(13, { kind: "tiles", event: { kind: "gameOver", winners: [0], reason: "forfeit", scores: [0, 0], left: [41, 0] } }),
    },
    { name: "event-presence", message: event(14, { kind: "presence", seat: 1, presence: "away" }) },
    ...(
      [
        "bad_action",
        "pool_empty",
        "pool_not_empty",
        "bad_piece",
        "duplicate_piece",
        "missing_piece",
        "not_your_piece",
        "nothing_played",
        "bad_set",
        "table_touched",
        "opening_too_low",
        "not_your_turn",
        "game_over",
        "forfeited",
        "game_off",
      ] as const
    ).map((code): Sample<ServerMessage> => ({ name: `error-${code}`, message: { t: "error", code } })),
  ];
}

const clientSamples: Sample<ClientMessage>[] = [
  { name: "act-draw", message: { t: "act", seat: 1, action: { type: "draw" } } },
  { name: "act-pass", message: { t: "act", seat: 1, action: { type: "pass" } } },
  { name: "act-forfeit", message: { t: "act", seat: 1, action: { type: "forfeit" } } },
  { name: "act-play-opening", message: { t: "act", seat: 0, action: { type: "play", table: [RUN] } } },
  {
    name: "act-play-id",
    message: { t: "act", seat: 1, action: { type: "play", table: [[...RUN, fish(12)], GROUP] }, id: "0f8fad5b-d9cb-469f-a165-70867728950e" },
  },
];

test("the tile game's server samples match the committed file, and are real", () => {
  const samples = serverSamples();
  check("tiles-server-messages.json", samples);
  const snaps = samples.flatMap((s) => (s.message.t === "snapshot" ? [s] : []));
  for (const { name, message } of snaps) {
    const { room } = message as Snapshot;
    // Every tile game snapshot says its game, keeps Cat Tower's key empty, and shows one rack at most.
    expect(room.gameId, name).toBe("tiles");
    expect(room.game, name).toBeNull();
    expect(Object.keys(room.tiles?.racks ?? {}).length, name).toBeLessThanOrEqual(1);
    for (const set of room.tiles?.table ?? []) expect(readSet(set), name).not.toBeNull();
    if (room.tiles) expect(piecesIn(room.tiles).length, name).toBe(new Set(piecesIn(room.tiles)).size);
  }
  expect(snaps.map((s) => (s.message as Snapshot).room.status)).toEqual([
    "lobby", "playing", "playing", "playing", "playing", "playing", "playing", "over", "over",
  ]);
});

test("the tile game's client samples match the committed file, and the room's parser takes each as it is", () => {
  check("tiles-client-messages.json", clientSamples);
  for (const { name, message } of clientSamples) {
    expect(parseClientMessage(JSON.stringify(message), tiles.parseAction), name).toEqual(message);
    // A Cat Tower room would refuse every one of them.
    expect(parseClientMessage(JSON.stringify(message)), name).toEqual(name === "act-forfeit" ? message : { error: "bad_message" });
  }
});
