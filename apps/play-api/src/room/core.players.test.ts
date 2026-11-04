import { beforeEach, describe, expect, it } from "vitest";

import { card } from "../rules/cards";

import { RoomCore, type Outbound } from "./core";

import type { Person, ServerMessage } from "../protocol";
import type { CatTowerState, Seat } from "../rules/engine";

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});
const P1 = person(1).id;
const P2 = person(2).id;

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const presenceTo = (out: Outbound[], to: string) =>
  out.flatMap((o) =>
    o.to === to && o.message.t === "event" && o.message.event.kind === "presence" ? [o.message.event] : [],
  );
const snapshotTo = (out: Outbound[], to: string): Snapshot =>
  out.find((o) => o.to === to && o.message.t === "snapshot")?.message as Snapshot;

const newRoom = (host = "phone") => new RoomCore(RoomCore.create("BCDFG", host, clock), () => clock, rng);

/** The phone claims seat 0 as person 1 (player A unless `legacy`); three bots follow; the game starts. */
function startedWithPlayer({ legacy = false, ipad = true } = {}): RoomCore {
  const room = newRoom();
  room.connect("phone", legacy ? {} : { [P1]: A });
  if (ipad) room.connect("ipad", { [P1]: A });
  room.handle("phone", { t: "claim", seat: 0, person: person(1) });
  for (const seat of [1, 2, 3]) room.handle("phone", { t: "configure", seat, kind: "bot" });
  expect(errorsOf(room.handle("phone", { t: "start" }))).toEqual([]);
  return room;
}

const game = (room: RoomCore) => room.state.gameState as CatTowerState;

function tickUntilTurn(room: RoomCore, seat: Seat): void {
  for (let i = 0; game(room).turn !== seat || game(room).status !== "playing"; i++) {
    if (i > 200) throw new Error("turn never arrived");
    clock = room.state.timers.botAt as number;
    room.tick();
  }
}

const away = (room: RoomCore, ...devices: string[]) => {
  for (const d of devices) room.handle(d, { t: "presence", state: "background" });
};

describe("seats belong to players", () => {
  it("a claim stamps the seat with the device's player for that person", () => {
    const room = newRoom();
    room.connect("phone", { [P1]: A });
    room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(room.state.seats[0]?.playerId).toBe(A);
  });

  it("a claim from a device without a map leaves the seat to its device", () => {
    const room = newRoom();
    room.connect("phone");
    room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(room.state.seats[0]).not.toHaveProperty("playerId");
  });

  it("another device of the same player controls the seat and sees it as theirs", () => {
    const room = newRoom();
    room.connect("phone", { [P1]: A });
    room.connect("ipad", { [P1]: A });
    room.connect("other");
    const out = room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(room.controlledSeats("ipad")).toEqual([0]);
    expect(room.controlledSeats("other")).toEqual([]);
    expect(snapshotTo(out, "ipad").room.seats[0]?.yours).toBe(true);
    expect(snapshotTo(out, "other").room.seats[0]?.yours).toBe(false);
  });

  it("one player can't take two seats, even as two people", () => {
    const room = newRoom();
    room.connect("phone", { [P1]: A, [P2]: A });
    room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(errorsOf(room.handle("phone", { t: "claim", seat: 1, person: person(2) }))).toEqual(["person_seated"]);
  });

  it("the other device can rename, leave and move the seat", () => {
    const room = newRoom();
    room.connect("phone", { [P1]: A });
    room.connect("ipad", { [P1]: A });
    room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    expect(errorsOf(room.handle("ipad", { t: "renameSeat", seat: 0, name: "Mochi" }))).toEqual([]);
    expect(room.state.seats[0]?.person?.name).toBe("Mochi");
    expect(room.handle("ipad", { t: "moveSeat", seat: 0 })[0]?.message.t).toBe("moveCode");
    expect(errorsOf(room.handle("ipad", { t: "leave", seat: 0 }))).toEqual([]);
    expect(room.state.seats[0]?.kind).toBe("open");
  });

  it("seatPlayers lists each seated player once", () => {
    const room = newRoom();
    room.connect("phone", { [P1]: A });
    room.connect("wife", { [P2]: B });
    room.handle("phone", { t: "claim", seat: 0, person: person(1) });
    room.handle("wife", { t: "claim", seat: 1, person: person(2) });
    room.handle("phone", { t: "configure", seat: 2, kind: "bot" });
    expect(room.seatPlayers()).toEqual([A, B]);
  });
});

