import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { createRng } from "../rules/rng";

import { catTower, parseAim } from "./cat-tower";

import type { Action, CatTowerState } from "../rules/engine";


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

  it("endsTurn counts a discard or going out, never a draw or a new deal", () => {
    const discarded = [
      { kind: "discarded" as const, seat: 0, card: 1 },
      { kind: "turn" as const, seat: 1 },
    ];
    expect(catTower.endsTurn({ type: "discard", card: 1 }, discarded, 0)).toBe(true);
    const out = { kind: "roundOver" as const, wentOut: 0, points: [], advanced: [], scores: [], phase: [] };
    expect(catTower.endsTurn({ type: "layDown", groups: [] }, [out], 0)).toBe(true);
    expect(catTower.endsTurn({ type: "draw", from: "deck" }, [{ ...out, wentOut: null }], 0)).toBe(false);
    expect(catTower.endsTurn({ type: "draw", from: "deck" }, [{ kind: "drew", seat: 0, from: "deck" }], 0)).toBe(false);
    const dealt = [
      { kind: "roundStarted" as const, round: 2, dealer: 1 },
      { kind: "turn" as const, seat: 2 },
    ];
    expect(catTower.endsTurn({ type: "nextRound" }, dealt, 0)).toBe(false);
  });
});

describe("cat tower aim", () => {
  it("parseAim takes exactly a target seat and group", () => {
    expect(parseAim({ target: { seat: 1, group: 0 } })).toEqual({ target: { seat: 1, group: 0 } });
    expect(catTower.parseAim({ target: { seat: 1, group: 0 } })).toEqual({ target: { seat: 1, group: 0 } });
    for (const bad of [
      { target: { seat: 1 } },
      { target: { seat: 1, group: 0 }, x: 1 },
      { target: { seat: 1, group: 0, x: 1 } },
      { target: { seat: -1, group: 0 } },
      { target: { seat: 1, group: 0.5 } },
      {},
      null,
      [],
      5,
    ])
      expect(parseAim(bad)).toBeNull();
  });

  it("aimAllowed only for a group another seat has laid", () => {
    const s = catTower.create(3, seedOf(42));
    s.laid[1] = [{ kind: "set", cards: [8, 32, 56], value: 9 }];
    const at = (seat: number, group: number) => ({ target: { seat, group } });
    expect(catTower.aimAllowed(s, 0, at(1, 0))).toBe(true);
    expect(catTower.aimAllowed(s, 0, at(2, 0))).toBe(false);
    expect(catTower.aimAllowed(s, 0, at(1, 1))).toBe(false);
    expect(catTower.aimAllowed(s, 0, at(3, 0))).toBe(false);
  });
});

describe("cat tower discard log", () => {
  // Two seats, seat 0 to draw, a 7 face up and the deck's top a 3.
  const start = (): CatTowerState => ({
    ...catTower.create(2, seedOf(7)),
    turn: 0,
    step: "draw",
    pendingSkip: [false, false],
    discard: [6],
    deck: [2],
    hands: [[0, 11, 12], [1, 13, 14]],
  });
  const play = (s: CatTowerState, seat: number, action: Action): CatTowerState => {
    const r = catTower.apply(s, seat, action);
    if (!r.ok) throw new Error(r.error);
    return r.state;
  };

  it("notes what each seat took, passed up and threw, as the table saw it", () => {
    let s = play(start(), 0, { type: "draw", from: "deck" });
    s = play(s, 0, { type: "discard", card: 11 });
    s = play(s, 1, { type: "draw", from: "discard" });
    expect(s.discardLog).toEqual({
      round: s.round,
      seats: [
        [
          { card: 6, took: false },
          { card: 11, took: false },
        ],
        [{ card: 11, took: true }],
      ],
    });
  });

  it("never reaches a device", () => {
    let s = play(start(), 0, { type: "draw", from: "deck" });
    s = play(s, 0, { type: "discard", card: 11 });
    expect(s.discardLog).toBeDefined();
    expect(catTower.view(s, [0])).not.toHaveProperty("discardLog");
    expect(catTower.view(s, [])).not.toHaveProperty("discardLog");
  });

  it("starts again each round", () => {
    let s = play(start(), 0, { type: "draw", from: "deck" });
    expect(s.discardLog?.seats[0]).toHaveLength(1);
    s = play({ ...s, status: "roundOver" }, 0, { type: "nextRound" });
    expect(s.discardLog).toBeUndefined();
  });

  it("botAction keeps back the card the next player is collecting", () => {
    // Seat 1 took two 7s; seat 0 holds a spare 7 and a spare 2, both worth 5.
    const s: CatTowerState = {
      ...start(),
      step: "play",
      phase: [0, 0],
      hands: [[4, 28, 7, 31, 54, 73], [1, 13]],
      discardLog: { round: 1, seats: [[], [{ card: 6, took: true }, { card: 30, took: true }]] },
      round: 1,
    };
    for (let seed = 1; seed <= 20; seed++) {
      expect(catTower.botAction(s, 0, createRng(seedOf(seed)))).toEqual({ type: "discard", card: 73 });
    }
  });
});
