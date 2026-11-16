import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { gameModule, type GameId } from "../games";
import { createRng } from "../rules/rng";

import { RoomCore, type Outbound } from "./core";

import type { GameAim, Person, ServerMessage } from "../protocol";
import type { CatTowerState } from "../rules/engine";
import type { TilesState } from "../tiles/engine";

/*
 * Whole random games through a room with a TV (a screen) and a spectator watching. Whatever
 * happens, nothing addressed to the TV is private: no hand, rack, drawn card or tile, no seat of
 * its own, and what it sees is what a spectator sees.
 */

const T0 = 1_000_000;
const MAX_STEPS = 3000;
const DAY = 24 * 60 * 60 * 1000;

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Kind = "human" | "pp" | "bot";

const CASES: { game: GameId; seeds: number; min: number; max: number }[] = [
  { game: "cat-tower", seeds: 40, min: 2, max: 6 },
  { game: "tiles", seeds: 60, min: 2, max: 4 },
];

/** The first snapshot without `screen`, which is the one thing that may differ for a screen. */
function withoutScreen(snap: Snapshot): unknown {
  const room: Record<string, unknown> = { ...snap.room };
  delete room.screen;
  return { ...snap, room };
}

type Counts = { draws: number; compared: number };

function playGame(game: GameId, n: number, min: number, max: number): { over: boolean; steps: number; tvMessages: number; counts: Counts } {
  const rng = createRng(seedOf(n * 7919 + (game === "tiles" ? 1 : 0)));
  const pick = (count: number) => Math.floor(rng() * count);
  let clock = T0;

  const state = RoomCore.create("BCDFG", "", clock, undefined, undefined, game, "tv");
  const room = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv: true, link: true, nudge: true });

  const seatCount = min + pick(max - min + 1);
  const kinds: Kind[] = Array.from({ length: seatCount }, (_, i) => {
    if (i === 0) return "human";
    const r = rng();
    return r < 0.45 ? "human" : r < 0.7 ? "pp" : "bot";
  });
  // A pass-and-play device holds two seats; a lone one is a human on a phone.
  const pp = kinds.flatMap((k, i) => (k === "pp" ? [i] : []));
  if (pp.length === 1) kinds[pp[0] as number] = "human";
  pp.splice(2).forEach((i) => (kinds[i] = "human"));
  const deviceOf = (seat: number) => (kinds[seat] === "pp" ? "pp" : `phone${seat}`);

  const tvSeen: Outbound[] = [];
  const counts: Counts = { draws: 0, compared: 0 };
  const check = (out: Outbound[]): void => {
    for (const o of out) {
      if (o.to !== "tv" && o.to !== "all") continue;
      const m = o.message;
      if (m.t === "snapshot") {
        if (o.to !== "tv") continue;
        const { room: view } = m;
        expect(view.game?.hands ?? {}).toEqual({});
        expect(view.tiles?.racks ?? {}).toEqual({});
        expect(view.seats.every((s) => !s.yours)).toBe(true);
        expect(view.youAreHost).toBe(false);
        if (m.seq === room.state.seq) {
          counts.compared += 1;
          expect(withoutScreen(m)).toEqual(withoutScreen(room.snapshotFor("spectator")));
        }
      }
      // A card taken from the discard pile was face up, so it is public; one from the deck is not.
      if (m.t === "event" && m.event.kind === "game" && m.event.event.kind === "drew" && m.event.event.from === "deck") {
        counts.draws += 1;
        expect(Object.hasOwn(m.event.event, "card")).toBe(false);
      }
      if (m.t === "event" && m.event.kind === "tiles" && m.event.event.kind === "drew") {
        counts.draws += 1;
        expect(Object.hasOwn(m.event.event, "tile")).toBe(false);
      }
      if (o.to === "tv") tvSeen.push(o);
    }
  };
  const send = (out: Outbound[]): Outbound[] => {
    check(out);
    return out;
  };

  send(room.connect("tv", {}, "screen"));
  send(room.connect("spectator"));
  const devices = [...new Set(kinds.flatMap((k, i) => (k === "bot" ? [] : [deviceOf(i)])))];
  for (const d of devices) send(room.connect(d));

  // Seats in order: the first to sit hosts, so seat 0 (always a person) is the host's.
  const host = deviceOf(0);
  kinds.forEach((k, i) => {
    if (k !== "bot") send(room.handle(deviceOf(i), { t: "claim", seat: i, person: person(i + 1) }));
  });
  room.state.seats.forEach((s, i) => {
    if (s.kind !== "open") return;
    send(room.handle(host, { t: "configure", seat: i, kind: i < seatCount ? "bot" : "closed" }));
  });
  expect(room.state.seats.map((s) => s.kind).filter((k) => k === "open")).toEqual([]);
  const started = send(room.handle(host, { t: "start" }));
  expect(started.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []))).toEqual([]);

  const module = gameModule(game);
  const humans = (seat: number) => kinds[seat] !== "bot";
  const aimFor = (seat: number): GameAim | undefined => {
    const g = room.state.gameState;
    if (game === "tiles") {
      const s = g as unknown as TilesState;
      const own = s.racks[seat] ?? [];
      return { table: [...s.table, ...(own.length > 0 && rng() < 0.5 ? [[own[0] as number]] : [])] };
    }
    const s = g as unknown as CatTowerState;
    const seats = s.laid.flatMap((groups, i) => ((groups?.length ?? 0) > 0 ? [i] : []));
    if (seats.length === 0) return undefined;
    const target = seats[pick(seats.length)] as number;
    return { target: { seat: target, group: pick(s.laid[target]?.length ?? 1) } };
  };

  let steps = 0;
  let tvOnline = true;
  while (room.state.status !== "over" && steps < MAX_STEPS) {
    steps += 1;
    if (rng() < 0.03) {
      if (tvOnline) room.disconnect("tv");
      else send(room.connect("tv", {}, "screen"));
      tvOnline = !tvOnline;
    }
    const actor = room.actor();
    if (actor !== null && humans(actor)) {
      const device = deviceOf(actor);
      if (rng() < 0.3) send(room.handle(device, { t: "aim", seat: actor, ...(rng() < 0.7 ? { aim: aimFor(actor) } : {}) }));
      const action = module.botAction(room.state.gameState, actor, rng);
      const acted = send(room.handle(device, { t: "act", seat: actor, action } as never));
      const refused = acted.flatMap((o) => (o.to === device && o.message.t === "error" ? [o.message.code] : []));
      expect({ game, seed: n, action, refused }).toEqual({ game, seed: n, action, refused: [] });
      clock += 1000;
    } else {
      clock = Math.max(clock, room.nextAlarm());
      expect(clock).toBeLessThan(T0 + DAY);
      send(room.tick());
    }
  }
  if (!tvOnline) send(room.connect("tv", {}, "screen"));
  return { over: room.state.status === "over", steps, tvMessages: tvSeen.length, counts };
}

describe("a screen never sees a private piece", () => {
  for (const { game, seeds, min, max } of CASES) {
    it(`${game}: ${seeds} random whole games`, () => {
      const total: Counts = { draws: 0, compared: 0 };
      for (let n = 1; n <= seeds; n++) {
        const result = playGame(game, n, min, max);
        expect({ game, seed: n, over: result.over }).toEqual({ game, seed: n, over: true });
        expect(result.tvMessages).toBeGreaterThan(0);
        total.draws += result.counts.draws;
        total.compared += result.counts.compared;
      }
      // Each check must have run, or it proves nothing.
      expect(total.draws).toBeGreaterThan(0);
      expect(total.compared).toBeGreaterThan(0);
    }, 60_000);
  }
});
