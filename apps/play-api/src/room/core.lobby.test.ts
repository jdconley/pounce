import { beforeEach, describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { PROTOCOL_VERSION, type Person, type ServerMessage } from "../protocol";
import { createRng } from "../rules/rng";

import { RoomCore, type Outbound } from "./core";
import { defaultRoomName } from "./names";


const MIN = 60_000;
const DAY = 24 * 60 * MIN;
const T0 = 1_000_000;

const person = (n: number): Person => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: `Cat ${n}`,
  cat: n % 8,
});

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

function snapshotOf(out: Outbound[], to: string): Snapshot {
  const hit = out.find((o) => o.to === to && o.message.t === "snapshot");
  if (!hit) throw new Error(`no snapshot for ${to}`);
  return hit.message as Snapshot;
}

function errorsOf(out: Outbound[]): { to: string; code: string }[] {
  return out.flatMap((o) =>
    o.message.t === "error" ? [{ to: o.to, code: o.message.code }] : [],
  );
}

let clock = T0;
let rngValues: number[] = [];
const rng = () => rngValues.shift() ?? 0.25;

function newRoom(host = "host"): RoomCore {
  const state = RoomCore.create("BCDFG", host, clock);
  return new RoomCore(state, () => clock, rng);
}

/** A room where "a" and "b" are connected and each holds a seat. */
function twoPlayerLobby(): RoomCore {
  const room = newRoom();
  room.connect("a");
  room.connect("b");
  room.handle("a", { t: "claim", seat: 0, person: person(1) });
  room.handle("b", { t: "claim", seat: 1, person: person(2) });
  return room;
}

beforeEach(() => {
  clock = T0;
  rngValues = [];
});

describe("RoomCore.create", () => {
  it("has seats 0-1 open and 2-5 closed, in the lobby", () => {
    const state = RoomCore.create("BCDFG", "host", T0);
    expect(state.code).toBe("BCDFG");
    expect(state.game).toBe("cat-tower");
    expect(state.hostDeviceId).toBe("host");
    expect(state.status).toBe("lobby");
    expect(state.seats.map((s) => s.kind)).toEqual([
      "open",
      "open",
      "closed",
      "closed",
      "closed",
      "closed",
    ]);
    expect(state.gameState).toBeNull();
    expect(state.seq).toBe(0);
    expect(state.lastActivity).toBe(T0);
    expect(state.devices).toEqual({});
    expect(state.moveCodes).toEqual({});
    expect(state.moveFailures).toEqual({});
    expect(state.timers).toEqual({ botAt: null, nextRoundAt: null, cleanupAt: T0 + 7 * DAY });
    expect(state.pushedForTurn).toBeNull();
    expect(state.turnSeq).toBe(0);
  });
});

