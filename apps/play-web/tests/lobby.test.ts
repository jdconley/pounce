import { describe, expect, test } from "vitest";

import { autoClaimSeat, minPlayers, rulesMessage, swapMessage, firstTableMessages, inviteHost, inviteMessages, practiceMessages, startBlock, startClosingOpenSeats, startLit, startWords, takeableSeats } from "../src/store/lobby";

import type { RoomView } from "@pounce/play-api/protocol";

const ME = { id: "11111111-1111-4111-8111-111111111111", name: "Mia", cat: 1 };
const GRANDMA = { id: "22222222-2222-4222-8222-222222222222", name: "Grandma", cat: 4 };

type Seat = RoomView["seats"][number];
const open: Seat = { kind: "open", yours: false, presence: null };
const closed: Seat = { kind: "closed", yours: false, presence: null };
const bot: Seat = { kind: "bot", yours: false, presence: null };
const me: Seat = { kind: "human", person: ME, yours: true, presence: "awake" };
const grandma: Seat = { kind: "human", person: GRANDMA, yours: false, presence: "awake" };

const room = (seats: Seat[], status: RoomView["status"] = "lobby"): RoomView => ({ code: "BCDFG", name: "The Sleepy Sardines", status, youAreHost: true, seats, game: null });

describe("the lobby plan (LobbyPlan.swift)", () => {
  test("a new table: not seated, then waiting for a seat, then a House Cat lights Start", () => {
    expect(startBlock(room([open, open, closed]))).toEqual({ kind: "notSeated" });
    expect(startWords(room([me, open, closed]))).toBe("Waiting for 1 seat.");
    expect(startLit(room([me, open, closed]))).toBe(false);
    expect(firstTableMessages(room([me, open, closed]))).toEqual([{ t: "configure", seat: 1, kind: "bot" }]);
    expect(startLit(room([me, bot, closed]))).toBe(true);
    expect(startWords(room([me, bot, closed]))).toBeNull();
  });

  test("Start closes open seats when two cats are already here", () => {
    expect(startClosingOpenSeats(room([me, grandma, open, closed]))).toEqual([{ t: "configure", seat: 2, kind: "closed" }, { t: "start" }]);
    expect(startClosingOpenSeats(room([me, open]))).toBeNull();
    expect(startBlock(room([me, closed]))).toEqual({ kind: "notEnough", players: 1 });
  });

  test("practice: a House Cat, the rest closed, dealt; never with someone else here", () => {
    expect(practiceMessages(room([me, open, open, closed]))).toEqual([
      { t: "configure", seat: 1, kind: "bot" },
      { t: "configure", seat: 2, kind: "closed" },
      { t: "start" },
    ]);
    expect(practiceMessages(room([me, grandma, open]))).toBeNull();
    expect(practiceMessages(room([open, open]))).toBeNull();
  });

  test("inviting opens a seat only when none is open", () => {
    expect(inviteMessages(room([me, bot, closed]))).toEqual([{ t: "configure", seat: 2, kind: "open" }]);
    expect(inviteMessages(room([me, open]))).toBeNull();
  });

  test("a guest takes an open seat first, else a House Cat's", () => {
    expect(takeableSeats(room([grandma, bot, open]))).toEqual([2, 1]);
    expect(autoClaimSeat(room([grandma, bot, closed]))).toBe(1);
    expect(autoClaimSeat(room([grandma, me, open]))).toBeNull();
    expect(autoClaimSeat(room([grandma, open], "playing"))).toBeNull();
  });

  test("who saved a guest a seat", () => {
    expect(inviteHost(room([grandma, bot]))).toEqual({ name: "Grandma", cat: 4, table: "The Sleepy Sardines", seatWaits: true });
    expect(inviteHost(room([grandma, grandma], "playing"))?.seatWaits).toBe(false);
    expect(inviteHost(room([bot, open]))).toBeNull();
  });
});

describe("a Birdwatch lobby", () => {
  const bird = (seats: Seat[]): RoomView => ({ ...room(seats), gameId: "birdwatch", options: { rules: "official" } });

  test("needs 4 players", () => {
    expect(minPlayers(bird([me]))).toBe(4);
    expect(minPlayers(room([me]))).toBe(2);
    expect(startLit(bird([me, bot, bot, closed, closed, closed]))).toBe(false);
    expect(startWords(bird([me, bot, bot, closed, closed, closed]))).toBe("Needs 4 players.");
    expect(startWords(bird([me, bot, open, open, closed, closed]))).toBe("Waiting for 2 seats.");
    expect(startLit(bird([me, bot, bot, bot, closed, closed]))).toBe(true);
    expect(startClosingOpenSeats(bird([me, bot, bot, bot, open, closed]))).toEqual([{ t: "configure", seat: 4, kind: "closed" }, { t: "start" }]);
    expect(startClosingOpenSeats(bird([me, bot, bot, open, open, closed]))).toBeNull();
  });

  test("a first table gets three House Cats, so Start is lit at once", () => {
    expect(firstTableMessages(bird([me, open, open, open, closed, closed]))).toEqual([1, 2, 3].map((seat) => ({ t: "configure", seat, kind: "bot" })));
  });

  test("practice: three House Cats, the rest closed, dealt", () => {
    expect(practiceMessages(bird([me, open, open, open, closed, closed]))).toEqual([
      ...[1, 2, 3].map((seat) => ({ t: "configure", seat, kind: "bot" })),
      { t: "start" },
    ]);
  });

  test("the rule set and seat swaps", () => {
    expect(rulesMessage("friesen")).toEqual({ t: "setOptions", options: { rules: "friesen" } });
    expect(swapMessage(1, 2)).toEqual({ t: "swapSeats", seats: [1, 2] });
  });
});
