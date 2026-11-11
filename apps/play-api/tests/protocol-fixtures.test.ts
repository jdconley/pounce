import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { parseClientMessage } from "../src/protocol";
import { RoomCore } from "../src/room/core";
import { createRng } from "../src/rules/rng";
import { newPair, report, view } from "../src/streaks/pair-core";

import type { ClientMessage, Person, ServerMessage } from "../src/protocol";
import type { CatTowerState } from "../src/rules/engine";

/**
 * Shared with the Swift client (PounceKit): it decodes every server sample and
 * encodes every client sample, looking each up by `name`. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/protocol-fixtures.test.ts`.
 */
type Sample<M> = { name: string; message: M };

const write = process.env.UPDATE_FIXTURES === "1";

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const alice: Person = { id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 0 };
const bob: Person = { id: "22222222-2222-4222-8222-222222222222", name: "Bob", cat: 3 };

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

/** Real snapshots from a real room: alice (devA), bob (devB), a bot, and a seatless devC. */
function snapshots(): { lobby: Snapshot; withHand: Snapshot; noHand: Snapshot } {
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", 1_000), () => 1_000, createRng([1, 2, 3, 4]));
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.handle("devA", { t: "configure", seat: 2, kind: "bot" });
  const lobby = room.snapshotFor("devB");
  room.connect("devC");
  room.handle("devA", { t: "start" });
  return { lobby, withHand: room.snapshotFor("devA"), noHand: room.snapshotFor("devC") };
}

/** A room with `LINK` on: alice's (devA) snapshot after her move "move-1", bob's phone just dropped. */
function linkSnapshot(): Snapshot {
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", 1_000), () => 1_000, createRng([1, 2, 3, 4]), undefined, 1, {
    streaks: false,
    link: true,
  });
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.handle("devA", { t: "start" });
  // Seat 1 plays first.
  room.handle("devB", { t: "act", seat: 1, action: { type: "draw", from: "deck" }, id: "move-0" });
  room.disconnect("devB", false);
  (room.state.devices.devA as { acks?: string[] }).acks = ["move-1"];
  return room.snapshotFor("devA");
}

/**
 * Alice's (devA) snapshot of a game that ended early: she drew while down on
 * phase 10 and bob, on phase 4, could no longer catch her.
 */
function decidedSnapshot(): Snapshot {
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", 1_000), () => 1_000, createRng([1, 2, 3, 4]), undefined, 1, {
    streaks: false,
  });
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.handle("devA", { t: "start" });
  const game = room.state.gameState as CatTowerState;
  game.turn = 0;
  game.step = "draw";
  game.phase = [9, 3];
  game.laid[0] = [{ kind: "set", cards: [8, 32, 56], value: 9 }];
  room.handle("devA", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
  return room.snapshotFor("devA");
}

/** Alice (devA), bob (devB) and a bot: bob forfeited (§5.13); alice's snapshot. */
function forfeitedSnapshot(): Snapshot {
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", 1_000), () => 1_000, createRng([1, 2, 3, 4]));
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.handle("devA", { t: "configure", seat: 2, kind: "bot" });
  room.handle("devA", { t: "start" });
  room.handle("devB", { t: "act", seat: 1, action: { type: "forfeit" } });
  return room.snapshotFor("devA");
}

/** A room with `NUDGE` on, two minutes into bob's (devB) turn: alice's (devA) snapshot, before and after she nudged him. */
function nudgeSnapshots(): { ready: Snapshot; sent: Snapshot } {
  let now = 1_000;
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", now), () => now, createRng([1, 2, 3, 4]), undefined, 1, {
    streaks: false,
    nudge: true,
  });
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.handle("devA", { t: "start" });
  // Seat 1 plays first.
  now += 90_000;
  const ready = room.snapshotFor("devA");
  now += 30_000;
  room.handle("devA", { t: "nudge", seat: 1 });
  return { ready, sent: room.snapshotFor("devA") };
}

