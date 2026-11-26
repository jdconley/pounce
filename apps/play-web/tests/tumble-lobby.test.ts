/**
 * Toy Tumble's lobby (spec §5.1): Start waits for every person's device ("Waiting for Sam", or
 * "Waiting for 2"), a device holds one seat, the House Cats' level is the host's pick, and How to
 * play says only what the game does, with no banned words.
 */
import { describe, expect, test } from "vitest";

import { catsMessage, oneSeatPerDevice, startBlock, startLit, startWords } from "../src/store/lobby";
import { HOW_TO_PLAY, TRICK_DOES } from "../src/tumble/help";

import type { Presence, RoomView } from "@pounce/play-api/protocol";

const seat = (name: string, yours: boolean, presence: Presence | null) => ({ kind: "human" as const, person: { id: `${name}-1111-4111-8111-111111111111`, name, cat: 1 }, yours, presence });

function lobby(seats: RoomView["seats"], gameId = "tumble"): RoomView {
  return { code: "BCDFG", name: "Toy Box", status: "lobby", youAreHost: true, seats, game: null, gameId: gameId as never };
}

describe("Start at a Toy Tumble table", () => {
  test("waits for a person whose device isn't connected, by name", () => {
    const room = lobby([seat("Ann", true, "awake"), seat("Sam", false, "asleep")]);
    expect(startBlock(room)).toEqual({ kind: "waiting", seats: [1] });
    expect(startLit(room)).toBe(false);
    expect(startWords(room)).toBe("Waiting for Sam");
  });

  test("says how many when it is more than one", () => {
    const room = lobby([seat("Ann", true, "awake"), seat("Sam", false, null), seat("Mia", false, "asleep"), seat("Lu", false, "away")]);
    expect(startWords(room)).toBe("Waiting for 2");
  });

  test("lights once everyone's device is here, House Cats included", () => {
    const room = lobby([seat("Ann", true, "awake"), seat("Sam", false, "away"), { kind: "bot", yours: false, presence: null }]);
    expect(startBlock(room)).toBeNull();
    expect(startWords(room)).toBeNull();
  });

  test("other games never wait on a device", () => {
    expect(startBlock(lobby([seat("Ann", true, "awake"), seat("Sam", false, "asleep")], "tiles"))).toBeNull();
  });
});

describe("the rest of the lobby", () => {
  test("one seat per device, and the Cats pill sends the host's pick", () => {
    expect(oneSeatPerDevice(lobby([]))).toBe(true);
    expect(oneSeatPerDevice(lobby([], "tiles"))).toBe(false);
    expect(catsMessage("quick")).toEqual({ t: "setOptions", options: { cats: "quick" } });
  });

  test("How to play says it in plain words, with no emoji", () => {
    const words = [...HOW_TO_PLAY, ...Object.values(TRICK_DOES)].join(" ");
    expect(words).not.toMatch(/\p{Extended_Pictographic}/u);
    for (const line of HOW_TO_PLAY) expect(line.length).toBeLessThan(140);
  });
});
