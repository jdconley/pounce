import { describe, expect, it } from "vitest";

import { catTower } from "../games/cat-tower";
import { card } from "../rules/cards";

import { RoomCore, type YourTurnIntent } from "./core";

import type { Person } from "../protocol";
import type { CatTowerState } from "../rules/engine";

const T0 = 1_000_000;
const A = "p_AAAAAAAAAAAAAAAAAAAAAA";
const B = "p_BBBBBBBBBBBBBBBBBBBBBB";
const person = (n: number): Person => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, name: `Cat ${n}`, cat: n % 8 });

function started(streaks: boolean, bots = 0): RoomCore {
  const r = new RoomCore(RoomCore.create("BCDFG", "phone", T0), () => T0, () => 0.25, catTower, 1, { streaks });
  r.connect("phone", { [person(1).id]: A });
  r.connect("tablet", { [person(2).id]: B });
  r.handle("phone", { t: "claim", seat: 0, person: person(1) });
  r.handle("tablet", { t: "claim", seat: 1, person: person(2) });
  for (let seat = 2; seat < 2 + bots; seat++) r.handle("phone", { t: "configure", seat, kind: "bot" });
  for (let seat = 2 + bots; seat < 6; seat++) r.handle("phone", { t: "configure", seat, kind: "closed" });
  r.handle("phone", { t: "start" });
  return r;
}

const deviceOf = (seat: number) => (seat === 0 ? "phone" : "tablet");

function takeTurn(r: RoomCore): void {
  const g = () => r.state.gameState as CatTowerState;
  const seat = g().turn;
  r.handle(deviceOf(seat), { t: "act", seat, action: { type: "draw", from: "deck" } });
  const pick = (g().hands[seat] as number[]).find((id) => card(id).kind === "number") as number;
  r.handle(deviceOf(seat), { t: "act", seat, action: { type: "discard", card: pick } });
}

const turnPushes = (r: RoomCore) => r.drainPushIntents().filter((i): i is YourTurnIntent => i.kind === "your_turn");

describe("who played (§12.2)", () => {
  it("with streaks on, your move names the human who just ended their turn", () => {
    const r = started(true);
    r.handle("phone", { t: "presence", state: "background" });
    r.handle("tablet", { t: "presence", state: "background" });
    r.drainPushIntents();
    const mover = (r.state.gameState as CatTowerState).turn;
    takeTurn(r);
    const [push] = turnPushes(r);
    expect(push?.from).toEqual({ name: person(mover + 1).name, cat: person(mover + 1).cat });
  });

  it("the deal names nobody, and with streaks off no push carries it", () => {
    const r = started(true);
    expect(r.drainPushIntents().every((i) => !("from" in i))).toBe(true);
    const off = started(false);
    off.handle("phone", { t: "presence", state: "background" });
    off.handle("tablet", { t: "presence", state: "background" });
    takeTurn(off);
    expect(turnPushes(off).every((i) => !("from" in i))).toBe(true);
  });

  it("a bot's turn names nobody", () => {
    const r = started(true, 1);
    r.handle("phone", { t: "presence", state: "background" });
    r.handle("tablet", { t: "presence", state: "background" });
    // Play humans until the bot is up, then let it move.
    for (let i = 0; i < 6 && (r.state.gameState as CatTowerState).turn !== 2; i++) takeTurn(r);
    // Acting woke the humans' devices; put them away again.
    r.handle("phone", { t: "presence", state: "background" });
    r.handle("tablet", { t: "presence", state: "background" });
    r.drainPushIntents();
    // The bot draws, then discards: one step a tick.
    for (let i = 0; i < 4 && (r.state.gameState as CatTowerState).turn === 2; i++) {
      r.state.timers.botAt = T0;
      r.tick();
    }
    const [push] = turnPushes(r);
    expect(push).toBeDefined();
    expect(push).not.toHaveProperty("from");
  });
});

describe("awakePlayers", () => {
  it("lists the players of connected, awake devices", () => {
    const r = started(true);
    expect(r.awakePlayers().sort()).toEqual([A, B]);
    // An old app's device speaks for no players.
    r.connect("old-ipad");
    expect(r.awakePlayers().sort()).toEqual([A, B]);
    r.handle("tablet", { t: "presence", state: "background" });
    expect(r.awakePlayers()).toEqual([A]);
    r.disconnect("phone");
    expect(r.awakePlayers()).toEqual([]);
  });
});
