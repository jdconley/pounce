import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { expectSound } from "../../tests/tiles-helpers";
import { createRng } from "../rules/rng";

import { tiles } from "./tiles";

import type { TilesEvent } from "../tiles/engine";

describe("tiles module", () => {
  it("declares id and seat bounds", () => {
    expect(tiles.id).toBe("tiles");
    expect(tiles.minSeats).toBe(2);
    expect(tiles.maxSeats).toBe(4);
  });

  it("create deals a playing game", () => {
    const s = tiles.create(3, seedOf(42));
    expect(s.seats).toBe(3);
    expect(s.status).toBe("playing");
    expectSound(s);
  });

  it("currentActor is the turn while playing and null once the game is over", () => {
    const s = tiles.create(3, seedOf(42));
    expect(tiles.currentActor(s)).toBe(s.turn);
    expect(tiles.currentActor({ ...s, status: "gameOver" })).toBeNull();
  });

  it("apply rejects out-of-turn actions and applies in-turn ones", () => {
    const s = tiles.create(2, seedOf(7));
    const other = (s.turn + 1) % 2;
    expect(tiles.apply(s, other, { type: "draw" })).toEqual({ ok: false, error: "not_your_turn" });
    const r = tiles.apply(s, s.turn, { type: "draw" });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.turn).toBe(other);
  });

  it("view only exposes controlled racks; filterEvent hides other seats' draws", () => {
    const s = tiles.create(2, seedOf(7));
    expect(Object.keys(tiles.view(s, [1]).racks)).toEqual(["1"]);
    const ev = { kind: "drew", seat: 0, tile: 5, poolCount: 77 } as const;
    expect(tiles.filterEvent(ev, [1])).toEqual({ kind: "drew", seat: 0, poolCount: 77 });
    expect(tiles.filterEvent(ev, [0])).toEqual(ev);
  });

  it("botAction picks a legal action for the seat on turn", () => {
    const s = tiles.create(2, seedOf(7));
    const action = tiles.botAction(s, s.turn, createRng(seedOf(1)));
    expect(tiles.apply(s, s.turn, action).ok).toBe(true);
  });

  it("endsTurn counts a play, a draw and a pass: each is a whole turn", () => {
    const turn: TilesEvent = { kind: "turn", seat: 1 };
    const played: TilesEvent = { kind: "played", seat: 0, table: [[1, 2, 3]], placed: [3], opened: false };
    expect(tiles.endsTurn({ type: "play", table: [[1, 2, 3]] }, [played, turn], 0)).toBe(true);
    expect(tiles.endsTurn({ type: "draw" }, [{ kind: "drew", seat: 0, tile: 4, poolCount: 9 }, turn], 0)).toBe(true);
    expect(tiles.endsTurn({ type: "pass" }, [{ kind: "passed", seat: 0 }, turn], 0)).toBe(true);
  });

  it("endsTurn counts the play that ends the game", () => {
    const played: TilesEvent = { kind: "played", seat: 0, table: [[1, 2, 3]], placed: [3], opened: false };
    const over: TilesEvent = { kind: "gameOver", winners: [0], reason: "out", scores: [4, -4], left: [0, 4] };
    expect(tiles.endsTurn({ type: "play", table: [[1, 2, 3]] }, [played, over], 0)).toBe(true);
  });

  it("endsTurn never counts a forfeit, though it moves the turn on, nor another seat's events", () => {
    expect(tiles.endsTurn({ type: "forfeit" }, [{ kind: "forfeited", seat: 0 }, { kind: "turn", seat: 1 }], 0)).toBe(false);
    expect(tiles.endsTurn({ type: "draw" }, [{ kind: "drew", seat: 1, poolCount: 9 }], 0)).toBe(false);
    expect(tiles.endsTurn({ type: "draw" }, [], 0)).toBe(false);
  });
});