describe("claim", () => {
  it("seats a device and sends every connected device its own snapshot", () => {
    const room = newRoom();
    room.connect("a");
    room.connect("b");
    const out = room.handle("a", { t: "claim", seat: 0, person: person(1) });

    expect(room.state.seats[0]).toEqual({ kind: "human", person: person(1), deviceId: "a" });
    expect(room.state.seq).toBe(1);
    expect(out.map((o) => o.to).sort()).toEqual(["a", "b"]);
    expect(snapshotOf(out, "a").room.seats[0]).toMatchObject({ kind: "human", yours: true });
    expect(snapshotOf(out, "b").room.seats[0]).toMatchObject({ kind: "human", yours: false });
    expect(snapshotOf(out, "a").seq).toBe(1);
  });

  it("does not send to disconnected devices", () => {
    const room = newRoom();
    room.connect("a");
    room.connect("b");
    room.disconnect("b");
    const out = room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(out.map((o) => o.to)).toEqual(["a"]);
  });

  it("lets one device claim a second seat for a local player", () => {
    const room = newRoom();
    room.connect("a");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "claim", seat: 1, person: person(2) });
    expect(room.controlledSeats("a")).toEqual([0, 1]);
    expect(room.controlledSeats("b")).toEqual([]);
  });

  it("rejects a taken seat with seat_taken and changes nothing", () => {
    const room = twoPlayerLobby();
    const before = structuredClone(room.state);
    const out = room.handle("b", { t: "claim", seat: 0, person: person(3) });
    expect(errorsOf(out)).toEqual([{ to: "b", code: "seat_taken" }]);
    expect(out).toHaveLength(1);
    expect(room.state).toEqual(before);
  });

  it("rejects a closed seat with seat_taken", () => {
    const room = newRoom();
    const out = room.handle("a", { t: "claim", seat: 2, person: person(1) });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "seat_taken" }]);
  });

  it("rejects the same Person.id seated twice with person_seated", () => {
    const room = newRoom();
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const out = room.handle("b", { t: "claim", seat: 1, person: person(1) });
    expect(errorsOf(out)).toEqual([{ to: "b", code: "person_seated" }]);
    expect(room.state.seats[1]!.kind).toBe("open");
  });

  it("rejects out-of-range and negative seats with bad_seat", () => {
    const room = newRoom();
    for (const seat of [6, 99, -1]) {
      const out = room.handle("a", { t: "claim", seat, person: person(1) });
      expect(errorsOf(out)).toEqual([{ to: "a", code: "bad_seat" }]);
    }
  });

  it("rejects claims once the game has started with not_lobby", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    const out = room.handle("c", { t: "claim", seat: 0, person: person(3) });
    expect(errorsOf(out)).toEqual([{ to: "c", code: "not_lobby" }]);
  });
});

describe("configure", () => {
  it("adds a house bot to an open seat", () => {
    const room = newRoom();
    room.connect("a");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const out = room.handle("a", { t: "configure", seat: 1, kind: "bot" });
    expect(room.state.seats[1]).toEqual({ kind: "bot", botLevel: "house" });
    expect(snapshotOf(out, "a").room.seats[1]).toEqual({
      kind: "bot",
      yours: false,
      presence: null,
    });
    expect(room.state.seq).toBe(2);
  });

  it("opens and closes non-human seats, clearing any bot", () => {
    const room = newRoom();
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "configure", seat: 2, kind: "bot" });
    room.handle("a", { t: "configure", seat: 2, kind: "open" });
    expect(room.state.seats[2]).toEqual({ kind: "open" });
    room.handle("a", { t: "configure", seat: 1, kind: "closed" });
    expect(room.state.seats[1]).toEqual({ kind: "closed" });
  });

  it("rejects a device that holds no seat with not_seated", () => {
    const room = newRoom();
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const before = structuredClone(room.state);
    const out = room.handle("stranger", { t: "configure", seat: 1, kind: "bot" });
    expect(errorsOf(out)).toEqual([{ to: "stranger", code: "not_seated" }]);
    expect(room.state).toEqual(before);
  });

  it("rejects configuring a human seat with seat_taken", () => {
    const room = twoPlayerLobby();
    const out = room.handle("a", { t: "configure", seat: 1, kind: "closed" });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "seat_taken" }]);
    expect(room.state.seats[1]!.kind).toBe("human");
  });

  it("rejects bad seats and non-lobby rooms", () => {
    const room = twoPlayerLobby();
    expect(errorsOf(room.handle("a", { t: "configure", seat: 6, kind: "bot" }))).toEqual([
      { to: "a", code: "bad_seat" },
    ]);
    room.handle("a", { t: "start" });
    expect(errorsOf(room.handle("a", { t: "configure", seat: 0, kind: "bot" }))).toEqual([
      { to: "a", code: "not_lobby" },
    ]);
  });
});

