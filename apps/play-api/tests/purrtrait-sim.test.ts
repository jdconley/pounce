import { expect, test } from "vitest";

import { EASEL_HEIGHT, EASEL_WIDTH, type InkOp } from "../src/purrtrait/ink";
import { turnKey } from "../src/purrtrait/view";
import { RoomCore, SCREEN_GRACE_MS, STALL_END_MS, type Outbound } from "../src/room/core";

import type { ClientMessage, Person } from "../src/protocol";
import type { PurrState } from "../src/purrtrait/engine";
import type { PurrView } from "../src/purrtrait/view";
import type { Seat } from "../src/rules/engine";

/**
 * A soak through the room, as a family plays: random tables of 2-10 seats (some with a second
 * device for a seat), random picks, ink, gotIt, giveUp, clocks running out, the host removing
 * people, people leaving, the TV dropping and coming back (sometimes for good), and junk from
 * every phone. Every game must end, nothing may throw, and along the way ink and the word reach
 * only the TV and the drawer's device. `PURRTRAIT_SOAK=<games>` plays more.
 */
const GAMES = Number(process.env.PURRTRAIT_SOAK ?? 1000);
const MAX_STEPS = 4000;
const ON = ["cat-tower", "purrtrait"] as const;

type Room = RoomCore<PurrState>;

function mulberry(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 2 ** 32;
  };
}

const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });

/** The drawer's easel as its device sees it, to send ink the room takes. */
type Easel = { turn: string; next: number; ends: Map<number, [number, number]> };

