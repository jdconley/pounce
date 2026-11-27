import { describe, expect, it } from "vitest";

import { TUMBLE_WINS, tumble, type TumbleAction, type TumbleState } from "./tumble";

import type { Seed } from "../rules/rng";

/* Toy Tumble's slow state: rounds, wins and who sits out. The room applies every change. */

const SEED: Seed = [1, 2, 3, 4];
const seeds = (n: number): Seed[] => Array.from({ length: n }, (_, i) => [i + 1, 1, 1, 1] as Seed);

const apply = (s: TumbleState, seat: number, a: TumbleAction): TumbleState => {
  const out = tumble.apply(s, seat, a);
  if (!out.ok) throw new Error(out.error);
  expect(out.events).toEqual([]);
  return out.state;
};
const start = (s: TumbleState, at = 5000, replay = false): TumbleState =>
  apply(s, 0, { k: "start", at, roundSeed: [9, 9, 9, 9], trickSeeds: seeds(s.seats), ...(replay ? { replay: true } : {}) });

describe("the Toy Tumble module", () => {
  it("seats 2 to 6, and nobody is ever to act", () => {
    expect(tumble.id).toBe("tumble");
    expect([tumble.minSeats, tumble.maxSeats]).toEqual([2, 6]);
    const s = tumble.create(3, SEED);
    expect(tumble.currentActor(s)).toBeNull();
    expect(tumble.currentActor(start(s))).toBeNull();
    expect(tumble.progressKind).toBe("score");
    expect(tumble.betweenAction).toBeNull();
    expect(tumble.forfeitAction).toEqual({ k: "leave" });
  });

  it("starts with no round, the House Cats easy unless the lobby said quick", () => {
    const s = tumble.create(3, SEED);
    expect(s).toEqual({
      seats: 3,
      cats: "easy",
      wins: [0, 0, 0],
      left: [false, false, false],
      away: [false, false, false],
      status: "between",
      r: 0,
      startsAt: 0,
      roundSeed: [0, 0, 0, 0],
      trickSeeds: [],
      outs: [],
      winner: null,
      waitingSince: null,
    });
    expect(tumble.create(2, SEED, { cats: "quick" }).cats).toBe("quick");
    expect(tumble.defaultOptions).toEqual({ cats: "easy" });
  });

  it("takes exactly {cats: easy | quick} as options", () => {
    const parse = tumble.parseOptions as (raw: unknown) => unknown;
    expect(parse({ cats: "easy" })).toEqual({ cats: "easy" });
    expect(parse({ cats: "quick" })).toEqual({ cats: "quick" });
    for (const bad of [{}, { cats: "hard" }, { cats: "easy", x: 1 }, { rules: "official" }, "easy", null]) expect(parse(bad)).toBeNull();
  });

  it("a client may only send Play without and Leave", () => {
    expect(tumble.parseAction({ k: "playWithout" })).toEqual({ k: "playWithout" });
    expect(tumble.parseAction({ k: "leave" })).toEqual({ k: "leave" });
    for (const bad of [
      { k: "start", at: 1, roundSeed: [1, 1, 1, 1], trickSeeds: [] },
      { k: "end", winner: 0 },
      { k: "out", seat: 0 },
      { k: "away", seat: 0, away: true },
      { k: "leave", seat: 1 },
      { type: "forfeit" },
      null,
    ]) {
      expect(tumble.parseAction(bad)).toBeNull();
    }
    expect(tumble.apply(tumble.create(2, SEED), 0, { k: "playWithout" }).ok).toBe(false);
  });

  it("a round: countdown, playing, outs in order, then the winner's win", () => {
    let s = start(tumble.create(3, SEED));
    expect(s).toMatchObject({ status: "countdown", r: 1, startsAt: 5000, roundSeed: [9, 9, 9, 9], trickSeeds: seeds(3), outs: [] });
    expect(tumble.phase(s)).toBe("playing");
    s = apply(s, 0, { k: "play" });
    expect(s.status).toBe("playing");
    s = apply(s, 0, { k: "out", seat: 2 });
    s = apply(s, 0, { k: "out", seat: 2 });
    s = apply(s, 0, { k: "out", seat: 1 });
    expect(s.outs).toEqual([2, 1]);
    s = apply(s, 0, { k: "end", winner: 0 });
    expect(s).toMatchObject({ status: "between", winner: 0, wins: [1, 0, 0], outs: [2, 1] });
    expect(tumble.phase(s)).toBe("between");
    expect(tumble.progress(s)).toEqual([1, 0, 0]);
    s = start(s, 9000);
    expect(s).toMatchObject({ status: "countdown", r: 2, startsAt: 9000, outs: [], winner: null, wins: [1, 0, 0] });
  });

  it("a round nobody won adds no win", () => {
    const s = apply(apply(start(tumble.create(2, SEED)), 0, { k: "play" }), 0, { k: "end", winner: null });
    expect(s).toMatchObject({ status: "between", winner: null, wins: [0, 0] });
  });

  it("is over at the third win", () => {
    let s = tumble.create(2, SEED);
    for (let i = 0; i < TUMBLE_WINS; i++) s = apply(apply(start(s), 0, { k: "play" }), 0, { k: "end", winner: 1 });
    expect(TUMBLE_WINS).toBe(3);
    expect(s).toMatchObject({ status: "over", winner: 1, wins: [0, 3] });
    expect(tumble.phase(s)).toBe("over");
    expect(tumble.apply(s, 0, { k: "start", at: 1, roundSeed: [1, 1, 1, 1], trickSeeds: seeds(2) }).ok).toBe(false);
  });

  it("a replay keeps the round's number and the wins", () => {
    let s = apply(apply(start(tumble.create(2, SEED)), 0, { k: "play" }), 0, { k: "end", winner: 0 });
    s = apply(start(s, 9000), 0, { k: "play" });
    s = start(s, 20_000, true);
    expect(s).toMatchObject({ status: "countdown", r: 2, startsAt: 20_000, wins: [1, 0], outs: [] });
  });

  it("waiting, and seats sitting out", () => {
    let s = tumble.create(3, SEED);
    s = apply(s, 0, { k: "wait", since: 1234 });
    expect(s.waitingSince).toBe(1234);
    s = apply(s, 0, { k: "away", seat: 2, away: true });
    expect(s.away).toEqual([false, false, true]);
    s = start(s);
    expect(s.waitingSince).toBeNull();
    s = apply(s, 0, { k: "away", seat: 2, away: false });
    expect(s.away).toEqual([false, false, false]);
  });

  it("leaving is for good; with one seat left the game is over and it wins", () => {
    let s = apply(apply(start(tumble.create(3, SEED)), 0, { k: "play" }), 0, { k: "end", winner: 2 });
    s = apply(s, 1, { k: "leave" });
    expect(s.left).toEqual([false, true, false]);
    expect(tumble.forfeited(s)).toEqual([false, true, false]);
    expect(s.status).toBe("between");
    s = apply(s, 2, { k: "leave" });
    expect(s).toMatchObject({ status: "over", winner: 0, wins: [0, 0, 1] });
  });

  it("stop ends the game early: the seat left with the most wins wins, a tie nobody", () => {
    let s = apply(apply(start(tumble.create(3, SEED)), 0, { k: "play" }), 0, { k: "end", winner: 1 });
    expect(apply(s, 0, { k: "stop" })).toMatchObject({ status: "over", winner: 1 });
    s = apply(s, 1, { k: "leave" });
    expect(apply(s, 0, { k: "stop" })).toMatchObject({ status: "over", winner: null });
  });

  it("refuses a round's changes out of their phase", () => {
    const s = tumble.create(2, SEED);
    expect(tumble.apply(s, 0, { k: "play" })).toEqual({ ok: false, error: "not_playing" });
    expect(tumble.apply(s, 0, { k: "out", seat: 1 })).toEqual({ ok: false, error: "not_playing" });
    expect(tumble.apply(start(s), 0, { k: "end", winner: 0 })).toEqual({ ok: false, error: "not_playing" });
    expect(tumble.parseAction({ k: "start" })).toBeNull();
  });

  it("has no turns, events, aims or House Cat moves for a room to ask about", () => {
    const s = tumble.create(2, SEED);
    expect(tumble.turnKey(s)).toBe("0:between");
    expect(tumble.turnKey(start(s))).toBe("1:countdown");
    expect(tumble.endsTurn({ k: "leave" }, [], 0)).toBe(false);
    expect(tumble.parseAim({})).toBeNull();
    expect(tumble.aimAllowed(s, 0, { table: [] })).toBe(false);
    expect(tumble.botAction(s, 0, () => 0)).toEqual({ k: "playWithout" });
    expect(tumble.fallbackAction(s, 0)).toEqual({ k: "playWithout" });
    expect(tumble.apply(s, 0, tumble.botAction(s, 0, () => 0)).ok).toBe(false);
    expect(tumble.startsTurn(undefined as never)).toBe(false);
    expect(tumble.filterEvent(undefined as never, [])).toBeUndefined();
  });

  it("the view holds the seeds from the first countdown on", () => {
    const s = tumble.create(2, SEED);
    expect(tumble.view(s, [0])).not.toHaveProperty("roundSeed");
    expect(tumble.view(s, [0])).not.toHaveProperty("trickSeeds");
    const counting = start(s);
    expect(tumble.view(counting, [])).toEqual(counting);
  });
});
