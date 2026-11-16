import { beforeEach, describe, expect, it } from "vitest";

import { PROTOCOL_VERSION, type ClientMessage, type Person, type ServerMessage } from "../protocol";

import { RoomCore, SCREEN_GRACE_MS, type Outbound } from "./core";

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

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [{ to: o.to, code: o.message.code }] : []));
const snapshotsTo = (out: Outbound[]) => out.filter((o) => o.message.t === "snapshot").map((o) => o.to);

let clock = T0;
const rng = () => 0.25;

function build(tv = true, screen?: string): RoomCore {
  const state = RoomCore.create("BCDFG", screen ? "" : "host", clock, undefined, undefined, undefined, screen);
  return new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv });
}

/** "a" and "b" are connected, each in a seat. */
function phones(room: RoomCore): void {
  room.connect("a");
  room.connect("b");
  room.handle("a", { t: "claim", seat: 0, person: person(1) });
  room.handle("b", { t: "claim", seat: 1, person: person(2) });
}

beforeEach(() => {
  clock = T0;
});

describe("a screen", () => {
  it("gets no hand and claims nothing", () => {
    const room = build();
    phones(room);
    room.handle("a", { t: "start" });
    const out = room.connect("tv", {}, "screen");
    expect(snapshotOf(out, "tv").room.game?.hands).toEqual({});
    const messages: ClientMessage[] = [
      { t: "claim", seat: 0, person: person(3) },
      { t: "moveSeat", seat: 0 },
      { t: "claimMove", code: "ABCDEF" },
      { t: "act", seat: 0, action: { type: "forfeit" } },
      { t: "aim", seat: 0 },
      { t: "configure", seat: 2, kind: "bot" },
      { t: "start" },
      { t: "leave", seat: 0 },
      { t: "rename", name: "New" },
      { t: "renameSeat", seat: 0, name: "New" },
      { t: "rematch" },
      { t: "setLook", rug: "rug-classic" },
      { t: "nudge", seat: 0 },
      { t: "retire", seat: 0 },
    ];
    for (const msg of messages) {
      expect(errorsOf(room.handle("tv", msg))).toEqual([{ to: "tv", code: "not_allowed" }]);
    }
  });

  it("may still ping, report presence and link", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    expect(room.handle("tv", { t: "ping" })).toEqual([{ to: "tv", message: { t: "pong" } }]);
    expect(errorsOf(room.handle("tv", { t: "presence", state: "active" }))).toEqual([]);
    expect(errorsOf(room.handle("tv", { t: "link", state: "weak" }))).toEqual([]);
  });

  it("has a table with no host until the first phone sits", () => {
    const room = build(true, "tv");
    expect(room.state.hostDeviceId).toBe("");
    expect(room.state.screens).toEqual(["tv"]);
    room.connect("tv");
    const a = room.connect("a");
    expect(snapshotOf(a, "a").room.youAreHost).toBe(false);
    room.connect("b");
    const out = room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(snapshotOf(out, "a").room.youAreHost).toBe(true);
    expect(snapshotOf(out, "tv").room.youAreHost).toBe(false);
    const next = room.handle("b", { t: "claim", seat: 1, person: person(2) });
    expect(snapshotOf(next, "b").room.youAreHost).toBe(false);
    expect(snapshotOf(next, "a").room.youAreHost).toBe(true);
  });

  it("shows while a screen is connected", () => {
    const room = build();
    phones(room);
    expect(snapshotOf(room.connect("c"), "c").room).not.toHaveProperty("screen");
    const seq = room.state.seq;
    const out = room.connect("tv", {}, "screen");
    for (const to of ["a", "b", "c", "tv"]) {
      const snap = snapshotOf(out, to);
      expect(snap.room.screen).toBe(true);
      expect(snap.seq).toBe(seq + 1);
      expect(snap.protocol).toBe(PROTOCOL_VERSION);
    }
  });

  it("coming back within the grace changes nothing for the phones", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    const seq = room.state.seq;
    clock += SCREEN_GRACE_MS - 1;
    const out = room.connect("tv");
    expect(snapshotsTo(out)).toEqual(["tv"]);
    expect(snapshotOf(out, "tv").room.screen).toBe(true);
    expect(room.state.screenLeftAt).toBeUndefined();
    expect(room.state.seq).toBe(seq);
    clock += SCREEN_GRACE_MS * 2;
    expect(room.tick()).toEqual([]);
  });

  it("goes after the grace", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    expect(room.nextAlarm()).toBe(clock + SCREEN_GRACE_MS);
    const activity = room.state.lastActivity;
    const seq = room.state.seq;
    // Still shown just before the grace ends.
    clock += SCREEN_GRACE_MS - 1;
    expect(snapshotOf(room.connect("c"), "c").room.screen).toBe(true);
    clock += 1;
    const out = room.tick();
    expect(snapshotsTo(out).sort()).toEqual(["a", "b", "c"]);
    for (const to of ["a", "b", "c"]) expect(snapshotOf(out, to).room).not.toHaveProperty("screen");
    expect(room.state.seq).toBe(seq + 1);
    expect(room.state.screenLeftAt).toBeUndefined();
    expect(room.state.lastActivity).toBe(activity);
    expect(room.tick()).toEqual([]);
  });

  it("stays while another screen is connected", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.connect("tv2", {}, "screen");
    room.disconnect("tv");
    expect(room.state.screenLeftAt).toBeUndefined();
    expect(snapshotOf(room.connect("c"), "c").room.screen).toBe(true);
  });

  it("a second close of the same screen doesn't restart the grace", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    const left = room.state.screenLeftAt;
    clock += 1_000;
    room.disconnect("tv");
    expect(room.state.screenLeftAt).toBe(left);
  });

  it("back after the grace but before the tick leaves no overdue alarm", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    clock += SCREEN_GRACE_MS;
    const out = room.connect("tv");
    expect(snapshotsTo(out).sort()).toEqual(["a", "b", "tv"]);
    expect(room.state.screenLeftAt).toBeUndefined();
    expect(room.nextAlarm()).toBeGreaterThan(clock);
    expect(room.tick()).toEqual([]);
  });

  it("speaks for nobody, whatever players it sends", () => {
    const room = build();
    const p1 = person(1).id;
    room.connect("a", { [p1]: "p_A" });
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    room.connect("b");
    room.handle("b", { t: "claim", seat: 1, person: person(2) });
    room.handle("a", { t: "start" });
    for (const role of ["screen" as const, undefined]) {
      const out = room.connect("tv", { [p1]: "p_A" }, role);
      expect(room.controlledSeats("tv")).toEqual([]);
      const snap = snapshotOf(out, "tv");
      expect(snap.room.game?.hands).toEqual({});
      expect(snap.room.seats.some((s) => s.yours)).toBe(false);
    }
  });

  it("the grace shrinks with the dev speed", () => {
    const state = RoomCore.create("BCDFG", "host", clock);
    const room = new RoomCore(state, () => clock, rng, undefined, 10, { streaks: true, tv: true });
    room.connect("a");
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    expect(room.nextAlarm()).toBe(clock + SCREEN_GRACE_MS / 10);
  });

  it("can't be a seated device or the host", () => {
    const room = build();
    phones(room);
    expect(room.mayScreen("a")).toBe(false);
    expect(room.mayScreen("tv")).toBe(true);
    const hosted = RoomCore.create("BCDFG", "host", clock);
    expect(new RoomCore(hosted, () => clock, rng).mayScreen("host")).toBe(false);
  });

  it("stays a screen without the role", () => {
    const room = build();
    phones(room);
    room.connect("tv", {}, "screen");
    room.disconnect("tv");
    room.connect("tv");
    expect(room.isScreen("tv")).toBe(true);
    expect(errorsOf(room.handle("tv", { t: "claim", seat: 2, person: person(3) }))).toEqual([
      { to: "tv", code: "not_allowed" },
    ]);
  });

  it("isn't a screen unless it said so", () => {
    const room = build();
    phones(room);
    expect(room.isScreen("a")).toBe(false);
    room.connect("tv", {}, "screen");
    room.connect("tv", {}, "screen");
    expect(room.state.screens).toEqual(["tv"]);
  });

  it("is listed by addScreen before it connects", () => {
    const room = build();
    phones(room);
    room.addScreen("tv");
    room.addScreen("tv");
    expect(room.state.screens).toEqual(["tv"]);
    expect(room.isScreen("tv")).toBe(true);
    const out = room.connect("tv");
    expect(snapshotOf(out, "tv").room.screen).toBe(true);
    expect(snapshotOf(out, "a").room.screen).toBe(true);
  });
});

