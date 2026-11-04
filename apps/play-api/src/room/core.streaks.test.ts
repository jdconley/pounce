import { beforeEach, describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { card } from "../rules/cards";

import { RoomCore, type CatTowerModule, type Outbound, type RoomState } from "./core";

import type { Person } from "../protocol";
import type { CatTowerState } from "../rules/engine";

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

let clock = T0;
const rng = () => 0.25;

beforeEach(() => {
  clock = T0;
});

const errorsOf = (out: Outbound[]) => out.flatMap((o) => (o.message.t === "error" ? [o.message.code] : []));
const game = (room: RoomCore) => room.state.gameState as CatTowerState;

function room(streaks: boolean, module: CatTowerModule = catTower, state?: RoomState): RoomCore {
  return new RoomCore(state ?? RoomCore.create("BCDFG", "phone", clock), () => clock, rng, module, 1, { streaks });
}

/** Seat 0 is person 1 (player A) on the phone, seat 1 person 2 (player B) on the tablet, then `bots` bots. */
function started(streaks = true, bots = 0, module: CatTowerModule = catTower): RoomCore {
  const r = room(streaks, module);
  r.connect("phone", { [P1]: A });
  r.connect("tablet", { [P2]: B });
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  for (let seat = 2; seat < 2 + bots; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  for (let seat = 2 + bots; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  expect(errorsOf(r.handle("phone", { t: "start" }))).toEqual([]);
  return r;
}

const deviceOf = (seat: number) => (seat === 0 ? "phone" : "tablet");

/** The seat to act draws from the deck and discards a number card. */
function takeTurn(r: RoomCore): void {
  const seat = game(r).turn;
  r.handle(deviceOf(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
  const hand = game(r).hands[seat] as number[];
  const pick = hand.find((id) => card(id).kind === "number") as number;
  expect(errorsOf(r.handle(deviceOf(seat), { t: "act", seat, action: { type: "discard", card: pick } }))).toEqual([]);
}

describe("with streaks off", () => {
  it("rejects rematch and setLook, adds nothing to snapshots and queues no reports", () => {
    const r = started(false);
    expect(errorsOf(r.handle("phone", { t: "rematch" }))).toEqual(["bad_message"]);
    expect(errorsOf(r.handle("phone", { t: "setLook", rug: "rug-classic" }))).toEqual(["bad_message"]);
    takeTurn(r);
    expect(r.drainStreakIntents()).toEqual([]);
    const snap = r.snapshotFor("phone");
    expect(snap.room).not.toHaveProperty("look");
    expect(snap.room).not.toHaveProperty("rematch");
  });
});

describe("streak reports", () => {
  it("report the deal, then each human turn and where the move went", () => {
    const r = started();
    const first = game(r).turn;
    const holderOf = (seat: number) => (seat === 0 ? A : B);
    expect(r.drainStreakIntents()).toEqual([
      { code: "BCDFG", at: T0, by: null, holder: holderOf(first), players: [A, B], turnedAt: {}, over: false },
    ]);
    clock += 1000;
    takeTurn(r);
    expect(r.drainStreakIntents()).toEqual([
      {
        code: "BCDFG",
        at: T0 + 1000,
        by: holderOf(first),
        holder: holderOf(1 - first),
        players: [A, B],
        turnedAt: { [holderOf(first)]: T0 + 1000 },
        over: false,
      },
    ]);
  });

  it("say nothing for a draw alone", () => {
    const r = started();
    r.drainStreakIntents();
    const seat = game(r).turn;
    r.handle(deviceOf(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
    expect(r.drainStreakIntents()).toEqual([]);
  });

  it("report a bot's turn with nobody as the mover", () => {
    const r = started(true, 1);
    r.drainStreakIntents();
    for (let i = 0; i < 10 && game(r).turn !== 2; i++) takeTurn(r);
    r.drainStreakIntents();
    let intents = r.drainStreakIntents();
    for (let i = 0; i < 5 && intents.length === 0; i++) {
      clock = r.state.timers.botAt as number;
      r.tick();
      intents = r.drainStreakIntents();
    }
    expect(intents).toEqual([expect.objectContaining({ by: null, holder: [A, B][game(r).turn] })]);
  });

  it("report the end of the game", () => {
    const over: CatTowerModule = {
      ...catTower,
      apply: (s) => ({ ok: true, state: { ...s, status: "gameOver" }, events: [{ kind: "gameOver", winners: [0] }] }),
    };
    const r = started(true, 0, over);
    r.drainStreakIntents();
    const seat = game(r).turn;
    r.handle(deviceOf(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
    expect(r.drainStreakIntents()).toEqual([expect.objectContaining({ by: null, holder: null, over: true })]);
  });

  it("report a table closed for inactivity", () => {
    const r = started();
    r.drainStreakIntents();
    clock = r.state.timers.cleanupAt;
    r.tick();
    expect(r.drainStreakIntents()).toEqual([expect.objectContaining({ over: true, players: [A, B] })]);
  });

  it("report a lobby closed for inactivity as over", () => {
    const r = room(true);
    clock = r.state.timers.cleanupAt;
    r.tick();
    expect(r.drainStreakIntents()).toEqual([expect.objectContaining({ holder: null, over: true, players: [] })]);
  });

  it("list a player in two seats once", () => {
    const r = started();
    r.adopt({ from: B, to: A });
    r.drainStreakIntents();
    takeTurn(r);
    expect(r.drainStreakIntents()[0]?.players).toEqual([A]);
  });

  it("don't name a seat without a player as the mover", () => {
    const r = room(true);
    r.connect("phone");
    r.connect("tablet");
    r.handle("phone", { t: "claim", seat: 0, person: person(1) });
    r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
    r.handle("phone", { t: "start" });
    r.drainStreakIntents();
    takeTurn(r);
    expect(r.drainStreakIntents()[0]).toMatchObject({ by: null, holder: null, players: [] });
  });
});

describe("table looks", () => {
  const unlocks = { backs: ["back-violet-paw", "back-crown"], rugs: ["rug-classic", "rug-night-sky"] };

  it("start with the defaults, or the look the room was made with", () => {
    expect(started().snapshotFor("phone").room.look).toEqual({ rug: "rug-classic", back: "back-violet-paw" });
    const made = room(true, catTower, RoomCore.create("BCDFG", "phone", T0, undefined, { rug: "rug-fish-pond", back: "back-crown" }));
    expect(made.snapshotFor("phone").room.look).toEqual({ rug: "rug-fish-pond", back: "back-crown" });
  });

  it("change for everyone when anyone seated picks one they've unlocked", () => {
    const r = started();
    const out = r.handle("tablet", { t: "setLook", rug: "rug-night-sky" }, unlocks);
    const looks = out.flatMap((o) => (o.message.t === "event" && o.message.event.kind === "look" ? [[o.to, o.message.event]] : []));
    expect(looks).toEqual([
      ["phone", { kind: "look", seat: 1, rug: "rug-night-sky", back: "back-violet-paw" }],
      ["tablet", { kind: "look", seat: 1, rug: "rug-night-sky", back: "back-violet-paw" }],
    ]);
    expect(r.snapshotFor("phone").room.look).toEqual({ rug: "rug-night-sky", back: "back-violet-paw" });
    clock += 10_000;
    r.handle("phone", { t: "setLook", back: "back-crown" }, unlocks);
    expect(r.state.look).toEqual({ rug: "rug-night-sky", back: "back-crown" });
  });

  it("allow the defaults without any unlocks", () => {
    const r = started();
    expect(errorsOf(r.handle("phone", { t: "setLook", rug: "rug-classic", back: "back-violet-paw" }))).toEqual([]);
  });

  it("refuse what the setter hasn't unlocked", () => {
    const r = started();
    expect(errorsOf(r.handle("phone", { t: "setLook", rug: "rug-fish-pond" }, unlocks))).toEqual(["not_unlocked"]);
    expect(errorsOf(r.handle("phone", { t: "setLook", back: "back-heart-paws" }, unlocks))).toEqual(["not_unlocked"]);
    expect(r.state.look).toBeUndefined();
  });

  it("change at most once every 10 seconds per phone", () => {
    const r = started();
    r.handle("phone", { t: "setLook", rug: "rug-night-sky" }, unlocks);
    clock += 9_999;
    expect(errorsOf(r.handle("phone", { t: "setLook", rug: "rug-classic" }, unlocks))).toEqual(["too_soon"]);
    expect(errorsOf(r.handle("tablet", { t: "setLook", rug: "rug-classic" }, unlocks))).toEqual([]);
  });

  it("only from someone seated", () => {
    const r = started();
    r.connect("watcher");
    expect(errorsOf(r.handle("watcher", { t: "setLook", rug: "rug-classic" }))).toEqual(["not_seated"]);
  });

  it("are checked against the players of the setter's seats", () => {
    const r = started();
    expect(r.lookPlayers("phone")).toEqual([A]);
    r.connect("watcher");
    expect(r.lookPlayers("watcher")).toEqual([]);
    const legacy = room(true);
    legacy.connect("old");
    legacy.handle("old", { t: "claim", seat: 0, person: person(1) });
    expect(legacy.lookPlayers("old")).toEqual([]);
  });
});

describe("play again", () => {
  function finished(): RoomCore {
    const r = started(true, 1);
    r.handle("phone", { t: "setLook", rug: "rug-night-sky" }, { backs: [], rugs: ["rug-night-sky"] });
    r.state.status = "over";
    return r;
  }

  it("waits for the game to be over, and someone seated", () => {
    const r = started();
    expect(errorsOf(r.handle("phone", { t: "rematch" }))).toEqual(["not_over"]);
    const f = finished();
    f.connect("watcher");
    expect(errorsOf(f.handle("watcher", { t: "rematch" }))).toEqual(["not_seated"]);
    expect(f.drainRematch()).toBeNull();
  });

  it("asks for a new table with the same people, name and look, the first seat rotated", () => {
    const r = finished();
    const seats = r.state.seats.map((s) => ({ ...s }));
    expect(r.handle("tablet", { t: "rematch" })).toEqual([]);
    expect(r.drainRematch()).toEqual({
      name: r.state.name,
      look: { rug: "rug-night-sky", back: "back-violet-paw" },
      seats: [seats[1], seats[2], seats[0]],
      hostDeviceId: "tablet",
    });
    expect(r.drainRematch()).toBeNull();
  });

  it("is accepted once: later requests wait, then get the new code", () => {
    const r = finished();
    r.handle("tablet", { t: "rematch" });
    r.drainRematch();
    expect(r.handle("phone", { t: "rematch" })).toEqual([]);
    expect(r.drainRematch()).toBeNull();
    const told = r.rematchDealt("NWCDE");
    expect(told).toEqual([{ to: "all", message: { t: "rematch", code: "NWCDE" } }]);
    expect(r.snapshotFor("phone").room.rematch).toBe("NWCDE");
    expect(r.handle("phone", { t: "rematch" })).toEqual([{ to: "phone", message: { t: "rematch", code: "NWCDE" } }]);
  });

  it("can be asked again when making the table failed", () => {
    const r = finished();
    r.handle("tablet", { t: "rematch" });
    r.drainRematch();
    r.rematchFailed();
    r.handle("phone", { t: "rematch" });
    expect(r.drainRematch()?.hostDeviceId).toBe("phone");
  });

  it("deals the new table at once", () => {
    const r = finished();
    r.handle("tablet", { t: "rematch" });
    const spec = r.drainRematch();
    if (!spec) throw new Error("no rematch");
    const next = room(true, catTower, RoomCore.rematchState("NWCDE", spec, clock));
    next.deal();
    expect(next.state.status).toBe("playing");
    expect(next.state.seats.map((s) => s.playerId ?? s.kind)).toEqual([B, "bot", A]);
    expect(next.state.look).toEqual(spec.look);
    expect(next.state.hostDeviceId).toBe("tablet");
    expect(next.drainStreakIntents()).toHaveLength(1);
    // The dealer is seat 0, so the first move is seat 1's: one on from last game's.
    expect(game(next).turn).toBe(1);
  });
});

describe("streak views reach the right sockets", () => {
  it("lists the connected devices and the person on each that speaks for a player", () => {
    const r = started();
    r.connect("ipad", { [P1]: A, [P2]: B });
    expect(r.devicesFor(A)).toEqual([
      { deviceId: "phone", personId: P1 },
      { deviceId: "ipad", personId: P1 },
    ]);
    r.disconnect("ipad");
    r.connect("legacy");
    expect(r.devicesFor(B)).toEqual([{ deviceId: "tablet", personId: P2 }]);
  });
});
