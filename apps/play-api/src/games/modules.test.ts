import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { makeState } from "../../tests/tiles-helpers";
import { card } from "../rules/cards";

import { catTower } from "./cat-tower";
import { tiles } from "./tiles";

import type { CatTowerState } from "../rules/engine";

/* What a room asks of a game beyond playing it (GameModule's later members). */

describe("catTower: what a room asks of it", () => {
  const dealt = () => catTower.create(3, seedOf(42));

  it("parseAction is the parser the protocol always used", () => {
    expect(catTower.parseAction({ type: "draw", from: "deck" })).toEqual({ type: "draw", from: "deck" });
    expect(catTower.parseAction({ type: "discard", card: 3, skipTarget: 1 })).toEqual({ type: "discard", card: 3, skipTarget: 1 });
    expect(catTower.parseAction({ type: "draw" })).toBeNull();
    expect(catTower.parseAction({ type: "pass" })).toBeNull();
    expect(catTower.parseAction("draw")).toBeNull();
  });

  it("phase: playing, between two rounds, over", () => {
    const s = dealt();
    expect(catTower.phase(s)).toBe("playing");
    expect(catTower.phase({ ...s, status: "roundOver" })).toBe("between");
    expect(catTower.phase({ ...s, status: "gameOver" })).toBe("over");
  });

  it("between rounds the room deals the next one; a forfeit is the game's own", () => {
    expect(catTower.betweenAction).toEqual({ type: "nextRound" });
    expect(catTower.forfeitAction).toEqual({ type: "forfeit" });
    const s = { ...dealt(), status: "roundOver" as const };
    expect(catTower.apply(s, 0, catTower.betweenAction as NonNullable<typeof catTower.betweenAction>).ok).toBe(true);
    expect(catTower.apply(dealt(), 1, catTower.forfeitAction).ok).toBe(true);
  });

  it("forfeited is empty until someone forfeits, then per seat", () => {
    const s = dealt();
    expect(catTower.forfeited(s)).toEqual([]);
    const out = catTower.apply(s, 2, { type: "forfeit" });
    expect(out.ok && catTower.forfeited(out.state)).toEqual([false, false, true]);
  });

  it("turnKey is the round and the seat, as the room has always keyed a turn", () => {
    const s = dealt();
    expect(catTower.turnKey(s)).toBe(`${s.round}:${s.turn}`);
    expect(catTower.turnKey({ ...s, round: 4, turn: 2 })).toBe("4:2");
  });

  it("a turn starts with a turn event or a new round's deal", () => {
    expect(catTower.startsTurn({ kind: "turn", seat: 1 })).toBe(true);
    expect(catTower.startsTurn({ kind: "roundStarted", round: 2, dealer: 1 })).toBe(true);
    expect(catTower.startsTurn({ kind: "drew", seat: 1, from: "deck" })).toBe(false);
    expect(catTower.startsTurn({ kind: "skipped", seat: 1 })).toBe(false);
  });

  it("progress is each seat's shelf", () => {
    const s = { ...dealt(), phase: [0, 3, 9] };
    expect(catTower.progress(s)).toEqual([0, 3, 9]);
    expect(catTower.progressKind).toBe("shelf");
  });

  describe("fallbackAction: a plain legal move for the seat on the move", () => {
    const playing = (hand: number[], over: Partial<CatTowerState> = {}): CatTowerState => {
      const s = dealt();
      return { ...s, turn: 0, step: "play", hands: [hand, s.hands[1] as number[], s.hands[2] as number[]], ...over };
    };
    const accepted = (s: CatTowerState) => catTower.apply(s, s.turn, catTower.fallbackAction(s, s.turn)).ok;

    it("draws from the deck on the draw step", () => {
      const s = dealt();
      expect(catTower.fallbackAction(s, s.turn)).toEqual({ type: "draw", from: "deck" });
      expect(accepted(s)).toBe(true);
    });

    it("discards a number card first, then Yarn", () => {
      expect(catTower.fallbackAction(playing([96, 104, 5]), 0)).toEqual({ type: "discard", card: 5 });
      expect(catTower.fallbackAction(playing([104, 96]), 0)).toEqual({ type: "discard", card: 96 });
      expect(accepted(playing([96, 104, 5]))).toBe(true);
    });

    it("aims a Cucumber when that is all there is, at a seat that can be skipped", () => {
      expect(card(104).kind).toBe("cucumber");
      const s = playing([104]);
      expect(catTower.fallbackAction(s, 0)).toEqual({ type: "discard", card: 104, skipTarget: 1 });
      expect(accepted(s)).toBe(true);
      expect(catTower.fallbackAction(playing([104], { pendingSkip: [false, true, false] }), 0)).toEqual({
        type: "discard",
        card: 104,
        skipTarget: 2,
      });
      expect(catTower.fallbackAction(playing([104], { forfeited: [false, true, false] }), 0)).toMatchObject({ skipTarget: 2 });
    });

    it("discards the Cucumber unaimed when nobody can be skipped", () => {
      const s = playing([104], { pendingSkip: [false, true, true] });
      expect(catTower.fallbackAction(s, 0)).toEqual({ type: "discard", card: 104 });
      expect(accepted(s)).toBe(true);
    });
  });
});

