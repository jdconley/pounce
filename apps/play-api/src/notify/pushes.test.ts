import { describe, expect, test } from "vitest";

import { answeredPush, playAgainPush, pouncePush, statusPush, yourMovePush } from "./pushes";

const streak = { pair: "pr_1", count: 12, me: false, them: true, naps: 1, myMove: ["GH2VD"], theirMove: [] };

describe("push builders", () => {
  test("your move: the room's thread and collapse id, who played, the streak", () => {
    expect(yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: { name: "Mia", cat: 2 }, completesToday: true, streak })).toEqual({
      kind: "your_move",
      title: "JD",
      body: "Mia played. Your turn makes today count.",
      code: "GH2VD",
      thread: "GH2VD",
      collapse: "GH2VD",
      from: { name: "Mia", cat: 2 },
      streak,
    });
    expect(yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: null, completesToday: false, streak: null })).toEqual({
      kind: "your_move",
      title: "JD",
      body: "Your move at Couch Cats.",
      code: "GH2VD",
      thread: "GH2VD",
      collapse: "GH2VD",
    });
  });

  test("pounce: per sender thread, per pounce collapse id, the target as data", () => {
    const from = { name: "Mia", cat: 2 };
    expect(pouncePush({ id: "pc_1", pair: "pr_1", to: "JD", from, target: { table: "GH2VD", name: "Couch Cats" }, streak })).toEqual({
      kind: "pounce",
      title: "JD",
      body: "Mia wants to play. Couch Cats?",
      code: "GH2VD",
      thread: "pounce:pr_1",
      collapse: "pounce:pc_1",
      from,
      streak,
      data: { pounce: { id: "pc_1", target: { table: "GH2VD" } } },
    });
    const pick = pouncePush({ id: "pc_1", pair: "pr_1", to: "JD", from, target: "pick", streak: null });
    expect(pick).not.toHaveProperty("code");
    expect(pick.body).toBe("Mia wants to play. You pick.");
    expect(pick.data).toEqual({ pounce: { id: "pc_1", target: "pick" } });
  });

  test("pounce answered goes to the sender, titled with their name", () => {
    expect(answeredPush({ id: "pc_1", pair: "pr_1", to: "Mia", who: { name: "JD", cat: 1 }, answer: "play", code: "NWCDF" })).toEqual({
      kind: "pounce_answered",
      title: "Mia",
      body: "JD is coming.",
      code: "NWCDF",
      thread: "pounce:pr_1",
      collapse: "answer:pc_1",
      from: { name: "JD", cat: 1 },
      data: { pounce: { id: "pc_1", answer: "play" } },
    });
    const later = answeredPush({ id: "pc_2", pair: null, to: "Mia", who: { name: "JD", cat: 1 }, answer: "later", code: null });
    expect(later.thread).toBe("pounce:pc_2");
    expect(later).not.toHaveProperty("code");
  });

  test("status pushes thread by pair", () => {
    expect(statusPush({ kind: "nap", pair: "pr_1", title: "Couch Cats", count: 12, streak })).toEqual({
      kind: "nap",
      title: "Couch Cats",
      body: "A cat nap covered yesterday. 12 days and counting.",
      thread: "pair:pr_1",
      collapse: "nap:pr_1",
      streak,
      data: { pair: "pr_1" },
    });
    expect(statusPush({ kind: "winback", pair: "pr_1", title: "Mia", count: 12, streak: null }).body).toBe("Two days in a row brings 12 back.");
    const m = statusPush({ kind: "milestone", pair: "pr_1", title: "Mia", count: 30, streak: null });
    expect(m).toMatchObject({ body: "30 days together. There's a gift on the rug.", collapse: "milestone:pr_1:30" });
    expect(m).not.toHaveProperty("streak");
    const p = statusPush({ kind: "paused", pair: "pr_1", title: "Mia", count: 3, who: { name: "Mia", cat: 2 }, streak: null });
    expect(p).toMatchObject({ body: "Mia put the cats to bed for 3 days.", from: { name: "Mia", cat: 2 } });
  });

  test("play again opens the new table", () => {
    expect(playAgainPush({ code: "NWCDF", table: "Couch Cats", who: { name: "Mia", cat: 2 } })).toEqual({
      kind: "play_again",
      title: "Couch Cats",
      body: "Mia dealt a new game.",
      code: "NWCDF",
      thread: "NWCDF",
      collapse: "play_again:NWCDF",
      from: { name: "Mia", cat: 2 },
    });
  });
});
