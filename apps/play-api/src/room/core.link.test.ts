import { beforeEach, describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";

import { RoomCore, type Outbound, type RoomFeatures } from "./core";
import { DROPPED_FOR_MS, LINK_PING_MS, LOST_AFTER_MS, WEAK_AFTER_MS } from "./link";

import type { Person, SeatLink, ServerMessage } from "../protocol";
import type { CatTowerState } from "../rules/engine";

const T0 = 1_000_000;
const ON: RoomFeatures = { streaks: false, link: true };

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n,
});

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

let clock = T0;

beforeEach(() => {
  clock = T0;
});

/** jd in seat 0, mia in seat 1, both connected; seat 1 plays first. */
function started(features: RoomFeatures = ON, bots = 0): RoomCore {
  const room = new RoomCore(RoomCore.create("BCDFG", "jd", clock), () => clock, () => 0.25, catTower, 1, features);
  room.connect("jd");
  room.connect("mia");
  room.handle("jd", { t: "claim", seat: 0, person: person(1) });
  room.handle("mia", { t: "claim", seat: 1, person: person(2) });
  for (let i = 0; i < bots; i++) room.handle("jd", { t: "configure", seat: 2 + i, kind: "bot" });
  room.handle("jd", { t: "start" });
  return room;
}

/** The `{t:"link"}` messages in `out`, by device. */
function links(out: Outbound[]): Record<string, (SeatLink | null)[]> {
  return Object.fromEntries(out.flatMap((o) => (o.message.t === "link" ? [[o.to, o.message.seats]] : [])));
}

function snapshotTo(out: Outbound[], to: string): Snapshot {
  const hit = out.find((o) => o.to === to && o.message.t === "snapshot");
  if (!hit) throw new Error(`no snapshot for ${to}`);
  return hit.message as Snapshot;
}

const game = (room: RoomCore): CatTowerState => room.state.gameState as CatTowerState;

describe("each seat's link", () => {
  it("snapshots say the server takes pings and move ids, with this device's acks", () => {
    const room = started();
    const snap = room.snapshotFor("mia");
    expect(snap.room.link).toEqual({ ping: LINK_PING_MS, acks: [] });
    expect(snap.room.seats.map((s) => s.link)).toEqual([undefined, undefined]);
    expect(room.snapshotFor("stranger").room.link).toEqual({ ping: LINK_PING_MS, acks: [] });
  });

  it("off, snapshots and ticks are as before", () => {
    const room = started({ streaks: false });
    expect(room.snapshotFor("mia").room.link).toBeUndefined();
    clock = T0 + LOST_AFTER_MS;
    expect(links(room.tick())).toEqual({});
    expect(room.snapshotFor("jd").room.seats[1]?.link).toBeUndefined();
    expect(links(room.handle("mia", { t: "link", state: "weak" }))).toEqual({});
  });

  it("a silent phone turns weak, then lost, for everyone; its next ping puts it right", () => {
    const room = started();
    clock = T0 + 3000;
    room.heard("jd", clock);
    expect(links(room.tick())).toEqual({});

    clock = T0 + WEAK_AFTER_MS;
    room.heard("jd", clock);
    expect(links(room.tick())).toEqual({ jd: [null, "weak"], mia: [null, "weak"] });
    expect(room.snapshotFor("jd").room.seats[1]?.link).toBe("weak");
    // No change, no message.
    expect(links(room.tick())).toEqual({});

    clock = T0 + LOST_AFTER_MS;
    room.heard("jd", clock);
    expect(links(room.tick())).toEqual({ jd: [null, "lost"], mia: [null, "lost"] });

    clock += 500;
    room.heard("jd", clock);
    room.heard("mia", clock);
    expect(links(room.tick())).toEqual({ jd: [null, null], mia: [null, null] });
  });

  it("any message counts as heard", () => {
    const room = started();
    clock = T0 + WEAK_AFTER_MS - 1;
    room.handle("mia", { t: "presence", state: "active" });
    room.handle("jd", { t: "presence", state: "active" });
    clock = T0 + WEAK_AFTER_MS + 1;
    expect(links(room.tick())).toEqual({});
  });

  it("a ping that reaches the room gets its pong", () => {
    const room = started();
    expect(room.handle("mia", { t: "ping" })).toEqual([{ to: "mia", message: { t: "pong" } }]);
  });

  it("takes the app's own report of a weak link", () => {
    const room = started();
    expect(links(room.handle("mia", { t: "link", state: "weak" }))).toEqual({ jd: [null, "weak"], mia: [null, "weak"] });
    expect(links(room.handle("mia", { t: "link", state: "weak" }))).toEqual({});
    expect(links(room.handle("mia", { t: "link", state: "good" }))).toEqual({ jd: [null, null], mia: [null, null] });
  });

  it("a socket that drops shows as lost for a minute, then the seat is just away", () => {
    const room = started();
    expect(links(room.disconnect("mia", false))).toEqual({ jd: [null, "lost"] });
    clock = T0 + DROPPED_FOR_MS - 1;
    room.heard("jd", clock);
    expect(links(room.tick())).toEqual({});
    clock = T0 + DROPPED_FOR_MS;
    room.heard("jd", clock);
    expect(links(room.tick())).toEqual({ jd: [null, null] });
  });

  it("coming back clears it, and the phone's own snapshot already says so", () => {
    const room = started();
    room.disconnect("mia", false);
    clock += 5000;
    const out = room.connect("mia");
    expect(links(out)).toEqual({ jd: [null, null] });
    expect(snapshotTo(out, "mia").room.seats[1]?.link).toBeUndefined();
  });

  it("a close the app asked for (leaving, the background) is no lost link", () => {
    const room = started();
    expect(links(room.disconnect("mia"))).toEqual({});
    expect(room.snapshotFor("jd").room.seats[1]?.link).toBeUndefined();
  });

  it("only while playing, only human seats; pings from gone devices are ignored", () => {
    const lobby = new RoomCore(RoomCore.create("BCDFG", "jd", clock), () => clock, () => 0.25, catTower, 1, ON);
    lobby.connect("jd");
    lobby.handle("jd", { t: "claim", seat: 0, person: person(1) });
    lobby.disconnect("jd", false);
    expect(lobby.snapshotFor("x").room.seats[0]?.link).toBeUndefined();

    const room = started(ON, 1);
    room.disconnect("mia");
    room.heard("mia", clock);
    clock = T0 + LOST_AFTER_MS;
    room.heard("jd", clock);
    expect(room.snapshotFor("jd").room.seats.map((s) => s.link)).toEqual([undefined, undefined, undefined]);
  });

  it("the alarm wakes for the next change while a game is on", () => {
    const room = started(ON);
    // The cleanup is a week away; the first link change is the silence turning weak.
    expect(room.nextAlarm()).toBe(T0 + WEAK_AFTER_MS);
    const off = started({ streaks: false });
    expect(off.nextAlarm()).toBe(off.state.timers.cleanupAt);
    const lobby = new RoomCore(RoomCore.create("BCDFG", "jd", clock), () => clock, () => 0.25, catTower, 1, ON);
    lobby.connect("jd");
    expect(lobby.nextAlarm()).toBe(lobby.state.timers.cleanupAt);
    room.disconnect("jd");
    room.disconnect("mia");
    // Nobody connected: nothing to watch but the presence decay.
    expect(room.nextAlarm()).toBe(T0 + 5 * 60_000);
  });
});

