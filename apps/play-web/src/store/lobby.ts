/**
 * The lobby's decisions, as iOS makes them (`LobbyPlan.swift`, `RoomEntry.swift`): what stops
 * Start, the seat "Add a player" fills, the first table's House Cat, a practice game, and the
 * seat a guest arriving takes.
 */
import { seatName } from "../table/seat-names";

import type { GameOptions } from "@pounce/play-api/games/index";
import type { ClientMessage, RoomView } from "@pounce/play-api/protocol";

export const MIN_PLAYERS = 2;

/** The fewest players a table's game deals for: Birdwatch needs 4, the others 2. */
export const minPlayers = (room: Pick<RoomView, "gameId">): number => (room.gameId === "birdwatch" ? 4 : MIN_PLAYERS);

export type StartBlock =
  | { kind: "notSeated" }
  | { kind: "openSeats"; open: number; players: number }
  | { kind: "notEnough"; players: number }
  /** Toy Tumble: a person's device isn't connected, and a real-time round needs everyone (spec §5.1). */
  | { kind: "waiting"; seats: number[] };

export const mySeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.yours && s.kind === "human" ? [i] : []));
export const openSeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.kind === "open" ? [i] : []));
export const playerCount = (room: RoomView): number => room.seats.filter((s) => s.kind === "human" || s.kind === "bot").length;
/** Toy Tumble: each person plays on their own device, at once. */
/** Toy Tumble: each person plays on their own device, at once. The game ids don't list it until its server module lands. */
const realTime = (room: Pick<RoomView, "gameId">): boolean => room.gameId === "tumble";

/** At a Toy Tumble table, the people whose device isn't connected: Start waits for them. */
export function waitingSeats(room: RoomView): number[] {
  if (!realTime(room)) return [];
  return room.seats.flatMap((s, i) => (s.kind === "human" && !s.yours && (s.presence === null || s.presence === "asleep") ? [i] : []));
}

export function startBlock(room: RoomView): StartBlock | null {
  if (room.status !== "lobby") return null;
  if (mySeats(room).length === 0) return { kind: "notSeated" };
  const open = openSeats(room).length;
  if (open > 0) return { kind: "openSeats", open, players: playerCount(room) };
  if (playerCount(room) < minPlayers(room)) return { kind: "notEnough", players: playerCount(room) };
  const waiting = waitingSeats(room);
  return waiting.length > 0 ? { kind: "waiting", seats: waiting } : null;
}

/** Start with the cats already here: close every open seat, then start. Null unless that is all that's in the way. */
export function startClosingOpenSeats(room: RoomView): ClientMessage[] | null {
  const block = startBlock(room);
  if (block?.kind !== "openSeats" || block.players < minPlayers(room) || waitingSeats(room).length > 0) return null;
  return [...openSeats(room).map((seat): ClientMessage => ({ t: "configure", seat, kind: "closed" })), { t: "start" }];
}

/** Start deals now, or after closing the open seats. */
export const startLit = (room: RoomView): boolean => startBlock(room) === null || startClosingOpenSeats(room) !== null;

/** The seat "Add a player" fills: the first open one, else the first closed one. */
export function seatToAdd(room: RoomView): number | null {
  if (room.status !== "lobby") return null;
  const open = room.seats.findIndex((s) => s.kind === "open");
  if (open >= 0) return open;
  const closed = room.seats.findIndex((s) => s.kind === "closed");
  return closed >= 0 ? closed : null;
}

const othersHere = (room: RoomView): boolean => room.seats.some((s) => s.kind === "bot" || (s.kind === "human" && !s.yours));

/** The free seats (open first, then closed) the House Cats a table needs to deal take: enough for `minPlayers`. */
function houseCatSeats(room: RoomView): number[] {
  const need = minPlayers(room) - playerCount(room);
  const free = [...openSeats(room), ...room.seats.flatMap((s, i) => (s.kind === "closed" ? [i] : []))];
  return need > 0 && free.length >= need ? free.slice(0, need) : [];
}