describe("linking", () => {
  it("is for the host or a seated device, never a screen", () => {
    const state = RoomCore.create("BCDFG", "host", clock);
    const room = new RoomCore(state, () => clock, rng, undefined, 1, { streaks: true, tv: true });
    room.connect("a");
    room.connect("watcher");
    room.connect("tv", {}, "screen");
    room.handle("a", { t: "claim", seat: 0, person: person(1) });
    expect(room.mayLink("host")).toBe(true);
    expect(room.mayLink("a")).toBe(true);
    expect(room.mayLink("watcher")).toBe(false);
    expect(room.mayLink("tv")).toBe(false);
    room.state.hostDeviceId = "tv";
    expect(room.mayLink("tv")).toBe(false);
  });
});

describe("play again", () => {
  it("keeps the table's screens", () => {
    const room = build(true, "tv");
    room.connect("tv");
    phones(room);
    room.handle("a", { t: "start" });
    room.state.status = "over";
    expect(room.handle("a", { t: "rematch" })).toEqual([]);
    const intent = room.drainRematch();
    expect(intent?.screens).toEqual(["tv"]);
    const next = RoomCore.rematchState("NWCDE", intent as NonNullable<typeof intent>, clock);
    expect(next.screens).toEqual(["tv"]);
    expect(next.hostDeviceId).toBe("a");
  });

  it("adds nothing to a table with no screens", () => {
    const room = build();
    phones(room);
    room.handle("a", { t: "start" });
    room.state.status = "over";
    room.handle("a", { t: "rematch" });
    const intent = room.drainRematch() as NonNullable<ReturnType<RoomCore["drainRematch"]>>;
    expect(intent).not.toHaveProperty("screens");
    expect(RoomCore.rematchState("NWCDE", intent, clock)).not.toHaveProperty("screens");
  });
});

describe("without the TV feature", () => {
  it("nothing says screen", () => {
    const room = build(false);
    phones(room);
    const seq = room.state.seq;
    const out = room.connect("tv", {}, "screen");
    expect(snapshotsTo(out)).toEqual(["tv"]);
    expect(snapshotOf(out, "tv").room).not.toHaveProperty("screen");
    expect(room.state.seq).toBe(seq);
  });
});