function playOne(seed: number): { steps: number; reason: string } {
  const rand = mulberry(seed);
  const pick = <T>(xs: readonly T[]): T => xs[Math.floor(rand() * xs.length)] as T;
  let clock = 1_000_000;
  const seats = 2 + Math.floor(rand() * 9);
  const state = RoomCore.create<PurrState>("BCDFG", "", clock, undefined, undefined, "purrtrait", "tv");
  const r: Room = new RoomCore<PurrState>(state, () => clock, rand, undefined, 1, { games: ON, tv: true, streaks: false });
  const devices: string[] = [];
  const check = (out: Outbound[]): Outbound[] => {
    const s = r.state.gameState;
    const owner = r.state.drawerDevice?.deviceId;
    for (const o of out) {
      if (o.message.t === "ink") expect(o.to === "tv" || o.to === owner, `seed ${seed}: ink to ${o.to}`).toBe(true);
      if (o.message.t !== "snapshot" || !s) continue;
      const v = o.message.room.purrtrait as PurrView;
      if (v.word === undefined && v.choices === undefined) continue;
      const drives = s.drawer !== null && r.controlledSeats(o.to).includes(s.drawer);
      expect(drives && (v.choices !== undefined || owner === undefined || owner === o.to), `seed ${seed}: word to ${o.to}`).toBe(true);
    }
    return out;
  };
  const send = (device: string, msg: ClientMessage) => check(r.handle(device, msg));
  const tick = () => check(r.tick());

  check(r.connect("tv"));
  for (let seat = 0; seat < seats; seat++) {
    const device = `d${seat}`;
    devices.push(device);
    if (r.state.seats[seat]?.kind === "closed") send("d0", { t: "configure", seat, kind: "open" });
    check(r.connect(device, { [person(seat).id]: `p${seat}` }));
    send(device, { t: "claim", seat, person: person(seat) });
    // A parent's iPad that speaks for the same person.
    if (rand() < 0.2) {
      devices.push(`x${seat}`);
      check(r.connect(`x${seat}`, { [person(seat).id]: `p${seat}` }));
    }
  }
  for (let seat = seats; seat < r.state.seats.length; seat++) send("d0", { t: "configure", seat, kind: "closed" });
  if (rand() < 0.5) send("d0", { t: "setOptions", options: { timer: pick([45, 60, 90] as const) } });
  expect(send("d0", { t: "start" }).flatMap((o) => (o.message.t === "error" ? [o.message.code] : [])), `seed ${seed}`).toEqual([]);

  let tvHere = true;
  let easel = null as Easel | null;
  const inkBatch = (e: Easel): InkOp[] => {
    const roll = rand();
    const live = [...e.ends.keys()];
    if (roll < 0.05) {
      e.ends.clear();
      return [["c"]];
    }
    if (roll < 0.12 && live.length > 0) {
      const id = pick(live);
      e.ends.delete(id);
      return [["u", id]];
    }
    if (roll < 0.55 && live.length > 0) {
      const id = pick(live);
      let [x, y] = e.ends.get(id) as [number, number];
      const deltas: number[] = [];
      for (let i = 0; i < 1 + Math.floor(rand() * 6); i++) {
        const dx = Math.max(-x, Math.min(EASEL_WIDTH - 1 - x, Math.floor(rand() * 41) - 20));
        const dy = Math.max(-y, Math.min(EASEL_HEIGHT - 1 - y, Math.floor(rand() * 41) - 20));
        x += dx;
        y += dy;
        deltas.push(dx, dy);
      }
      e.ends.set(id, [x, y]);
      return [["p", id, ...deltas]];
    }
    const id = e.next++;
    const [x, y] = [Math.floor(rand() * EASEL_WIDTH), Math.floor(rand() * EASEL_HEIGHT)];
    e.ends.set(id, [x, y]);
    return [["s", id, Math.floor(rand() * 9), Math.floor(rand() * 3), x, y]];
  };

  let steps = 0;
  while (r.state.status !== "over") {
    if (++steps > MAX_STEPS) throw new Error(`seed ${seed}: no end after ${MAX_STEPS} steps`);
    const s = r.state.gameState as PurrState;
    const turn = turnKey(s);
    const drawer = s.drawer as Seat;
    const owner = r.state.drawerDevice?.deviceId;
    const drivers = devices.filter((d) => r.controlledSeats(d).includes(drawer));
    const actor = owner ?? (drivers.length > 0 ? pick(drivers) : null);
    const roll = rand();

    // The TV drops, and comes back after a while; now and then it stays away for good.
    if (!tvHere) {
      clock += rand() < 0.02 ? STALL_END_MS : SCREEN_GRACE_MS + Math.floor(rand() * 60_000);
      tick();
      if (rand() < 0.7) {
        check(r.connect("tv"));
        tvHere = true;
      }
      continue;
    }
    if (roll < 0.03) {
      check(r.disconnect("tv"));
      tvHere = false;
      continue;
    }
    // The host takes a seat away, or someone leaves.
    if (roll < 0.05) {
      const host = r.state.hostDeviceId;
      send(host === "" ? "tv" : host, { t: "remove", seat: Math.floor(rand() * seats) });
      continue;
    }
    if (roll < 0.06) {
      const seat = Math.floor(rand() * seats);
      const who = devices.find((d) => r.controlledSeats(d).includes(seat));
      if (who) send(who, { t: "act", seat, action: { type: "forfeit" } });
      continue;
    }
    // Junk from anyone who isn't drawing: ink, a gotIt or a give-up that isn't theirs, a room-only action.
    if (roll < 0.1) {
      const drawing = owner === undefined ? drivers : [owner];
      const from = pick([...devices.filter((d) => !drawing.includes(d)), "tv"]);
      const junk: ClientMessage[] = [
        { t: "ink", seat: drawer, turn: turn, ops: [["s", 0, 0, 0, 1, 1]] },
        { t: "ink", seat: drawer, turn: "9:99", ops: [["c"]] },
        { t: "act", seat: drawer, action: { type: "gotIt", seat: Math.floor(rand() * seats) } },
        { t: "act", seat: drawer, action: { type: "giveUp" } },
        { t: "act", seat: drawer, action: { type: "timeUp" } } as unknown as ClientMessage,
      ];
      send(from, pick(junk));
      continue;
    }
    if (s.phase === "reveal") {
      clock += 6_000;
      tick();
      continue;
    }
    // The clock runs out.
    if (roll < 0.16 || actor === null) {
      const at = r.state.timers.turnEndsAt;
      clock = at === null || at === undefined ? clock + 1_000 : Math.max(clock, at);
      tick();
      continue;
    }
    if (s.phase === "choosing") {
      send(actor, { t: "act", seat: drawer, action: { type: "choose", level: rand() < 0.5 ? "easy" : "tricky" } });
      continue;
    }
    // Drawing: mostly ink, now and then the turn ends.
    if (easel?.turn !== turn) easel = { turn: turn, next: 0, ends: new Map() };
    if (roll < 0.85) {
      clock += 50;
      const out = send(actor, { t: "ink", seat: drawer, turn: turn, ops: inkBatch(easel) });
      const refused = out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
      expect(refused, `seed ${seed}: ink`).toEqual([]);
      expect(out.some((o) => o.to === "tv" && o.message.t === "ink"), `seed ${seed}: ink reached the TV`).toBe(true);
    } else if (roll < 0.95) {
      const guessers = s.out.flatMap((out, seat) => (out || seat === drawer ? [] : [seat]));
      send(actor, { t: "act", seat: drawer, action: { type: "gotIt", seat: pick(guessers) } });
    } else {
      send(actor, { t: "act", seat: drawer, action: { type: "giveUp" } });
    }
  }
  const end = r.state.gameState as PurrState;
  expect(end.phase, `seed ${seed}`).toBe("over");
  expect(end.winners.length, `seed ${seed}`).toBeGreaterThan(0);
  expect(JSON.stringify(r.state), `seed ${seed}`).not.toMatch(/"ops"/);
  return { steps, reason: end.endReason as string };
}

test(`${GAMES} random Purrtrait games at 2-10 seats all end`, () => {
  const reasons: Record<string, number> = {};
  let steps = 0;
  for (let seed = 1; seed <= GAMES; seed++) {
    const played = playOne(seed);
    steps += played.steps;
    reasons[played.reason] = (reasons[played.reason] ?? 0) + 1;
  }
  // Each way a game ends happens: two rounds played out, too few left, the TV gone for good.
  expect(Object.keys(reasons).sort()).toEqual(["left", "rounds", "stalled"]);
  expect(steps / GAMES).toBeGreaterThan(10);
}, 60_000);
