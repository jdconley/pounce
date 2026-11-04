import { describe, expect, it } from "vitest";

import { A, at, B, D0, keepDays, missDay, pairOn, play, settle } from "../../tests/streak-helpers";

import { addDays } from "./clock";
import { drainEvents, facts, pause, view } from "./pair-core";

const day = (n: number) => addDays(D0, n);

function streakOf(n: number) {
  const s = pairOn();
  keepDays(s, D0, n);
  settle(s, day(n - 1));
  drainEvents(s);
  return s;
}

describe("pair events (§12.1 status pushes)", () => {
  it("a milestone queues once, when it's reached", () => {
    const s = pairOn();
    keepDays(s, D0, 2);
    expect(drainEvents(s)).toEqual([]);
    keepDays(s, day(2), 1);
    expect(drainEvents(s)).toEqual([{ kind: "milestone", count: 3 }]);
    expect(drainEvents(s)).toEqual([]);
  });

  it("a nap used at settlement queues the count", () => {
    const s = streakOf(10);
    s.streak.naps = 1;
    missDay(s, day(10));
    settle(s, day(10));
    expect(drainEvents(s)).toEqual([{ kind: "nap", count: 10 }]);
  });

  it("win-back queues when it starts; a break records its day", () => {
    const s = streakOf(4);
    s.streak.naps = 0;
    missDay(s, day(4));
    settle(s, day(4));
    expect(drainEvents(s)).toEqual([{ kind: "winback", count: 4 }]);
    missDay(s, day(5));
    settle(s, day(5));
    expect(drainEvents(s)).toEqual([]);
    expect(s.streak).toMatchObject({ count: 0, breakId: 1, brokeOn: day(5) });
  });
});

describe("facts", () => {
  it("you're in once you've played, before any paw shows; your move and the tables", () => {
    const s = pairOn();
    play(s, A, at(D0, "09:00"), B);
    const f = facts(s, A, at(D0, "09:30"));
    expect(f).toMatchObject({ in: true, paused: false, breakId: 0, brokeOn: null, tables: ["ROOM1"] });
    expect(f.view.theirMove).toEqual(["ROOM1"]);
    expect(facts(s, B, at(D0, "09:30"))).toMatchObject({ in: false, view: { myMove: ["ROOM1"] } });
    expect(f.lastTurnAt).toBe(at(D0, "09:00"));
  });

  it("paused reflects today", () => {
    const s = pairOn();
    pause(s, A, 2, at(D0, "09:00"));
    expect(facts(s, B, at(D0, "10:00")).paused).toBe(true);
    expect(facts(s, B, at(day(3), "10:00")).paused).toBe(false);
  });

  it("views carry an empty pounce state until the glue fills it in", () => {
    expect(view(pairOn(), A, at(D0, "09:00")).pounce).toEqual({ sent: false, resting: false, quiet: false, answer: null, code: null, waiting: null });
  });
});
