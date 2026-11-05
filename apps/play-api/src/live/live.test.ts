import { describe, expect, test } from "vitest";

import {
  ATTRIBUTES_TYPE,
  CAP_MS,
  IDLE_MS,
  STALE_MS,
  deadline,
  endBody,
  expired,
  liveState,
  startAlert,
  startBody,
  updateBody,
  type LiveState,
} from "./live";

const T0 = Date.UTC(2026, 10, 5, 19, 0, 0);
const sec = (ms: number) => Math.floor(ms / 1000);

const state: LiveState = {
  table: "Couch Cats",
  seats: [
    { cat: 1, phase: 3, name: "JD", bot: false, me: true },
    { cat: 2, phase: 4, name: "Mia", bot: false, me: false },
  ],
  turn: 1,
  mine: false,
  streak: { count: 12, me: true, them: false },
};

describe("deadlines (§11.3)", () => {
  test("30 minutes with no move, or 2 hours since the start, whichever comes first", () => {
    expect(IDLE_MS).toBe(30 * 60_000);
    expect(CAP_MS).toBe(2 * 60 * 60_000);
    expect(deadline({ startedAt: T0, movedAt: T0 })).toBe(T0 + IDLE_MS);
    expect(deadline({ startedAt: T0, movedAt: T0 + 100 * 60_000 })).toBe(T0 + CAP_MS);
  });

  test("expired names which limit, on the edge itself", () => {
    const r = { startedAt: T0, movedAt: T0 };
    expect(expired(r, T0 + IDLE_MS - 1)).toBeNull();
    expect(expired(r, T0 + IDLE_MS)).toBe("idle");
    const busy = { startedAt: T0, movedAt: T0 + CAP_MS - 60_000 };
    expect(expired(busy, T0 + CAP_MS - 1)).toBeNull();
    expect(expired(busy, T0 + CAP_MS)).toBe("cap");
  });
});

describe("liveState", () => {
  test("phases are the one each seat works on, 1 to 10; bots have no name; me follows the device's seats", () => {
    const s = liveState({
      table: "Couch Cats",
      seats: [
        { kind: "human", person: { name: "JD", cat: 1 } },
        { kind: "bot" },
        { kind: "human", person: { name: "Mia", cat: 2 } },
      ],
      phases: [0, 4, 10],
      controlled: [0],
      turn: 2,
      streak: null,
    });
    expect(s).toEqual({
      table: "Couch Cats",
      seats: [
        { cat: 1, phase: 1, name: "JD", bot: false, me: true },
        { cat: 3, phase: 5, bot: true, me: false },
        { cat: 2, phase: 10, name: "Mia", bot: false, me: false },
      ],
      turn: 2,
      mine: false,
      streak: null,
    });
  });

  test("mine when the move is one of the device's seats; no turn between rounds", () => {
    const seats = [
      { kind: "human" as const, person: { name: "JD", cat: 1 } },
      { kind: "human" as const, person: { name: "Mia", cat: 2 } },
    ];
    expect(liveState({ table: "T", seats, phases: [0, 0], controlled: [0, 1], turn: 1, streak: null }).mine).toBe(true);
    const between = liveState({ table: "T", seats, phases: [], controlled: [0], turn: null, streak: { count: 2, me: true, them: true } });
    expect(between).toMatchObject({ turn: null, mine: false, streak: { count: 2, me: true, them: true } });
    expect(between.seats.map((s) => s.phase)).toEqual([1, 1]);
  });
});

describe("APNs bodies (§11.3, §12.7)", () => {
  test("start: attributes, the token request, a silent alert and the stale date", () => {
    const body = startBody("GH2VD", state, T0, startAlert(state));
    expect(body).toEqual({
      aps: {
        timestamp: sec(T0),
        event: "start",
        "content-state": state,
        "attributes-type": ATTRIBUTES_TYPE,
        attributes: { code: "GH2VD" },
        "input-push-token": 1,
        "stale-date": sec(T0 + STALE_MS),
        alert: { title: "Couch Cats", body: "Mia's move." },
      },
    });
    expect(ATTRIBUTES_TYPE).toBe("LiveTableAttributes");
    expect(startAlert({ ...state, turn: 0, mine: true })).toEqual({ title: "Couch Cats", body: "Your move." });
    expect(startAlert({ ...state, turn: null })).toEqual({ title: "Couch Cats", body: "Couch Cats" });
    expect(startAlert({ ...state, turn: 1, seats: [state.seats[0] as never, { cat: 3, phase: 1, bot: true, me: false }] })).toEqual({
      title: "Couch Cats",
      body: "House Cat's move.",
    });
  });

  test("update: the state and stale date; an alert rings only when given", () => {
    expect(updateBody(state, T0, null)).toEqual({
      aps: { timestamp: sec(T0), event: "update", "content-state": state, "stale-date": sec(T0 + STALE_MS) },
    });
    const loud = updateBody({ ...state, mine: true }, T0, { title: "JD", body: "Mia played. Your move at Couch Cats." });
    expect((loud.aps as Record<string, unknown>).alert).toEqual({ title: "JD", body: "Mia played. Your move at Couch Cats.", sound: "default" });
  });

  test("end: dismissed now, with the last state", () => {
    expect(endBody(state, T0)).toEqual({
      aps: { timestamp: sec(T0), event: "end", "content-state": state, "dismissal-date": sec(T0) },
    });
  });

  test("six seats with long names stay far under 4 KB", () => {
    const seats = Array.from({ length: 6 }, (_, i) => ({ cat: i, phase: 10, name: "W".repeat(24), bot: false, me: i === 0 }));
    const big = startBody("GH2VD", { ...state, table: "T".repeat(40), seats }, T0, startAlert({ ...state, seats }));
    expect(new TextEncoder().encode(JSON.stringify(big)).length).toBeLessThan(1500);
  });
});