/** A practice game: House Cats in the first free seats (one, or three for Birdwatch), the other open seats closed, then start. */
export function practiceMessages(room: RoomView): ClientMessage[] | null {
  if (room.status !== "lobby" || mySeats(room).length === 0 || othersHere(room)) return null;
  const cats = houseCatSeats(room);
  if (cats.length === 0) return null;
  const others = openSeats(room).filter((s) => !cats.includes(s));
  return [
    ...cats.map((seat): ClientMessage => ({ t: "configure", seat, kind: "bot" })),
    ...others.map((s): ClientMessage => ({ t: "configure", seat: s, kind: "closed" })),
    { t: "start" },
  ];
}

/** A host's first table: House Cats in the first open seats (one, or three for Birdwatch), so Start is lit at once. */
export function firstTableMessages(room: RoomView): ClientMessage[] | null {
  if (room.status !== "lobby" || mySeats(room).length === 0 || othersHere(room)) return null;
  const cats = houseCatSeats(room).filter((s) => room.seats[s]?.kind === "open");
  return cats.length > 0 ? cats.map((seat): ClientMessage => ({ t: "configure", seat, kind: "bot" })) : null;
}

/** Birdwatch's rule set, the host's choice in the lobby. */
export const rulesMessage = (rules: "official" | "tucker" | "friesen"): ClientMessage => ({ t: "setOptions", options: { rules } });

/** Swaps two seats in the lobby, to choose teams. */
export const swapMessage = (a: number, b: number): ClientMessage => ({ t: "swapSeats", seats: [a, b] });

/** Someone is being invited: make sure a seat is open for them. */
export function inviteMessages(room: RoomView): ClientMessage[] | null {
  if (room.status !== "lobby" || mySeats(room).length === 0 || room.seats.some((s) => s.kind === "open")) return null;
  const closed = room.seats.findIndex((s) => s.kind === "closed");
  return closed >= 0 ? [{ t: "configure", seat: closed, kind: "open" }] : null;
}

/** Seats a person arriving could take: open ones, then House Cats'. */
export function takeableSeats(room: RoomView): number[] {
  if (room.status !== "lobby") return [];
  const open = room.seats.flatMap((s, i) => (s.kind === "open" ? [i] : []));
  const bots = room.seats.flatMap((s, i) => (s.kind === "bot" ? [i] : []));
  return [...open, ...bots];
}

/** The claim that seats a guest arriving with no seat, or null. */
export function autoClaimSeat(room: RoomView): number | null {
  if (room.status !== "lobby" || mySeats(room).length > 0) return null;
  return takeableSeats(room)[0] ?? null;
}

/** Who saved a guest a seat: the first person seated, and whether a seat waits for them. */
export function inviteHost(room: RoomView): { name: string; cat: number; table: string; seatWaits: boolean } | null {
  const person = room.seats.find((s) => s.kind === "human")?.person;
  if (!person) return null;
  return { name: person.name, cat: person.cat, table: room.name, seatWaits: takeableSeats(room).length > 0 };
}

/** The words under Start, or null when it deals. */
export function startWords(room: RoomView): string | null {
  const block = startBlock(room);
  if (!block) return null;
  if (block.kind === "notSeated") return "Take a seat to play.";
  if (block.kind === "waiting") return waitingWords(room, block.seats);
  if (block.kind === "openSeats") {
    if (block.players >= minPlayers(room)) return waitingSeats(room).length > 0 ? waitingWords(room, waitingSeats(room)) : null;
    return block.open === 1 ? "Waiting for 1 seat." : `Waiting for ${block.open} seats.`;
  }
  return `Needs ${minPlayers(room)} players.`;
}

/** "Waiting for Sam", or "Waiting for 2". */
export const waitingWords = (room: RoomView, seats: number[]): string =>
  seats.length === 1 ? `Waiting for ${seatName(room.seats[seats[0]!])}` : `Waiting for ${seats.length}`;

/** Toy Tumble holds one seat per device, so this device adds no second player. */
export const oneSeatPerDevice = (room: Pick<RoomView, "gameId">): boolean => realTime(room);

/** The host's choice of House Cat level at a Toy Tumble table (the lobby's two pills). */
export const catsMessage = (cats: "easy" | "quick"): ClientMessage => ({ t: "setOptions", options: { cats } as unknown as GameOptions });
