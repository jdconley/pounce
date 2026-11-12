import { describe, expect, it } from "vitest";

import { liveState, startBody } from "./live";

const seats = [
  { kind: "human", person: { name: "JD", cat: 1 } },
  { kind: "human", person: { name: "Mia", cat: 2 } },
  { kind: "bot" },
];

describe("liveState for a game that counts pieces", () => {
  it("adds each seat's count and what it counts, beside the keys an older reader expects", () => {
    const s = liveState({ table: "Couch Cats", seats, phases: [], pieces: [9, 14, 3], controlled: [0], turn: 1, streak: null });
    expect(s).toEqual({
      table: "Couch Cats",
      seats: [
        { cat: 1, phase: 1, name: "JD", bot: false, me: true, progress: 9 },
        { cat: 2, phase: 1, name: "Mia", bot: false, me: false, progress: 14 },
        { cat: 3, phase: 1, bot: true, me: false, progress: 3 },
      ],
      turn: 1,
      mine: false,
      streak: null,
      progressKind: "pieces",
    });
  });

  it("a seat the game has no count for shows none left", () => {
    const s = liveState({ table: "T", seats, phases: [], pieces: [9], controlled: [], turn: null, streak: null });
    expect(s.seats.map((seat) => seat.progress)).toEqual([9, 0, 0]);
  });

  it("goes into the push as it is", () => {
    const s = liveState({ table: "T", seats, phases: [], pieces: [9, 14, 3], controlled: [0], turn: 0, streak: null });
    const body = startBody("BCDFG", s, 1_000, { title: "T", body: "Your move." }) as { aps: Record<string, unknown> };
    expect(body.aps["content-state"]).toEqual(s);
  });
});

describe("liveState for Cat Tower", () => {
  it("has exactly the keys it always had: no count, no kind", () => {
    const s = liveState({ table: "T", seats, phases: [2, 3, 1], controlled: [0], turn: 1, streak: null });
    expect(Object.keys(s)).toEqual(["table", "seats", "turn", "mine", "streak"]);
    expect(s.seats.map((seat) => Object.keys(seat))).toEqual([
      ["cat", "phase", "name", "bot", "me"],
      ["cat", "phase", "name", "bot", "me"],
      ["cat", "phase", "bot", "me"],
    ]);
    expect(s.seats.map((seat) => seat.phase)).toEqual([3, 4, 2]);
  });
});