describe("start", () => {
  it("rejects with not_enough_players when fewer than 2 human/bot seats", () => {
    const room = newRoom();
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "configure", seat: 1, kind: "closed" });
    const out = room.handle("a", { t: "start" });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "not_enough_players" }]);
    expect(room.state.status).toBe("lobby");
  });

  it("rejects with seats_open while any seat is open", () => {
    const room = newRoom();
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const out = room.handle("a", { t: "start" });
    expect(errorsOf(out)).toEqual([{ to: "a", code: "seats_open" }]);
  });

  it("rejects starting twice with not_lobby", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    expect(errorsOf(room.handle("a", { t: "start" }))).toEqual([{ to: "a", code: "not_lobby" }]);
  });

  it("compacts seats, deals with a seed from the rng and sends per-device snapshots", () => {
    const room = newRoom();
    room.connect("a");
    room.connect("b");
    // Seats: 0 human a, 1 closed, 2 bot, 3 human b (local to nobody else), 4-5 closed.
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "configure", seat: 1, kind: "closed" });
    room.handle("a", { t: "configure", seat: 2, kind: "bot" });
    room.handle("b", { t: "claim", seat: 1, person: person(2) }); // closed -> rejected
    room.handle("a", { t: "configure", seat: 3, kind: "open" });
    room.handle("b", { t: "claim", seat: 3, person: person(2) });
    const seqBefore = room.state.seq;
    rngValues = [0.5];

    const out = room.handle("b", { t: "start" });

    expect(room.state.status).toBe("playing");
    expect(room.state.seats.map((s) => s.kind)).toEqual(["human", "bot", "human"]);
    expect(room.state.seats.map((s) => s.deviceId)).toEqual(["a", undefined, "b"]);
    expect(room.state.gameState!.seats).toBe(3);
    expect(room.state.seq).toBe(seqBefore + 1);
    const a = snapshotOf(out, "a");
    const b = snapshotOf(out, "b");
    expect(a.room.status).toBe("playing");
    expect(a.room.seats.map((s) => s.yours)).toEqual([true, false, false]);
    expect(b.room.seats.map((s) => s.yours)).toEqual([false, false, true]);
    expect(a.room.game).not.toBeNull();
    expect(JSON.stringify(a.room.game)).not.toEqual(JSON.stringify(b.room.game));
  });

  it("seeds the game with four uint32 words, each Math.floor(rng() * 2**32)", () => {
    const words = [0.5, 0.25, 1 / 2 ** 32, (2 ** 32 - 1) / 2 ** 32];
    const a = twoPlayerLobby();
    rngValues = [...words];
    a.handle("a", { t: "start" });
    expect(a.state.gameState!.seed).toEqual([2 ** 31, 2 ** 30, 1, 2 ** 32 - 1]);
    const b = twoPlayerLobby();
    rngValues = [...words];
    b.handle("b", { t: "start" });
    const c = twoPlayerLobby();
    rngValues = [...words.slice(0, 3), 0.9];
    c.handle("a", { t: "start" });
    expect(a.state.gameState).toEqual(b.state.gameState);
    expect(c.state.gameState!.seed[3]).not.toBe(a.state.gameState!.seed[3]);
    expect(a.state.gameState!.hands).not.toEqual(c.state.gameState!.hands);
  });

  it("rejects an unseated device with not_seated and changes nothing", () => {
    const room = twoPlayerLobby();
    const before = structuredClone(room.state);
    const out = room.handle("stranger", { t: "start" });
    expect(errorsOf(out)).toEqual([{ to: "stranger", code: "not_seated" }]);
    expect(out).toHaveLength(1);
    expect(room.state).toEqual(before);
    expect(room.state.seq).toBe(before.seq);
  });

  it("lets a seated non-creator start when the host never connected", () => {
    const room = newRoom("host-never-connects");
    room.connect("a");
    room.connect("b");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("b", { t: "claim", seat: 1, person: person(2) });
    const out = room.handle("b", { t: "start" });
    expect(errorsOf(out)).toEqual([]);
    expect(room.state.status).toBe("playing");
    expect(snapshotOf(out, "b").room.youAreHost).toBe(false);
  });
});