describe("move ids", () => {
  it("a move sent again is applied once; the answer is the snapshot that has it", () => {
    const room = started();
    const first = room.handle("mia", { t: "act", seat: 1, action: { type: "draw", from: "deck" }, id: "m-1" });
    expect(snapshotTo(first, "mia").room.link?.acks).toEqual(["m-1"]);
    expect(game(room).step).toBe("play");
    const deck = game(room).deck.length;

    const again = room.handle("mia", { t: "act", seat: 1, action: { type: "draw", from: "deck" }, id: "m-1" });
    expect(again).toEqual([{ to: "mia", message: room.snapshotFor("mia") }]);
    expect(game(room).deck.length).toBe(deck);
    // Other devices see none of this device's acks.
    expect(room.snapshotFor("jd").room.link?.acks).toEqual([]);
  });

  it("a refused move is not remembered, so it can be tried again", () => {
    const room = started();
    const out = room.handle("jd", { t: "act", seat: 0, action: { type: "draw", from: "deck" }, id: "early" });
    expect(out.some((o) => o.message.t === "error" && o.message.code === "not_your_turn")).toBe(true);
    expect(room.state.devices.jd?.acks).toBeUndefined();
  });

  it("keeps the last sixteen", () => {
    // One phone holding both seats plays 18 moves.
    const room = new RoomCore(RoomCore.create("BCDFG", "jd", clock), () => clock, () => 0.25, catTower, 1, ON);
    room.connect("jd");
    room.handle("jd", { t: "claim", seat: 0, person: person(1) });
    room.handle("jd", { t: "claim", seat: 1, person: person(2) });
    room.handle("jd", { t: "start" });
    const ids = Array.from({ length: 18 }, (_, i) => `m-${i}`);
    for (const id of ids) {
      const seat = game(room).turn;
      const action =
        game(room).step === "draw"
          ? ({ type: "draw", from: "deck" } as const)
          : ({ type: "discard", card: (game(room).hands[seat] as number[])[0] as number } as const);
      const out = room.handle("jd", { t: "act", seat, action, id });
      expect(out.some((o) => o.message.t === "error")).toBe(false);
    }
    expect(room.state.devices.jd?.acks).toEqual(ids.slice(2));
  });

  it("a seat held by a device the room has no record of still plays", () => {
    const room = started();
    (room.state.seats[1] as { deviceId?: string }).deviceId = "ghost";
    const out = room.handle("ghost", { t: "act", seat: 1, action: { type: "draw", from: "deck" }, id: "g" });
    expect(out.some((o) => o.message.t === "error")).toBe(false);
  });
});
