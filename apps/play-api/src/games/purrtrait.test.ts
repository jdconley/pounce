import { expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { apply } from "../purrtrait/engine";
import { createRng } from "../rules/rng";

import { purrtrait } from "./purrtrait";

import { GAMES } from "./index";

const game = (seats = 3, timer: 45 | 60 | 90 = 60) => purrtrait.create(seats, seedOf(7), { timer });
const ok = <T extends { ok: boolean }>(r: T) => {
  if (!r.ok) throw new Error("refused");
  return r as Extract<T, { ok: true }>;
};

test("what a room asks of Purrtrait", () => {
  expect([purrtrait.id, purrtrait.minSeats, purrtrait.maxSeats, purrtrait.leaveTakeover]).toEqual(["purrtrait", 2, 10, undefined]);
  expect(GAMES.purrtrait).toBe(purrtrait);
  expect(purrtrait.defaultOptions).toEqual({ timer: 60 });
  expect(purrtrait.parseOptions?.({ timer: 90 })).toEqual({ timer: 90 });
  expect(purrtrait.parseOptions?.({ timer: 10 })).toBeNull();
  expect(purrtrait.create(4, seedOf(1)).timer).toBe(60);
  expect(game(4, 45).timer).toBe(45);
  expect([purrtrait.betweenAction, purrtrait.forfeitAction, purrtrait.timeUpAction]).toEqual([{ type: "nextTurn" }, { type: "forfeit" }, { type: "timeUp" }]);
  expect(purrtrait.parseAim({ target: { seat: 0, group: 0 } })).toBeNull();
  expect(purrtrait.aimAllowed(game(), 0, { target: { seat: 0, group: 0 } })).toBe(false);
  expect(purrtrait.progressKind).toBe("score");
});

test("a client may not send the room's own actions", () => {
  expect(purrtrait.parseAction({ type: "timeUp" })).toBeNull();
  expect(purrtrait.parseAction({ type: "nextTurn" })).toBeNull();
  expect(purrtrait.parseAction({ type: "giveUp" })).toEqual({ type: "giveUp" });
});

test("turnLimitMs: 10 seconds choosing, the timer drawing, none in the reveal or after", () => {
  const s = game(2, 45);
  expect(purrtrait.turnLimitMs?.(s)).toBe(10_000);
  const drawing = ok(apply(s, 0, { type: "choose", level: "easy" })).state;
  expect(purrtrait.turnLimitMs?.(drawing)).toBe(45_000);
  const reveal = ok(apply(drawing, 0, { type: "giveUp" })).state;
  expect(purrtrait.turnLimitMs?.(reveal)).toBeNull();
  expect(purrtrait.turnLimitMs?.(ok(apply(reveal, 1, { type: "forfeit" })).state)).toBeNull();
});

test("phase, actor, turn key and progress follow the engine", () => {
  const s = game();
  expect(purrtrait.phase(s)).toBe("playing");
  expect(purrtrait.currentActor(s)).toBe(0);
  expect(purrtrait.turnKey(s)).toBe("1:0");
  const drawing = ok(apply(s, 0, { type: "choose", level: "tricky" })).state;
  expect(purrtrait.phase(drawing)).toBe("playing");
  const got = ok(apply(drawing, 0, { type: "gotIt", seat: 2 }));
  expect(purrtrait.phase(got.state)).toBe("between");
  expect(purrtrait.currentActor(got.state)).toBeNull();
  expect(purrtrait.progress(got.state)).toEqual([2, 0, 2]);
  expect(purrtrait.forfeited(got.state)).toEqual([false, false, false]);
  expect(purrtrait.endsTurn({ type: "gotIt", seat: 2 }, got.events, 0)).toBe(true);
  const next = ok(apply(got.state, 0, { type: "nextTurn" }));
  expect(next.events.filter(purrtrait.startsTurn)).toEqual([{ type: "turn", drawer: 1, round: 1 }]);
  expect(purrtrait.turnKey(next.state)).toBe("1:1");
});

test("a game ends in `over`", () => {
  const s = ok(apply(game(2), 1, { type: "forfeit" })).state;
  expect(s.phase).toBe("over");
  expect(purrtrait.phase(s)).toBe("over");
});

test("fallbackAction: a choosing drawer picks the Easy word, a drawing one gives up", () => {
  const s = game();
  expect(purrtrait.fallbackAction(s, 0)).toEqual({ type: "choose", level: "easy" });
  const drawing = ok(apply(s, 0, { type: "choose", level: "easy" })).state;
  expect(purrtrait.fallbackAction(drawing, 0)).toEqual({ type: "giveUp" });
  expect(purrtrait.apply(drawing, 0, purrtrait.fallbackAction(drawing, 0)).ok).toBe(true);
  expect(purrtrait.botAction(drawing, 0, createRng(seedOf(1)))).toEqual({ type: "giveUp" });
});

test("view takes the viewer, apply takes the context", () => {
  const s = game();
  const kitten = purrtrait.view(s, [0], { drawerDevice: true, easyOnly: true });
  const grown = purrtrait.view(s, [0], { drawerDevice: true, easyOnly: false });
  expect(kitten.choices?.easy).toBe(grown.choices?.easy);
  expect(kitten.choices?.tricky).not.toBe(grown.choices?.tricky);
  const picked = ok(purrtrait.apply(s, 0, { type: "choose", level: "tricky" }, { easyOnly: true }));
  expect(picked.state.level).toBe("easy");
  const second = ok(purrtrait.apply(ok(purrtrait.apply(s, 0, { type: "choose", level: "easy" })).state, 0, { type: "giveUp" }));
  expect(purrtrait.view(second.state, [0]).last?.guesser).toBeNull();
  expect(purrtrait.filterEvent(second.events[0] as never, [0])).toEqual(second.events[0]);
});
