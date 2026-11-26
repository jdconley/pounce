/**
 * The lobby's decisions, as iOS makes them (`LobbyPlan.swift`, `RoomEntry.swift`): what stops
 * Start, the seat "Add a player" fills, the first table's House Cat, a practice game, and the
 * seat a guest arriving takes.
 */
import type { ClientMessage, RoomView } from "@pounce/play-api/protocol";

export const MIN_PLAYERS = 2;

/** The fewest players a table's game deals for: Birdwatch needs 4, the others 2. */
export const minPlayers = (room: Pick<RoomView, "gameId">): number => (room.gameId === "birdwatch" ? 4 : MIN_PLAYERS);

export type StartBlock = { kind: "notSeated" } | { kind: "openSeats"; open: number; players: number } | { kind: "notEnough"; players: number };

export const mySeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.yours && s.kind === "human" ? [i] : []));
export const openSeats = (room: RoomView): number[] => room.seats.flatMap((s, i) => (s.kind === "open" ? [i] : []));
export const playerCount = (room: RoomView): number => room.seats.filter((s) => s.kind === "human" || s.kind === "bot").length;

export function startBlock(room: RoomView): StartBlock | null {
  if (room.status !== "lobby") return null;
  if (mySeats(room).length === 0) return { kind: "notSeated" };
  const open = openSeats(room).length;
  if (open > 0) return { kind: "openSeats", open, players: playerCount(room) };
  return playerCount(room) < minPlayers(room) ? { kind: "notEnough", players: playerCount(room) } : null;
}

/** Start with the cats already here: close every open seat, then start. Null unless that is all that's in the way. */
export function startClosingOpenSeats(room: RoomView): ClientMessage[] | null {
  const block = startBlock(room);
  if (block?.kind !== "openSeats" || block.players < minPlayers(room)) return null;
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
  if (block.kind === "openSeats") {
    if (block.players >= minPlayers(room)) return null;
    return block.open === 1 ? "Waiting for 1 seat." : `Waiting for ${block.open} seats.`;
  }
  return `Needs ${minPlayers(room)} players.`;
}