describe("leave", () => {
  it("frees a seat the device holds", () => {
    const room = twoPlayerLobby();
    room.connect("c");
    const out = room.handle("a", { t: "leave", seat: 0 });
    expect(room.state.seats[0]).toEqual({ kind: "open" });
    expect(snapshotOf(out, "c").room.seats[0]!.kind).toBe("open");
  });

  it("rejects leaving a seat the device does not hold with not_your_seat", () => {
    const room = twoPlayerLobby();
    expect(errorsOf(room.handle("a", { t: "leave", seat: 1 }))).toEqual([
      { to: "a", code: "not_your_seat" },
    ]);
    room.handle("a", { t: "configure", seat: 2, kind: "bot" });
    expect(errorsOf(room.handle("a", { t: "leave", seat: 2 }))).toEqual([
      { to: "a", code: "not_your_seat" },
    ]);
    expect(errorsOf(room.handle("a", { t: "leave", seat: 7 }))).toEqual([
      { to: "a", code: "bad_seat" },
    ]);
  });

  it("is not allowed once the game has started", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    expect(errorsOf(room.handle("a", { t: "leave", seat: 0 }))).toEqual([
      { to: "a", code: "in_game" },
    ]);
    expect(room.state.seats[0]!.kind).toBe("human");
  });

  it("invalidates a move code for the freed seat", () => {
    const room = twoPlayerLobby();
    room.connect("c");
    const code = (room.handle("a", { t: "moveSeat", seat: 0 })[0]!.message as { code: string }).code;
    room.handle("a", { t: "leave", seat: 0 });
    room.handle("c", { t: "claim", seat: 0, person: person(3) });
    const out = room.handle("d", { t: "claimMove", code });
    expect(errorsOf(out)).toEqual([{ to: "d", code: "bad_code" }]);
    expect(room.state.seats[0]!.deviceId).toBe("c");
  });
});

describe("renameSeat", () => {
  it("renames the person in your seat and sends everyone a snapshot", () => {
    const room = twoPlayerLobby();
    const seq = room.state.seq;
    const out = room.handle("a", { t: "renameSeat", seat: 0, name: "Jo" });
    expect(room.state.seats[0]?.person).toEqual({ ...person(1), name: "Jo" });
    expect(room.state.seq).toBe(seq + 1);
    expect(out.map((o) => o.to).sort()).toEqual(["a", "b"]);
    expect(snapshotOf(out, "b").room.seats[0]?.person?.name).toBe("Jo");
  });

  it("works mid-game, keeping the seat's person id and cat", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    const out = room.handle("b", { t: "renameSeat", seat: 1, name: "Bea" });
    expect(room.state.seats[1]?.person).toEqual({ id: person(2).id, name: "Bea", cat: person(2).cat });
    expect(snapshotOf(out, "a").room.seats[1]?.person?.name).toBe("Bea");
    expect(snapshotOf(out, "a").room.game).not.toBeNull();
  });

  it("changes nothing and sends nothing when the name is the same", () => {
    const room = twoPlayerLobby();
    const before = structuredClone(room.state);
    expect(room.handle("a", { t: "renameSeat", seat: 0, name: person(1).name })).toEqual([]);
    expect(room.state).toEqual(before);
  });

  it("rejects another device's seat, an empty seat, a bad seat and a finished room", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "configure", seat: 2, kind: "bot" });
    const before = structuredClone(room.state);
    expect(errorsOf(room.handle("a", { t: "renameSeat", seat: 1, name: "X" }))).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(errorsOf(room.handle("a", { t: "renameSeat", seat: 2, name: "X" }))).toEqual([{ to: "a", code: "not_your_seat" }]);
    expect(errorsOf(room.handle("a", { t: "renameSeat", seat: 6, name: "X" }))).toEqual([{ to: "a", code: "bad_seat" }]);
    expect(room.state).toEqual(before);
    room.state.status = "over";
    expect(errorsOf(room.handle("a", { t: "renameSeat", seat: 0, name: "X" }))).toEqual([{ to: "a", code: "game_over" }]);
  });
});

