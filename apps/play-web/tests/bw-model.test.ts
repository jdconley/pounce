import { readFileSync } from "node:fs";

import { BIRD, cardFor } from "@pounce/play-api/birdwatch/cards";
import { describe, expect, test } from "vitest";

import {
  bwOverTitle,
  bwStandings,
  cardLabel,
  isSecretPartner,
  lastHand,
  lobbyRibbons,
  othersInOrder,
  partnerRows,
  RIBBONS,
  ribbonOf,
  seatOnShow,
  sides,
  signOf,
  sortHand,
  stepFor,
  suggestTrump,
} from "../src/table/bw-model";

import type { RoomView, ServerMessage } from "@pounce/play-api/protocol";

type Sample = { name: string; message: ServerMessage };
const samples = JSON.parse(readFileSync(new URL("../../play-api/fixtures/protocol/birdwatch-server-messages.json", import.meta.url), "utf8")) as Sample[];
const roomOf = (name: string): RoomView => structuredClone((samples.find((s) => s.name === name)!.message as Extract<ServerMessage, { t: "snapshot" }>).room);

describe("cards", () => {
  test("say their number, suit and points", () => {
    expect(cardLabel(cardFor("fish", 10), "official")).toBe("10, fish, 10 points");
    expect(cardLabel(BIRD, "tucker")).toBe("Bird, 20 points, top trump");
    expect(cardLabel(cardFor("bell", 1), "tucker")).toBe("1, bell, 15 points");
    expect(cardLabel(cardFor("mouse", 7), "official")).toBe("7, mouse");
    expect(cardLabel(cardFor("feather", 14), "friesen")).toBe("14, feather, 10 points");
  });

  test("sort by suit, trump on the right, the 1 above the 14, the Bird last", () => {
    const hand = [BIRD, cardFor("bell", 1), cardFor("fish", 5), cardFor("bell", 14), cardFor("mouse", 9), cardFor("fish", 12), cardFor("bell", 6)];
    expect(sortHand(hand, null, "tucker")).toEqual([cardFor("fish", 5), cardFor("fish", 12), cardFor("mouse", 9), cardFor("bell", 6), cardFor("bell", 14), cardFor("bell", 1), BIRD]);
    expect(sortHand(hand, "fish", "tucker")).toEqual([cardFor("mouse", 9), cardFor("bell", 6), cardFor("bell", 14), cardFor("bell", 1), cardFor("fish", 5), cardFor("fish", 12), BIRD]);
  });

  test("the trump hint is the suit held most, ties broken by higher cards", () => {
    expect(suggestTrump([cardFor("fish", 5), cardFor("fish", 6), cardFor("bell", 14), BIRD], "official")).toBe("fish");
    expect(suggestTrump([cardFor("fish", 5), cardFor("bell", 14)], "official")).toBe("bell");
    expect(suggestTrump([BIRD], "official")).toBeNull();
  });

  test("the partner picker: trump's row first, led by the Bird, high to low", () => {
    const rows = partnerRows([cardFor("fish", 5), cardFor("bell", 1), cardFor("bell", 14), BIRD, cardFor("mouse", 9)], "bell", "tucker");
    expect(rows.map((r) => r.suit)).toEqual(["bell", "fish", "mouse"]);
    expect(rows[0]!.cards).toEqual([BIRD, cardFor("bell", 1), cardFor("bell", 14)]);
  });
});