function serverSamples(): Sample<ServerMessage>[] {
  const nudge = nudgeSnapshots();
  const { lobby, withHand, noHand } = snapshots();
  return [
    { name: "snapshot-lobby", message: lobby },
    { name: "snapshot-playing-with-hand", message: withHand },
    { name: "snapshot-playing-no-hand", message: noHand },
    { name: "event-presence", message: { t: "event", seq: 2, event: { kind: "presence", seat: 1, presence: "away" } } },
    {
      name: "event-roundStarted",
      message: { t: "event", seq: 3, event: { kind: "game", event: { kind: "roundStarted", round: 2, dealer: 1 } } },
    },
    {
      name: "event-drew-deck-own",
      message: { t: "event", seq: 4, event: { kind: "game", event: { kind: "drew", seat: 1, from: "deck", card: 17 } } },
    },
    {
      name: "event-drew-deck-other",
      message: { t: "event", seq: 5, event: { kind: "game", event: { kind: "drew", seat: 2, from: "deck" } } },
    },
    {
      name: "event-drew-discard",
      message: { t: "event", seq: 6, event: { kind: "game", event: { kind: "drew", seat: 1, from: "discard", card: 40 } } },
    },
    {
      name: "event-laidDown",
      message: {
        t: "event",
        seq: 7,
        event: {
          kind: "game",
          event: {
            kind: "laidDown",
            seat: 1,
            groups: [
              { kind: "set", cards: [4, 28, 52], value: 5 },
              { kind: "set", cards: [8, 32, 56], value: 9 },
            ],
          },
        },
      },
    },
    {
      name: "event-hit",
      message: {
        t: "event",
        seq: 8,
        event: {
          kind: "game",
          event: {
            kind: "hit",
            seat: 0,
            card: 76,
            target: { seat: 1, group: 0 },
            group: { kind: "set", cards: [4, 28, 52, 76], value: 5 },
          },
        },
      },
    },
    {
      name: "event-discarded",
      message: { t: "event", seq: 9, event: { kind: "game", event: { kind: "discarded", seat: 1, card: 11 } } },
    },
    {
      name: "event-discarded-skip",
      message: {
        t: "event",
        seq: 10,
        event: { kind: "game", event: { kind: "discarded", seat: 0, card: 104, skipTarget: 2 } },
      },
    },
    { name: "event-skipped", message: { t: "event", seq: 11, event: { kind: "game", event: { kind: "skipped", seat: 2 } } } },
    { name: "event-turn", message: { t: "event", seq: 12, event: { kind: "game", event: { kind: "turn", seat: 0 } } } },
    {
      name: "event-reshuffled",
      message: { t: "event", seq: 13, event: { kind: "game", event: { kind: "reshuffled", deckCount: 94 } } },
    },
    {
      name: "event-roundOver",
      message: {
        t: "event",
        seq: 14,
        event: {
          kind: "game",
          event: {
            kind: "roundOver",
            wentOut: 1,
            points: [35, 0, 40],
            advanced: [1],
            scores: [35, 0, 40],
            phase: [0, 1, 0],
          },
        },
      },
    },
    {
      name: "event-roundOver-nobody",
      message: {
        t: "event",
        seq: 15,
        event: {
          kind: "game",
          event: {
            kind: "roundOver",
            wentOut: null,
            points: [20, 45, 30],
            advanced: [],
            scores: [20, 45, 30],
            phase: [0, 0, 0],
          },
        },
      },
    },
    {
      name: "event-gameOver",
      message: { t: "event", seq: 16, event: { kind: "game", event: { kind: "gameOver", winners: [1] } } },
    },
    {
      name: "event-gameOver-decided",
      message: {
        t: "event",
        seq: 16,
        event: { kind: "game", event: { kind: "gameOver", winners: [0], reason: "decided" } },
      },
    },
    { name: "moveCode", message: { t: "moveCode", seat: 1, code: "BCDFGH" } },
    { name: "error-room_closed", message: { t: "error", code: "room_closed" } },
    { name: "error-bad_code", message: { t: "error", code: "bad_code" } },
    { name: "pong", message: { t: "pong" } },
    { name: "link", message: { t: "link", seats: [null, "weak", "lost"] } },
    { name: "snapshot-playing-link", message: linkSnapshot() },
    { name: "snapshot-over-decided", message: decidedSnapshot() },
    { name: "event-forfeited", message: { t: "event", seq: 17, event: { kind: "game", event: { kind: "forfeited", seat: 1 } } } },
    { name: "snapshot-playing-forfeited", message: forfeitedSnapshot() },
    { name: "error-forfeited", message: { t: "error", code: "forfeited" } },
    { name: "snapshot-playing-nudge-wait", message: nudge.ready },
    { name: "snapshot-playing-nudge-sent", message: nudge.sent },
    { name: "nudgeSent", message: { t: "nudgeSent", seat: 1 } },
    { name: "nudged", message: { t: "nudged", seat: 1, from: 0 } },
    { name: "error-not_their_turn", message: { t: "error", code: "not_their_turn" } },
  ] satisfies Sample<ServerMessage>[];
}

