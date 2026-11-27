import { describe, expect, it } from "vitest";

import { sameRoomTable } from "./same-room";

import type { Env } from "../env";

/** An env whose one room answers `invite` with `answer` (or throws it). */
const envWith = (answer: () => Promise<unknown>) =>
  ({ ROOMS: { idFromName: (name: string) => name, get: () => ({ invite: answer }) } }) as unknown as Env;

describe("sameRoomTable (design §5.1)", () => {
  it("is true for a Purrtrait table, false for Cat Tower or no table", async () => {
    expect(await sameRoomTable(envWith(() => Promise.resolve({ game: "purrtrait" })), "BCDFG")).toBe(true);
    expect(await sameRoomTable(envWith(() => Promise.resolve({ game: "cat-tower" })), "BCDFG")).toBe(false);
    expect(await sameRoomTable(envWith(() => Promise.resolve(null)), "BCDFG")).toBe(false);
  });

  it("a room that fails to answer is not same-room: a Cat Tower pounce still goes", async () => {
    expect(await sameRoomTable(envWith(() => Promise.reject(new Error("overloaded"))), "BCDFG")).toBe(false);
  });
});