describe("presence across a player's devices", () => {
  it("a seat stays awake while any of its devices is", () => {
    const room = startedWithPlayer();
    room.connect("watcher");
    const out = room.handle("phone", { t: "presence", state: "background" });
    expect(presenceTo(out, "watcher")).toEqual([]);
    expect(room.snapshotFor("watcher").room.seats[0]?.presence).toBe("awake");
    const later = room.handle("ipad", { t: "presence", state: "background" });
    expect(presenceTo(later, "watcher")).toEqual([{ kind: "presence", seat: 0, presence: "away" }]);
  });

  it("the seat goes asleep only when its last device does", () => {
    const room = startedWithPlayer();
    room.connect("watcher");
    room.disconnect("phone");
    clock += 4 * 60_000;
    room.disconnect("ipad");
    clock += 60_000 + 1;
    expect(presenceTo(room.tick(), "watcher")).toEqual([]);
    clock += 4 * 60_000;
    expect(presenceTo(room.tick(), "watcher")).toEqual([{ kind: "presence", seat: 0, presence: "asleep" }]);
  });
});

describe("pushes for players", () => {
  it("no push while another of the player's devices is awake", () => {
    const room = startedWithPlayer();
    away(room, "phone");
    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toEqual([]);
  });

  it("a push names the player when every device is away", () => {
    const room = startedWithPlayer();
    away(room, "phone", "ipad");
    tickUntilTurn(room, 0);
    expect(room.drainPushIntents()).toEqual([
      { kind: "your_turn", deviceId: "phone", playerId: A, seat: 0, personName: "Cat 1", tableName: room.state.name, code: "BCDFG" },
    ]);
  });

  it("acting on a pushed turn tells the player's other devices to clear it, once", () => {
    const room = startedWithPlayer();
    away(room, "phone", "ipad");
    tickUntilTurn(room, 0);
    room.drainPushIntents();
    room.handle("ipad", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.drainPushIntents()).toEqual([{ kind: "dismiss", playerId: A, exceptDeviceId: "ipad", code: "BCDFG" }]);
    const hand = game(room).hands[0] as number[];
    const discard = hand.find((id) => card(id).kind === "number") as number;
    room.handle("ipad", { t: "act", seat: 0, action: { type: "discard", card: discard } });
    expect(room.drainPushIntents()).toEqual([]);
  });

  it("no dismiss when no push went out, or the seat has no player", () => {
    const room = startedWithPlayer();
    tickUntilTurn(room, 0);
    room.handle("ipad", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(room.drainPushIntents()).toEqual([]);

    const legacy = startedWithPlayer({ legacy: true, ipad: false });
    away(legacy, "phone");
    tickUntilTurn(legacy, 0);
    expect(legacy.drainPushIntents()).toHaveLength(1);
    legacy.handle("phone", { t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    expect(legacy.drainPushIntents()).toEqual([]);
  });

  it("a rejected act sends no dismiss", () => {
    const room = startedWithPlayer();
    away(room, "phone", "ipad");
    tickUntilTurn(room, 0);
    room.drainPushIntents();
    room.handle("ipad", { t: "act", seat: 0, action: { type: "discard", card: 0 } });
    expect(room.drainPushIntents()).toEqual([]);
  });
});

describe("adopt", () => {
  it("backfills players on seats claimed by person, once", () => {
    const room = startedWithPlayer({ legacy: true });
    expect(room.controlledSeats("ipad")).toEqual([]);
    const out = room.adopt({ person: { [P1]: A } });
    expect(room.state.seats[0]?.playerId).toBe(A);
    expect(room.controlledSeats("ipad")).toEqual([0]);
    expect(snapshotTo(out, "ipad").room.seats[0]?.yours).toBe(true);
    expect(room.adopt({ person: { [P1]: A } })).toEqual([]);
  });

  it("by person never overwrites a seat's player", () => {
    const room = startedWithPlayer();
    expect(room.adopt({ person: { [P1]: B } })).toEqual([]);
    expect(room.state.seats[0]?.playerId).toBe(A);
  });

  it("moves seats from one player to another", () => {
    const room = startedWithPlayer();
    room.connect("b-device", { [P2]: B });
    room.adopt({ from: A, to: B });
    expect(room.state.seats[0]?.playerId).toBe(B);
    expect(room.controlledSeats("b-device")).toEqual([0]);
    expect(room.controlledSeats("ipad")).toEqual([]);
  });

  it("with no target, the seat falls back to the device that holds it", () => {
    const room = startedWithPlayer();
    room.adopt({ from: A, to: null });
    expect(room.state.seats[0]).not.toHaveProperty("playerId");
    expect(room.controlledSeats("ipad")).toEqual([]);
    expect(room.controlledSeats("phone")).toEqual([0]);
    expect(room.adopt({ from: A, to: null })).toEqual([]);
  });
});
