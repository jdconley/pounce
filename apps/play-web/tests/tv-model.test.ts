import { describe, expect, test } from "vitest";

import { anyoneSeated, back, bootPhase, cheerStep, gameOf, lobbySeats, momentFor, otherGame, overTitle, safeToReload, standings, NO_CHEER, turnSeat, turnWords } from "../src/ui/tv/tv-model";

import type { RoomView } from "@pounce/play-api/protocol";

type Seat = RoomView["seats"][number];
const open: Seat = { kind: "open", yours: false, presence: null };
const closed: Seat = { kind: "closed", yours: false, presence: null };
const bot: Seat = { kind: "bot", yours: false, presence: null };
const human = (name: string, cat = 1): Seat => ({ kind: "human", person: { id: name, name, cat }, yours: false, presence: "awake" });

const lobby = (seats: Seat[], gameId?: "tiles"): RoomView =>
  ({ code: "BCDFG", name: "Table", status: "lobby", youAreHost: false, seats, game: null, ...(gameId ? { gameId } : {}) }) as RoomView;

const catTower = (seats: Seat[], game: Partial<NonNullable<RoomView["game"]>>, status: RoomView["status"] = "playing"): RoomView =>
  ({
    ...lobby(seats),
    status,
    game: {
      round: 1,
      dealer: 0,
      turn: 0,
      step: "draw",
      status: status === "over" ? "gameOver" : "playing",
      deckCount: 40,
      discardTop: null,
      discardCount: 1,
      phase: seats.map(() => 0),
      scores: seats.map(() => 0),
      laid: seats.map(() => null),
      handCounts: seats.map(() => 10),
      hands: {},
      pendingSkip: seats.map(() => false),
      winners: [],
      forfeited: seats.map(() => false),
      ...game,
    },
  }) as RoomView;

const tiles = (seats: Seat[], t: Partial<NonNullable<RoomView["tiles"]>>, status: RoomView["status"] = "playing"): RoomView =>
  ({
    ...lobby(seats, "tiles"),
    status,
    tiles: { turn: 0, turns: 0, status: status === "over" ? "gameOver" : "playing", table: [], racks: {}, rackCounts: seats.map(() => 14), poolCount: 50, opened: seats.map(() => false), passed: seats.map(() => false), scores: seats.map(() => 0), winners: [], forfeited: seats.map(() => false), ...t },
  }) as unknown as RoomView;

describe("the TV lobby", () => {
  test("nobody is seated while every seat is open or closed; a person or a House Cat is someone", () => {
    expect(anyoneSeated(lobby([open, open, closed]))).toBe(false);
    expect(anyoneSeated(lobby([open, human("Ava")]))).toBe(true);
    expect(anyoneSeated(lobby([bot, open]))).toBe(true);
  });

  test("the seats shown are every seat but a closed one, each keyed by who sits there", () => {
    const seats = lobbySeats(lobby([human("Ava"), closed, open, bot]));
    expect(seats.map((s) => [s.seat, s.filled])).toEqual([
      [0, true],
      [2, false],
      [3, true],
    ]);
    // A new person in a seat is a new key, so their cat walks on again.
    expect(lobbySeats(lobby([human("Mo")]))[0]!.key).not.toBe(seats[0]!.key);
    expect(lobbySeats(lobby([human("Ava")]))[0]!.key).toBe(seats[0]!.key);
  });

  test("Change game makes the other game", () => {
    expect(otherGame("cat-tower")).toBe("tiles");
    expect(otherGame("tiles")).toBe("cat-tower");
    expect(gameOf(lobby([open]))).toBe("cat-tower");
    expect(gameOf(lobby([open], "tiles"))).toBe("tiles");
  });
});

describe("the turn banner", () => {
  test("whose turn it is, while a game is being played", () => {
    expect(turnSeat(catTower([human("Ava"), human("Mo")], { turn: 1 }))).toBe(1);
    expect(turnWords(catTower([human("Ava"), human("Mo")], { turn: 1 }))).toBe("Mo's turn");
    expect(turnWords(tiles([human("Ava"), bot], { turn: 1 }))).toBe("House Cat's turn");
  });

  test("no one's between rounds, in the lobby or after the game", () => {
    expect(turnSeat(catTower([human("Ava"), human("Mo")], { status: "roundOver" }))).toBeNull();
    expect(turnSeat(lobby([human("Ava")]))).toBeNull();
    expect(turnSeat(catTower([human("Ava"), human("Mo")], {}, "over"))).toBeNull();
    expect(turnWords(lobby([human("Ava")]))).toBe("");
  });
});

