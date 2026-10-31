import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { createRng } from "../rules/rng";

import { catTower } from "./cat-tower";

describe("catTower module", () => {
  it("declares id and seat bounds", () => {
    expect(catTower.id).toBe("cat-tower");
    expect(catTower.minSeats).toBe(2);
    expect(catTower.maxSeats).toBe(6);
  });

  it("create deals a playing game", () => {
    const s = catTower.create(3, seedOf(42));
    expect(s.seats).toBe(3);
    expect(s.status).toBe("playing");
  });

  it("currentActor is the turn while playing and null otherwise", () => {
    const s = catTower.create(3, seedOf(42));
    expect(catTower.currentActor(s)).toBe(s.turn);
    expect(catTower.currentActor({ ...s, status: "roundOver" })).toBeNull();
    expect(catTower.currentActor({ ...s, status: "gameOver" })).toBeNull();
  });

  it("apply rejects out-of-turn actions and applies in-turn ones", () => {
    const s = catTower.create(2, seedOf(7));
    const other = (s.turn + 1) % 2;
    expect(catTower.apply(s, other, { type: "draw", from: "deck" })).toEqual({
      ok: false,
      error: "not_your_turn",
    });
    const r = catTower.apply(s, s.turn, { type: "draw", from: "deck" });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.step).toBe("play");
  });

  it("view only exposes controlled hands; filterEvent hides other seats' deck draws", () => {
    const s = catTower.create(2, seedOf(7));
    expect(Object.keys(catTower.view(s, [1]))).toContain("hands");
    expect(Object.keys(catTower.view(s, [1]).hands)).toEqual(["1"]);
    const ev = { kind: "drew", seat: 0, from: "deck", card: 5 } as const;
    expect(catTower.filterEvent(ev, [1])).toEqual({ kind: "drew", seat: 0, from: "deck" });
    expect(catTower.filterEvent(ev, [0])).toEqual(ev);
  });

  it("botAction picks a legal action for the seat on turn", () => {
    const s = catTower.create(2, seedOf(7));
    const action = catTower.botAction(s, s.turn, createRng(seedOf(1)));
    const r = catTower.apply(s, s.turn, action);
    expect(r.ok).toBe(true);
  });
});