describe("the table's words", () => {
  test("four players: two sides, ribbons by team, the bid winner's side bidding", () => {
    const room = roomOf("snapshot-play-lead");
    const v = room.birdwatch!;
    const s = sides(v);
    expect(s.map((x) => x.seats)).toEqual([
      [0, 2],
      [1, 3],
    ]);
    expect(s.find((x) => x.bidding)!.seats).toContain(v.high!.seat);
    expect(ribbonOf(v, 0)).toBe(RIBBONS[0]);
    expect(ribbonOf(v, 3)).toBe(RIBBONS[1]);
    expect(signOf(v, v.high!.seat)).toEqual({ text: String(v.high!.amount), kind: "high" });
  });

  test("five players: only the bid winner's side wears a ribbon, and the partner only once shown", () => {
    const hidden = roomOf("snapshot-five-partner-hidden").birdwatch!;
    const bidder = hidden.high!.seat;
    const wearing = [0, 1, 2, 3, 4].filter((s) => ribbonOf(hidden, s) !== null);
    expect(wearing).toEqual([bidder]);
    const shown = roomOf("snapshot-five-partner-shown").birdwatch!;
    expect([0, 1, 2, 3, 4].filter((s) => ribbonOf(shown, s) !== null).sort()).toEqual([shown.high!.seat, 3].sort());
    expect(
      sides(shown)
        .filter((x) => x.bidding)
        .map((x) => x.seats[0])
        .sort(),
    ).toEqual([shown.high!.seat, 3].sort());
  });

  test("the partner mark shows only on the partner's own hand, before the reveal", () => {
    const v = roomOf("snapshot-five-you-are-partner").birdwatch!;
    expect(isSecretPartner(v, 3, true)).toBe(true);
    expect(isSecretPartner(v, 3, false)).toBe(false);
    expect(isSecretPartner(v, 4, true)).toBe(false);
  });

  test("six players: three sides across the table, ribbons in the lobby by seat order", () => {
    const room = roomOf("snapshot-six-house-cat");
    expect(sides(room.birdwatch!).map((x) => x.seats)).toEqual([
      [0, 3],
      [1, 4],
      [2, 5],
    ]);
    const lobby = roomOf("snapshot-lobby");
    // Four seated (two closed): teams by seat order among them.
    const ribbons = lobbyRibbons(lobby);
    expect(ribbons.get(0)).toBe(ribbons.get(2));
    expect(ribbons.get(1)).toBe(ribbons.get(3));
    expect(ribbons.get(0)).not.toBe(ribbons.get(1));
  });

  test("what this device does now", () => {
    const bid = roomOf("snapshot-bidding-your-move").birdwatch!;
    expect(stepFor(bid, 1)).toBe("bid");
    expect(stepFor(bid, 0)).toBe("wait");
    expect(stepFor(roomOf("snapshot-nest-bid-winner").birdwatch!, 1)).toBe("nest");
    expect(stepFor(roomOf("snapshot-between").birdwatch!, 0)).toBe("between");
    expect(stepFor(roomOf("snapshot-over-target").birdwatch!, 1)).toBe("over");
  });

  test("seats around the window start on my left", () => {
    expect(othersInOrder({ seats: 4 }, 1)).toEqual([2, 3, 0]);
    expect(othersInOrder({ seats: 5 }, null)).toEqual([0, 1, 2, 3, 4]);
  });

  test("a shared device raises the curtain for another seat and for a new hand", () => {
    const room = roomOf("snapshot-play-lead");
    room.seats[3] = { ...room.seats[3]!, yours: true };
    room.birdwatch!.turn = 1;
    expect(seatOnShow(room, null)).toMatchObject({ seat: 1, showHand: false, curtainSeat: 1 });
    expect(seatOnShow(room, { seat: 1, hand: room.birdwatch!.hand })).toMatchObject({ seat: 1, showHand: true, myTurn: true });
    expect(seatOnShow(room, { seat: 1, hand: room.birdwatch!.hand - 1 }).showHand).toBe(false);
    room.birdwatch!.turn = 3;
    expect(seatOnShow(room, { seat: 1, hand: room.birdwatch!.hand })).toMatchObject({ seat: 3, curtainSeat: 3 });
    room.birdwatch!.turn = 0;
    expect(seatOnShow(room, { seat: 1, hand: room.birdwatch!.hand })).toMatchObject({ seat: null, showHand: false });
  });

  test("between hands: the bid, made or missed, and each side's change", () => {
    const room = roomOf("snapshot-between");
    const s = lastHand(room)!;
    const r = room.birdwatch!.history.at(-1)!;
    expect(s.bid).toBe(r.bid);
    expect(s.made).toBe(r.made);
    expect(s.rows.map((x) => x.total)).toEqual(r.totals);
    expect(s.rows.filter((x) => x.bidding).length).toBe(1);
  });

  test("game over names the winning side, and a table everyone left", () => {
    const room = roomOf("snapshot-over-target");
    const w = room.birdwatch!.winners;
    expect(w.length).toBe(2);
    expect(bwOverTitle(room)).toMatch(/ and .* win$/);
    expect(bwStandings(room)[0]!.won).toBe(true);
    const left = roomOf("snapshot-over-left");
    expect(bwOverTitle(left)).toBe("Game over");
    expect(bwStandings(left).every((s) => s.left)).toBe(true);
    // A seat a House Cat took over keeps its person's name.
    expect(bwStandings(left)[0]!.name).not.toContain("House Cat");
  });
});