describe("moveSeat and claimMove", () => {
  function moveCodeFor(room: RoomCore, device: string, seat: number): string {
    const out = room.handle(device, { t: "moveSeat", seat });
    const msg = out[0]!.message;
    if (msg.t !== "moveCode") throw new Error(`expected moveCode, got ${JSON.stringify(msg)}`);
    return msg.code;
  }

  it("returns a 6-char code to the sender only, valid 10 minutes", () => {
    const room = twoPlayerLobby();
    const seq = room.state.seq;
    const out = room.handle("a", { t: "moveSeat", seat: 0 });
    expect(out).toHaveLength(1);
    expect(out[0]!.to).toBe("a");
    expect(out[0]!.message).toMatchObject({ t: "moveCode", seat: 0 });
    const code = (out[0]!.message as { code: string }).code;
    expect(code).toHaveLength(6);
    expect(room.state.moveCodes[code]).toEqual({ seat: 0, expires: T0 + 10 * MIN });
    expect(room.state.seq).toBe(seq);
  });

  it("transfers the seat to the claiming device and consumes the code", () => {
    const room = twoPlayerLobby();
    room.connect("c");
    const code = moveCodeFor(room, "a", 0);
    const out = room.handle("c", { t: "claimMove", code });

    expect(room.state.seats[0]!.deviceId).toBe("c");
    expect(room.state.seats[0]!.person).toEqual(person(1));
    expect(room.state.moveCodes[code]).toBeUndefined();
    expect(room.controlledSeats("a")).toEqual([]);
    expect(room.controlledSeats("c")).toEqual([0]);
    expect(snapshotOf(out, "c").room.seats[0]!.yours).toBe(true);
    expect(snapshotOf(out, "a").room.seats[0]!.yours).toBe(false);
    // A used code cannot be replayed.
    expect(errorsOf(room.handle("b", { t: "claimMove", code }))).toEqual([
      { to: "b", code: "bad_code" },
    ]);
  });

  it("works while the game is playing and follows compaction", () => {
    const room = newRoom();
    room.connect("a");
    room.connect("c");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.handle("a", { t: "configure", seat: 1, kind: "closed" });
    room.handle("a", { t: "configure", seat: 2, kind: "open" });
    room.handle("a", { t: "claim", seat: 2, person: person(2) });
    const code = moveCodeFor(room, "a", 2);
    room.handle("a", { t: "start" });
    expect(room.state.seats).toHaveLength(2);
    expect(room.state.moveCodes[code]!.seat).toBe(1);

    const out = room.handle("c", { t: "claimMove", code });
    expect(errorsOf(out)).toEqual([]);
    expect(room.controlledSeats("c")).toEqual([1]);
    expect(snapshotOf(out, "c").room.game).not.toBeNull();
    expect(moveCodeFor(room, "c", 1)).toHaveLength(6);
  });

  it("rejects moveSeat for a seat the device does not control, or out of range", () => {
    const room = twoPlayerLobby();
    expect(errorsOf(room.handle("a", { t: "moveSeat", seat: 1 }))).toEqual([
      { to: "a", code: "not_your_seat" },
    ]);
    expect(errorsOf(room.handle("a", { t: "moveSeat", seat: 2 }))).toEqual([
      { to: "a", code: "not_your_seat" },
    ]);
    expect(errorsOf(room.handle("a", { t: "moveSeat", seat: 6 }))).toEqual([
      { to: "a", code: "bad_seat" },
    ]);
  });

  it("rejects an expired code with bad_code", () => {
    const room = twoPlayerLobby();
    const code = moveCodeFor(room, "a", 0);
    clock = T0 + 10 * MIN;
    expect(errorsOf(room.handle("c", { t: "claimMove", code }))).toEqual([
      { to: "c", code: "bad_code" },
    ]);
    expect(room.state.seats[0]!.deviceId).toBe("a");
    expect(room.state.moveCodes[code]).toBeUndefined();
  });

  it("accepts a code one millisecond before it expires", () => {
    const room = twoPlayerLobby();
    const code = moveCodeFor(room, "a", 0);
    clock = T0 + 10 * MIN - 1;
    expect(errorsOf(room.handle("c", { t: "claimMove", code }))).toEqual([]);
  });

  it("rejects an unknown code with bad_code", () => {
    const room = twoPlayerLobby();
    expect(errorsOf(room.handle("c", { t: "claimMove", code: "BBBBBB" }))).toEqual([
      { to: "c", code: "bad_code" },
    ]);
  });

  it("rate-limits a device after 5 failed attempts in 10 minutes", () => {
    const room = twoPlayerLobby();
    const code = moveCodeFor(room, "a", 0);
    for (let i = 0; i < 5; i++) {
      expect(errorsOf(room.handle("c", { t: "claimMove", code: "BBBBBB" }))).toEqual([
        { to: "c", code: "bad_code" },
      ]);
    }
    // Even the right code is refused now.
    expect(errorsOf(room.handle("c", { t: "claimMove", code }))).toEqual([
      { to: "c", code: "too_many_attempts" },
    ]);
    expect(room.state.seats[0]!.deviceId).toBe("a");
    // Other devices are unaffected.
    expect(errorsOf(room.handle("d", { t: "claimMove", code }))).toEqual([]);
  });

  it("counts failures per device and allows attempts again after the window passes", () => {
    const room = twoPlayerLobby();
    for (let i = 0; i < 4; i++) room.handle("c", { t: "claimMove", code: "BBBBBB" });
    expect(room.state.moveFailures["c"]).toEqual({ count: 4, windowStart: T0 });
    clock = T0 + 5 * MIN;
    room.handle("c", { t: "claimMove", code: "BBBBBB" });
    expect(room.state.moveFailures["c"]).toEqual({ count: 5, windowStart: T0 });
    expect(errorsOf(room.handle("c", { t: "claimMove", code: "BBBBBB" }))).toEqual([
      { to: "c", code: "too_many_attempts" },
    ]);

    clock = T0 + 10 * MIN;
    const code = moveCodeFor(room, "a", 0);
    expect(errorsOf(room.handle("c", { t: "claimMove", code: "CCCCCC" }))).toEqual([
      { to: "c", code: "bad_code" },
    ]);
    expect(room.state.moveFailures["c"]).toEqual({ count: 1, windowStart: T0 + 10 * MIN });
    expect(errorsOf(room.handle("c", { t: "claimMove", code }))).toEqual([]);
  });

  it("does not bump seq for a failed claim or a code request", () => {
    const room = twoPlayerLobby();
    const seq = room.state.seq;
    room.handle("c", { t: "claimMove", code: "BBBBBB" });
    room.handle("a", { t: "moveSeat", seat: 0 });
    expect(room.state.seq).toBe(seq);
  });

  it("refuses claimMove once the game is over", () => {
    const room = twoPlayerLobby();
    const code = moveCodeFor(room, "a", 0);
    room.handle("a", { t: "start" });
    room.state.status = "over";
    expect(errorsOf(room.handle("c", { t: "claimMove", code }))).toEqual([
      { to: "c", code: "game_over" },
    ]);
  });

  it("replaces an earlier code for the same seat and prunes expired codes", () => {
    const room = twoPlayerLobby();
    rngValues = [0, 0, 0, 0, 0, 0];
    const first = moveCodeFor(room, "a", 0);
    expect(first).toBe("BBBBBB");
    const second = moveCodeFor(room, "a", 0);
    expect(second).not.toBe(first);
    expect(Object.keys(room.state.moveCodes)).toEqual([second]);

    clock = T0 + 11 * MIN;
    const third = moveCodeFor(room, "b", 1);
    expect(Object.keys(room.state.moveCodes)).toEqual([third]);
  });

  it("never issues a code that is already live for another seat", () => {
    const room = twoPlayerLobby();
    rngValues = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];
    expect(moveCodeFor(room, "a", 0)).toBe("BBBBBB");
    const second = moveCodeFor(room, "b", 1);
    expect(second).not.toBe("BBBBBB");
    expect(Object.keys(room.state.moveCodes).sort()).toEqual(["BBBBBB", second].sort());
  });

  it("uses an injected crypto-style rng for codes", () => {
    const state = RoomCore.create("BCDFG", "host", T0);
    const room = new RoomCore(state, () => T0, createRng(seedOf(5)));
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const out = room.handle("a", { t: "moveSeat", seat: 0 });
    expect((out[0]!.message as { code: string }).code).toMatch(/^[BCDFGHJKLMNPQRTVWXZ2346789]{6}$/);
  });
});

