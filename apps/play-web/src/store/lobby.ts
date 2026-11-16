/**
 * The lobby's decisions, as iOS makes them (`LobbyPlan.swift`, `RoomEntry.swift`): what stops
 * Start, the seat "Add a player" fills, the first table's House Cat, a practice game, and the
 * seat a guest arriving takes.
 */
import type { ClientMessage, RoomView } from "@pounce/play-api/protocol";

export const MIN_PLAYERS = 2;

export type StartBlock = { kind: "notSeated" } | { kind: "openSeats"; open: number; players: number } | { kind: "notEnough"; players: number };

export const mySeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.yours && s.kind === "human" ? [i] : []));
export const openSeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.kind === "open" ? [i] : []));
export const playerCount = (room: RoomView): number => room.seats.filter((s) => s.kind === "human" || s.kind === "bot").length;

export function startBlock(room: RoomView): StartBlock | null {
  if (room.status !== "lobby") return null;
  if (mySeats(room).length === 0) return { kind: "notSeated" };
  const open = openSeats(room).length;
  if (open > 0) return { kind: "openSeats", open, players: playerCount(room) };
  return playerCount(room) < MIN_PLAYERS ? { kind: "notEnough", players: playerCount(room) } : null;
}

/** Start with the cats already here: close every open seat, then start. Null unless that is all that's in the way. */
export function startClosingOpenSeats(room: RoomView): ClientMessage[] | null {
  const block = startBlock(room);
  if (block?.kind !== "openSeats" || block.players < MIN_PLAYERS) return null;
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

/** A practice game: a House Cat in the first free seat, the other open seats closed, then start. */
export function practiceMessages(room: RoomView): ClientMessage[] | null {
  if (room.status !== "lobby" || mySeats(room).length === 0 || othersHere(room)) return null;
  const seat = seatToAdd(room);
  if (seat === null) return null;
  const others = openSeats(room).filter((s) => s !== seat);
  return [
    { t: "configure", seat, kind: "bot" },
    ...others.map((s): ClientMessage => ({ t: "configure", seat: s, kind: "closed" })),
    { t: "start" },
  ];
}

/** A host's first table: a House Cat in the first open seat, so Start is lit at once. */
export function firstTableMessages(room: RoomView): ClientMessage[] | null {
  if (room.status !== "lobby" || mySeats(room).length === 0 || othersHere(room)) return null;
  const seat = room.seats.findIndex((s) => s.kind === "open");
  return seat >= 0 ? [{ t: "configure", seat, kind: "bot" }] : null;
}

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
  if (block.kind === "openSeats") {
    if (block.players >= MIN_PLAYERS) return null;
    return block.open === 1 ? "Waiting for 1 seat." : `Waiting for ${block.open} seats.`;
  }
  return "Needs 2 players.";
}