describe("game over", () => {
  test("Cat Tower: winners first, then the highest level, then the fewest points; a forfeit last", () => {
    const room = catTower(
      [human("Ava"), human("Mo"), human("Kiki"), human("Leo")],
      { winners: [2], phase: [4, 6, 9, 6], scores: [10, 80, 30, 40], forfeited: [false, false, false, true] },
      "over",
    );
    const s = standings(room);
    expect(s.map((x) => x.seat)).toEqual([2, 1, 0, 3]);
    expect(s[0]).toMatchObject({ won: true, out: false, detail: "Level 10 · 30" });
    expect(s[1]!.detail).toBe("Level 7 · 80");
    expect(s[3]).toMatchObject({ out: true, detail: "Left" });
    expect(overTitle(room)).toBe("Kiki wins");
  });

  test("Tuna Tiles: winners first, then the most points, signed", () => {
    const room = tiles([human("Ava"), human("Mo"), bot], { winners: [1], scores: [-12, 30, -18] }, "over");
    expect(standings(room).map((x) => [x.seat, x.detail])).toEqual([
      [1, "+30"],
      [0, "-12"],
      [2, "-18"],
    ]);
    expect(overTitle(room)).toBe("Mo wins");
  });

  test("a tie, and no winner", () => {
    expect(overTitle(tiles([human("Ava"), human("Mo")], { winners: [0, 1] }, "over"))).toBe("A tie");
    expect(overTitle(tiles([human("Ava"), human("Mo")], { winners: [] }, "over"))).toBe("Game over");
  });

  test("open and closed seats aren't ranked", () => {
    expect(standings(catTower([human("Ava"), open, closed, bot], {}, "over")).map((x) => x.seat)).toEqual([0, 3]);
  });
});

describe("moments", () => {
  test("a Cat Tower lay down is someone's moment, with the level they made", () => {
    const room = catTower([human("Ava"), human("Mo")], { phase: [0, 3] });
    expect(momentFor({ kind: "game", event: { kind: "laidDown", seat: 1, groups: [] } } as never, room)).toEqual({ seat: 1, title: "Mo laid down", sub: "Level 4" });
  });

  test("other events aren't", () => {
    const room = catTower([human("Ava"), human("Mo")], {});
    expect(momentFor({ kind: "game", event: { kind: "turn", seat: 1 } } as never, room)).toBeNull();
    expect(momentFor({ kind: "presence", seat: 0, presence: "away" } as never, room)).toBeNull();
  });
});

describe("Back", () => {
  test("opens the menu, goes back from the link to the menu, and closes the menu", () => {
    expect(back("closed")).toBe("items");
    expect(back("items")).toBe("closed");
    expect(back("link")).toBe("items");
  });
});

describe("one cheer per game end", () => {
  const ct = (event: object) => ({ kind: "game", event }) as never;
  const tt = (event: object) => ({ kind: "tiles", event }) as never;
  const run = (events: never[]) => events.reduce(cheerStep, NO_CHEER).cheered;

  test("a Cat Tower game that ends with its last round was cheered by that round: game over stays quiet", () => {
    expect(run([ct({ kind: "turn", seat: 0 }), ct({ kind: "roundOver", advanced: [0] }), ct({ kind: "gameOver", winners: [0] })])).toBe(true);
  });

  test("a presence change between the round and the end changes nothing", () => {
    expect(run([ct({ kind: "roundOver", advanced: [] }), { kind: "presence", seat: 1, presence: "away" } as never, ct({ kind: "gameOver", winners: [0] })])).toBe(true);
  });

  test("a forfeit ends it without a round: game over cheers", () => {
    expect(run([ct({ kind: "roundOver", advanced: [1] }), ct({ kind: "roundStarted" }), ct({ kind: "turn", seat: 0 }), ct({ kind: "forfeited", seat: 1 }), ct({ kind: "gameOver", winners: [0] })])).toBe(false);
  });

  test("Tuna Tiles' own game over event cheers at the table: game over stays quiet", () => {
    expect(run([tt({ kind: "forfeited", seat: 1 }), tt({ kind: "gameOver", winners: [0], scores: [] })])).toBe(true);
  });

  test("a TV that arrives after the end (a snapshot, no events) cheers once itself", () => {
    expect(run([])).toBe(false);
  });
});

describe("a TV reloading", () => {
  test("goes straight back to the table it kept, else to Start", () => {
    expect(bootPhase("BCDFG")).toBe("lobby");
    expect(bootPhase(null)).toBe("start");
  });

  test("a kept table wins; else the board it kept opens straight away", () => {
    expect(bootPhase("BCDFG", "B".repeat(22))).toBe("lobby");
    expect(bootPhase(null, "B".repeat(22))).toBe("board");
    expect(bootPhase(null, null)).toBe("start");
  });

  test("takes a new deploy anywhere but mid-hand", () => {
    expect(safeToReload("playing")).toBe(false);
    for (const p of ["connecting", "lobby", "over", "closed", "notFound", "locked", "needsUpdate"] as const) expect(safeToReload(p)).toBe(true);
  });
});