describe("snapshotFor", () => {
  it("carries the protocol version so a client can check compatibility", () => {
    const room = twoPlayerLobby();
    expect(Object.keys(room.snapshotFor("a"))).toEqual(["t", "protocol", "seq", "room"]);
    expect(room.snapshotFor("a").protocol).toBe(PROTOCOL_VERSION);
    room.handle("a", { t: "start" });
    expect(room.snapshotFor("b").protocol).toBe(1);
  });

  it("marks yours only on the device's own seats and host only for the host", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "claim", seat: 2, person: person(3) }); // closed: rejected
    room.handle("a", { t: "configure", seat: 2, kind: "open" });
    room.handle("a", { t: "claim", seat: 2, person: person(3) });

    const a = room.snapshotFor("a") as Snapshot;
    expect(a.t).toBe("snapshot");
    expect(a.seq).toBe(room.state.seq);
    expect(a.room.code).toBe("BCDFG");
    expect(a.room.status).toBe("lobby");
    expect(a.room.game).toBeNull();
    expect(a.room.youAreHost).toBe(false);
    expect(a.room.seats.map((s) => s.yours)).toEqual([true, false, true, false, false, false]);

    const b = room.snapshotFor("b") as Snapshot;
    expect(b.room.seats.map((s) => s.yours)).toEqual([false, true, false, false, false, false]);

    expect((room.snapshotFor("host") as Snapshot).room.youAreHost).toBe(true);
    expect((room.snapshotFor("stranger") as Snapshot).room.seats.some((s) => s.yours)).toBe(false);
  });

  it("includes person for humans and the holder's presence", () => {
    const room = twoPlayerLobby();
    room.disconnect("b");
    const snap = room.snapshotFor("a") as Snapshot;
    expect(snap.room.seats[0]).toEqual({
      kind: "human",
      person: person(1),
      yours: true,
      presence: "awake",
    });
    expect(snap.room.seats[1]).toMatchObject({ presence: "away", person: person(2) });
    expect(snap.room.seats[2]).toEqual({ kind: "closed", yours: false, presence: null });
  });

  it("reports away presence for a holder that never connected", () => {
    const room = newRoom();
    room.handle("ghost", { t: "claim", seat: 0, person: person(1) });
    expect((room.snapshotFor("x") as Snapshot).room.seats[0]!.presence).toBe("away");
  });

  it("shows each device only the hands it controls once playing", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    const a = room.snapshotFor("a") as Snapshot;
    const b = room.snapshotFor("b") as Snapshot;
    const watcher = room.snapshotFor("watcher") as Snapshot;
    expect(a.room.game).not.toBeNull();
    expect(a.room.game).not.toEqual(b.room.game);
    expect(JSON.stringify(watcher.room.game)).not.toEqual(JSON.stringify(a.room.game));
    expect(room.controlledSeats("a")).toEqual([0]);
  });
});

