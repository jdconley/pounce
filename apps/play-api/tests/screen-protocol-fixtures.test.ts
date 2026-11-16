import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { RoomCore } from "../src/room/core";
import { createRng } from "../src/rules/rng";

import type { Person, ServerMessage } from "../src/protocol";
import type { Outbound } from "../src/room/core";
import type { CatTowerState } from "../src/rules/engine";
import type { Group } from "../src/rules/groups";
import type { TilesState } from "../src/tiles/engine";

/**
 * What a TV table says that the apps shipped before the TV can still read: a snapshot with
 * `screen: true` (a field they don't know, so they ignore it), and `aim` messages (a `t` they
 * don't know, so they skip them). PounceKit and the web store decode these as they are today.
 * Not a pinned 1.0 file: it is new. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/screen-protocol-fixtures.test.ts`.
 */
type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Aim = Extract<ServerMessage, { t: "aim" }>;

const write = process.env.UPDATE_FIXTURES === "1";

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const alice: Person = { id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 0 };
const bob: Person = { id: "22222222-2222-4222-8222-222222222222", name: "Bob", cat: 3 };

/** A started two-seat table with a TV on (alice on devA, bob on devB, the screen "tv"). */
function table<S>(game?: string): RoomCore<S> {
  const state = RoomCore.create<S>("BCDFG", "devA", 1_000, undefined, undefined, game);
  const room = new RoomCore<S>(state, () => 1_000, createRng([1, 2, 3, 4]), undefined, 1, { streaks: false, tv: true });
  room.connect("devA");
  room.connect("devB");
  room.handle("devA", { t: "claim", seat: 0, person: alice });
  room.handle("devB", { t: "claim", seat: 1, person: bob });
  room.connect("tv", {}, "screen");
  const refused = room.handle("devA", { t: "start" }).filter((o) => o.message.t === "error");
  expect(refused).toEqual([]);
  return room;
}

const aimOf = (out: Outbound[]): Aim => {
  const aims = out.flatMap((o) => (o.message.t === "aim" ? [o.message] : []));
  expect(aims).toHaveLength(2); // to the other phone and to the TV
  return aims[0] as Aim;
};

function samples() {
  // Cat Tower: seat 0 holds the move, and points at a group seat 1 has laid.
  const cat = table<CatTowerState>();
  const snapshot = cat.snapshotFor("devA");
  const g = cat.state.gameState as CatTowerState;
  g.turn = 0;
  g.laid[1] = [{ kind: "set", cards: [1, 2, 3], value: 1 } satisfies Group];
  const aim = aimOf(cat.handle("devA", { t: "aim", seat: 0, aim: { target: { seat: 1, group: 0 } } }));
  const aimClear = aimOf(cat.handle("devA", { t: "aim", seat: 0 }));

  // Tiles: whoever holds the move points at a draft of the first three pieces on its own rack.
  const tile = table<TilesState>("tiles");
  const tilesSnapshot = tile.snapshotFor("devA");
  const t = tile.state.gameState as TilesState;
  const device = t.turn === 0 ? "devA" : "devB";
  const draft = (t.racks[t.turn] as number[]).slice(0, 3);
  const tilesAim = aimOf(tile.handle(device, { t: "aim", seat: t.turn, aim: { table: [draft] } }));

  return { snapshot, tilesSnapshot, aim, tilesAim, aimClear };
}

test("a TV table's samples match the committed file, and are real", () => {
  const s = samples();
  check("screen-server-messages.json", s);

  for (const message of [s.snapshot, s.tilesSnapshot] as Snapshot[]) {
    expect(message.t).toBe("snapshot");
    expect(message.room.screen).toBe(true);
    expect(message.room.status).toBe("playing");
  }
  expect(s.snapshot.room.gameId).not.toBe("tiles");
  expect(s.snapshot.room.game).not.toBeNull();
  expect(s.tilesSnapshot.room.gameId).toBe("tiles");
  expect(s.tilesSnapshot.room.tiles).toBeTruthy();

  // Aims carry no seq: the apps would not know to skip them otherwise.
  for (const aim of [s.aim, s.tilesAim, s.aimClear]) expect(Object.keys(aim)).not.toContain("seq");
  expect(s.aim.aim).toEqual({ target: { seat: 1, group: 0 } });
  expect((s.tilesAim.aim as { table: number[][] }).table[0]).toHaveLength(3);
  expect(s.aimClear).toEqual({ t: "aim", seat: 0 });
});
