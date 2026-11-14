import { describe, expect, test } from "vitest";

import { roomSteps, type RoomFacts } from "./room";

import type { SeatInfo } from "../room/core";

const person = (n: number) => ({ id: `${n}`.repeat(8), name: `P${n}`, cat: n });
const human = (deviceId: string, n: number): SeatInfo => ({ kind: "human", person: person(n), deviceId });

const lobby = (seats: SeatInfo[], over: Partial<RoomFacts> = {}): RoomFacts => ({
  game: "tiles",
  hostDeviceId: "host",
  status: "lobby",
  seats,
  gameState: null,
  ...over,
});

const names = (steps: ReturnType<typeof roomSteps>) => steps.map((s) => `${s.deviceId}:${s.milestone}`);

describe("roomSteps", () => {
  test("a seat at your own table, and at someone else's", () => {
    const told = new Set<string>();
    const steps = roomSteps(lobby([human("host", 1), human("guest", 2), { kind: "open" }, { kind: "bot" }]), told, null);
    expect(names(steps)).toEqual(["host:seat_taken", "guest:seat_taken", "guest:joined_table"]);
    expect(steps.every((s) => s.game === "tiles")).toBe(true);
    // Told once: the same seats again say nothing.
    expect(roomSteps(lobby([human("host", 1), human("guest", 2)]), told, null)).toEqual([]);
  });

  test("a seat without a device (an old room's) is no one's", () => {
    expect(roomSteps(lobby([{ kind: "human", person: person(1) }]), new Set(), null)).toEqual([]);
  });

  test("a move the room accepted", () => {
    const told = new Set<string>();
    const playing = lobby([human("host", 1)], { status: "playing", gameState: {} });
    expect(names(roomSteps(playing, told, "host"))).toEqual(["host:seat_taken", "host:first_move"]);
    expect(roomSteps(playing, told, "host")).toEqual([]);
  });

  test("a finished game alone with a House Cat", () => {
    const facts = lobby([human("host", 1), { kind: "bot", botLevel: "house" }], { status: "over", gameState: {} });
    expect(names(roomSteps(facts, new Set(["host:seat_taken"]), null))).toEqual(["host:game_finished"]);
  });

  test("a finished pass-and-play game: two people, one device", () => {
    const facts = lobby([human("host", 1), human("host", 2)], { status: "over", gameState: {} });
    expect(names(roomSteps(facts, new Set(["host:seat_taken"]), null))).toEqual(["host:game_finished", "host:game_with_human"]);
  });

  test("a finished game with someone on another device", () => {
    const facts = lobby([human("host", 1), human("guest", 2)], { status: "over", gameState: {} });
    expect(names(roomSteps(facts, new Set(), null))).toEqual([
      "host:seat_taken",
      "guest:seat_taken",
      "guest:joined_table",
      "host:game_finished",
      "host:game_with_human",
      "host:game_with_device",
      "guest:game_finished",
      "guest:game_with_human",
      "guest:game_with_device",
    ]);
  });

  test("a table closed before it was dealt finished no game", () => {
    expect(names(roomSteps(lobby([human("host", 1)], { status: "over" }), new Set(), null))).toEqual(["host:seat_taken"]);
  });
});