describe("connect and disconnect", () => {
  it("connect records an awake connected device and returns its snapshot", () => {
    clock = T0 + 5;
    const room = newRoom();
    const out = room.connect("a");
    expect(room.state.devices["a"]).toEqual({ presence: "awake", since: T0 + 5, connected: true });
    expect(out).toHaveLength(1);
    expect(out[0]!.to).toBe("a");
    expect(out[0]!.message).toEqual(room.snapshotFor("a"));
    expect(room.state.seq).toBe(0);
  });

  it("disconnect marks the device away and not connected; unknown devices are ignored", () => {
    const room = newRoom();
    room.connect("a");
    clock = T0 + 9;
    expect(room.disconnect("a")).toEqual([]);
    expect(room.state.devices["a"]).toMatchObject({ presence: "away", connected: false });
    expect(room.disconnect("never-seen")).toEqual([]);
    expect(room.state.devices["never-seen"]).toBeUndefined();
  });
});

describe("timers in the lobby", () => {
  it("tick does nothing and nextAlarm is the earliest non-null timer", () => {
    const room = newRoom();
    expect(room.tick()).toEqual([]);
    expect(room.nextAlarm()).toBe(T0 + 7 * DAY);
    room.state.timers.nextRoundAt = T0 + 50;
    expect(room.nextAlarm()).toBe(T0 + 50);
    room.state.timers.botAt = T0 + 10;
    expect(room.nextAlarm()).toBe(T0 + 10);
  });
});