function clientSamples(): Sample<ClientMessage>[] {
  return [
    { name: "claim", message: { t: "claim", seat: 0, person: alice } },
    { name: "configure-open", message: { t: "configure", seat: 1, kind: "open" } },
    { name: "configure-bot", message: { t: "configure", seat: 2, kind: "bot" } },
    { name: "configure-closed", message: { t: "configure", seat: 3, kind: "closed" } },
    { name: "start", message: { t: "start" } },
    { name: "act-draw-deck", message: { t: "act", seat: 0, action: { type: "draw", from: "deck" } } },
    { name: "act-draw-discard", message: { t: "act", seat: 0, action: { type: "draw", from: "discard" } } },
    {
      name: "act-layDown",
      message: {
        t: "act",
        seat: 0,
        action: { type: "layDown", groups: [{ cards: [4, 28, 52] }, { cards: [8, 32, 56] }] },
      },
    },
    {
      name: "act-layDown-runStart",
      message: {
        t: "act",
        seat: 0,
        action: { type: "layDown", groups: [{ cards: [9, 10, 11, 96], runStart: 9 }] },
      },
    },
    {
      name: "act-hit",
      message: { t: "act", seat: 0, action: { type: "hit", card: 76, target: { seat: 1, group: 0 } } },
    },
    {
      name: "act-hit-side",
      message: { t: "act", seat: 0, action: { type: "hit", card: 96, target: { seat: 1, group: 0 }, side: "start" } },
    },
    { name: "act-discard", message: { t: "act", seat: 0, action: { type: "discard", card: 11 } } },
    {
      name: "act-discard-skip",
      message: { t: "act", seat: 0, action: { type: "discard", card: 104, skipTarget: 2 } },
    },
    { name: "act-nextRound", message: { t: "act", seat: 0, action: { type: "nextRound" } } },
    { name: "presence-active", message: { t: "presence", state: "active" } },
    { name: "presence-background", message: { t: "presence", state: "background" } },
    { name: "moveSeat", message: { t: "moveSeat", seat: 1 } },
    { name: "claimMove", message: { t: "claimMove", code: "BCDFGH" } },
    { name: "leave", message: { t: "leave", seat: 1 } },
    { name: "rename", message: { t: "rename", name: "Taco Night" } },
    { name: "renameSeat", message: { t: "renameSeat", seat: 1, name: "Mo" } },
    {
      name: "act-draw-deck-id",
      message: { t: "act", seat: 0, action: { type: "draw", from: "deck" }, id: "0F8C1D2E-3A4B-4C5D-8E6F-7A8B9C0D1E2F" },
    },
    { name: "ping", message: { t: "ping" } },
    { name: "link-weak", message: { t: "link", state: "weak" } },
    { name: "link-good", message: { t: "link", state: "good" } },
    { name: "act-forfeit", message: { t: "act", seat: 1, action: { type: "forfeit" } } },
    { name: "nudge", message: { t: "nudge", seat: 1 } },
  ] satisfies Sample<ClientMessage>[];
}