describe("tiles: what a room asks of it", () => {
  const dealt = () => tiles.create(3, seedOf(42));

  it("parseAction is the tile game's own", () => {
    expect(tiles.parseAction({ type: "draw" })).toEqual({ type: "draw" });
    expect(tiles.parseAction({ type: "play", table: [[1, 2, 3]] })).toEqual({ type: "play", table: [[1, 2, 3]] });
    expect(tiles.parseAction({ type: "draw", from: "deck" })).toBeNull();
    expect(tiles.parseAction({ type: "nextRound" })).toBeNull();
  });

  it("phase: playing or over, never between: one round is one game", () => {
    const s = dealt();
    expect(tiles.phase(s)).toBe("playing");
    expect(tiles.phase({ ...s, status: "gameOver" })).toBe("over");
    expect(tiles.betweenAction).toBeNull();
  });

  it("a forfeit is the game's own, and forfeited is per seat from the start", () => {
    const s = dealt();
    expect(tiles.forfeited(s)).toEqual([false, false, false]);
    const out = tiles.apply(s, 2, tiles.forfeitAction);
    expect(out.ok && tiles.forfeited(out.state)).toEqual([false, false, true]);
  });

  it("turnKey counts completed turns", () => {
    const s = dealt();
    expect(tiles.turnKey(s)).toBe("0");
    const drawn = tiles.apply(s, s.turn, { type: "draw" });
    expect(drawn.ok && tiles.turnKey(drawn.state)).toBe("1");
  });

  it("a turn starts with a turn event and nothing else", () => {
    expect(tiles.startsTurn({ kind: "turn", seat: 1 })).toBe(true);
    expect(tiles.startsTurn({ kind: "drew", seat: 1, poolCount: 3 })).toBe(false);
    expect(tiles.startsTurn({ kind: "forfeited", seat: 1 })).toBe(false);
  });

  it("fallbackAction draws, or passes once the pool is empty: always legal for the seat on the move", () => {
    const s = dealt();
    expect(tiles.fallbackAction(s, s.turn)).toEqual({ type: "draw" });
    expect(tiles.apply(s, s.turn, tiles.fallbackAction(s, s.turn)).ok).toBe(true);
    const dry = makeState({ racks: [[1], [2]], pool: [] });
    expect(tiles.fallbackAction(dry, 0)).toEqual({ type: "pass" });
    expect(tiles.apply(dry, 0, tiles.fallbackAction(dry, 0)).ok).toBe(true);
  });

  it("progress is the pieces left on each rack", () => {
    const s = dealt();
    expect(tiles.progress(s)).toEqual([14, 14, 14]);
    const drawn = tiles.apply(s, s.turn, { type: "draw" });
    expect(drawn.ok && tiles.progress(drawn.state)[s.turn]).toBe(15);
    expect(tiles.progressKind).toBe("pieces");
  });
});