describe("handle robustness", () => {
  it("maps an unexpected exception to error internal instead of throwing", () => {
    const state = RoomCore.create("BCDFG", "host", T0);
    const room = new RoomCore(state, () => T0, () => {
      throw new Error("entropy failure");
    });
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    const out = room.handle("a", { t: "moveSeat", seat: 0 });
    expect(out).toEqual([{ to: "a", message: { t: "error", code: "internal" } }]);
    expect(room.state.moveCodes).toEqual({});
  });

  it("advances seq once per state-changing message and refreshes activity timers", () => {
    const room = newRoom();
    room.connect("a");
    clock = T0 + DAY;
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(room.state.seq).toBe(1);
    expect(room.state.lastActivity).toBe(T0 + DAY);
    expect(room.state.timers.cleanupAt).toBe(T0 + 8 * DAY);
    room.handle("a", { t: "claim", seat: 0, person: person(2) }); // rejected
    expect(room.state.seq).toBe(1);
    expect(room.state.lastActivity).toBe(T0 + DAY);
  });
});

describe("table name", () => {
  it("defaults to the code's name, or takes the one given at creation", () => {
    expect(newRoom().state.name).toBe(defaultRoomName("BCDFG"));
    expect(RoomCore.create("BCDFG", "host", T0, "Taco Night").name).toBe("Taco Night");
    expect(snapshotOf(twoPlayerLobby().connect("a"), "a").room.name).toBe(defaultRoomName("BCDFG"));
  });

  it("fills in the default for a room saved before tables had names", () => {
    const state = RoomCore.create("BCDFG", "host", T0);
    delete (state as Partial<typeof state>).name;
    const room = new RoomCore(state, () => clock, rng);
    expect(room.state.name).toBe(defaultRoomName("BCDFG"));
  });

  it("a seated phone renames it: every connected phone gets a snapshot with the new name", () => {
    const room = twoPlayerLobby();
    const seq = room.state.seq;
    const out = room.handle("b", { t: "rename", name: "Taco Night" });
    expect(snapshotOf(out, "a").room.name).toBe("Taco Night");
    expect(snapshotOf(out, "b").room.name).toBe("Taco Night");
    expect(room.state.seq).toBe(seq + 1);
  });

  it("the host may rename before sitting down; a seatless guest may not", () => {
    const room = newRoom("host");
    room.connect("host");
    room.connect("guest");
    expect(errorsOf(room.handle("guest", { t: "rename", name: "Mine" }))).toEqual([
      { to: "guest", code: "not_seated" },
    ]);
    expect(snapshotOf(room.handle("host", { t: "rename", name: "Taco Night" }), "guest").room.name).toBe(
      "Taco Night",
    );
  });

  it("works mid-game, but not once the game is over", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "start" });
    expect(snapshotOf(room.handle("a", { t: "rename", name: "Round Two" }), "b").room.name).toBe("Round Two");
    room.state.status = "over";
    expect(errorsOf(room.handle("a", { t: "rename", name: "Too Late" }))).toEqual([
      { to: "a", code: "game_over" },
    ]);
    expect(room.state.name).toBe("Round Two");
  });

  it("the same name again changes nothing and sends nothing", () => {
    const room = twoPlayerLobby();
    room.handle("a", { t: "rename", name: "Taco Night" });
    const seq = room.state.seq;
    expect(room.handle("b", { t: "rename", name: "Taco Night" })).toEqual([]);
    expect(room.state.seq).toBe(seq);
  });
});