test("server message fixtures match the server", () => {
  check("server-messages.json", serverSamples());
});

test("client message fixtures parse to themselves", () => {
  for (const { name, message } of clientSamples()) {
    expect(parseClientMessage(JSON.stringify(message)), name).toEqual(message);
  }
  check("client-messages.json", clientSamples());
});

test("playing snapshot keys hands by string seat", () => {
  const snap = serverSamples().find((s) => s.name === "snapshot-playing-with-hand")?.message;
  const room = (JSON.parse(JSON.stringify(snap)) as Snapshot).room;
  expect(Object.keys(room.game?.hands ?? {})).toEqual(["0"]);
});

test("no sample leaks server-only state", () => {
  const text = JSON.stringify(serverSamples());
  expect(text).not.toContain('"seed":');
  expect(text).not.toContain('"deck":');
  const noHand = serverSamples().find((s) => s.name === "snapshot-playing-no-hand")?.message as Snapshot;
  expect(noHand.room.game?.hands).toEqual({});
});

const PA = "p_AAAAAAAAAAAAAAAAAAAAAA";
const PB = "p_BBBBBBBBBBBBBBBBBBBBBB";
const day = (h: number) => Date.UTC(2026, 10, 4, h);

/**
 * The streak additions (§13.4), kept apart from the files above so the
 * Swift tests, which decode every server sample and count the client ones,
 * are unchanged until the app adopts them (PR 4).
 */
function streakServerSamples(): Sample<ServerMessage>[] {
  const zone = "America/Los_Angeles";
  const pair = newPair(
    "pair_3f9cAAAAAAAAAAAAAAAAAA",
    [
      { id: PA, name: "Alice", cat: 0, zone, quietStart: 1320 },
      { id: PB, name: "Bob", cat: 3, zone, quietStart: 1320 },
    ],
    day(16),
    [1, 2, 3, 4],
  );
  report(pair, { code: "BCDFG", at: day(17), by: PA, holder: PB, over: false }, day(17));
  report(pair, { code: "BCDFG", at: day(18), by: PB, holder: PA, over: false }, day(18));
  const room = new RoomCore(RoomCore.create("BCDFG", "devA", 1_000), () => 1_000, createRng([1, 2, 3, 4]), undefined, 1, {
    streaks: true,
  });
  room.connect("devA");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  return [
    { name: "streak", message: { t: "streak", pair: pair.id, person: alice.id, view: view(pair, PA, day(18)) } },
    { name: "rematch", message: { t: "rematch", code: "NWCDF" } },
    { name: "event-look", message: { t: "event", seq: 9, event: { kind: "look", seat: 1, rug: "rug-night-sky", back: "back-crown" } } },
    { name: "snapshot-lobby-with-look", message: room.snapshotFor("devA") },
    { name: "error-not_unlocked", message: { t: "error", code: "not_unlocked" } },
    { name: "error-too_soon", message: { t: "error", code: "too_soon" } },
    { name: "error-not_over", message: { t: "error", code: "not_over" } },
  ];
}

function streakClientSamples(): Sample<ClientMessage>[] {
  return [
    { name: "rematch", message: { t: "rematch" } },
    { name: "setLook-rug", message: { t: "setLook", rug: "rug-night-sky" } },
    { name: "setLook-back", message: { t: "setLook", back: "back-crown" } },
    { name: "setLook-both", message: { t: "setLook", rug: "rug-classic", back: "back-violet-paw" } },
  ];
}

test("streak fixtures match the server and parse to themselves", () => {
  check("streaks-server-messages.json", streakServerSamples());
  for (const { name, message } of streakClientSamples()) {
    expect(parseClientMessage(JSON.stringify(message)), name).toEqual(message);
  }
  check("streaks-client-messages.json", streakClientSamples());
});
