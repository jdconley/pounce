/**
 * What the TV's screens say, worked out from the room: pure, so it is tested without a page.
 */
import { SHELF, type GameId } from "../../lib/catalog";
import { bwOverTitle, bwStandings } from "../../table/bw-model";
import { playing, seatName } from "../../table/seat-names";

import type { RoomPhase } from "../../store/room";
import type { RoomEvent, RoomView } from "@pounce/play-api/protocol";

/**
 * The room's game. The server only lets this player into a room of a game it lists in
 * X-Pounce-Games, which is its catalog, so a newer game's id never reaches here.
 */
export const gameOf = (room: RoomView): GameId => (room.gameId ?? "cat-tower") as GameId;

/** The game a TV's "Change game" makes instead: the next on the shelf, round again after the last. */
export const otherGame = (id: GameId): GameId => SHELF[(SHELF.indexOf(id) + 1) % SHELF.length] ?? id;

/** Someone sits at the table: a person or a House Cat. Until then the TV may change the game. */
export const anyoneSeated = (room: RoomView): boolean => room.seats.some(playing);

/**
 * The lobby's seats: every seat but a closed one. `key` changes with whoever sits there, so a
 * newcomer's cat walks on.
 */
export function lobbySeats(room: RoomView): { seat: number; filled: boolean; key: string }[] {
  return room.seats.flatMap((s, seat) => {
    if (s.kind === "closed") return [];
    const who = s.kind === "bot" ? "bot" : s.kind === "human" ? `p:${s.person?.id ?? ""}` : "open";
    return [{ seat, filled: playing(s), key: `${seat}:${who}` }];
  });
}

/** The seat whose turn it is, while a hand is being played; null between rounds and after. */
export function turnSeat(room: RoomView): number | null {
  if (room.status !== "playing") return null;
  const b = room.birdwatch;
  if (b) return b.status === "playing" && b.phase !== "between" ? b.turn : null;
  const g = room.game ?? room.tiles;
  if (!g || g.status !== "playing") return null;
  return g.turn;
}

/** The turn banner: "<Name>'s turn", or nothing. */
export function turnWords(room: RoomView): string {
  const s = turnSeat(room);
  return s === null ? "" : `${seatName(room.seats[s])}'s turn`;
}

/** `name`: a side's names, where a row stands for more than one seat (Birdwatch). */
export type Standing = { seat: number; won: boolean; out: boolean; detail: string; name?: string };

/** Everyone who played, best first (GameOverView.swift's order), with what they finished on. */
export function standings(room: RoomView): Standing[] {
  // Birdwatch: one row per side, under its first seat (its cat), named for all of them.
  if (room.birdwatch) return bwStandings(room).map((s) => ({ seat: s.seats[0]!, won: s.won, out: s.left, detail: String(s.score), name: s.name }));
  const g = room.game;
  const t = room.tiles;
  const winners = g?.winners ?? t?.winners ?? [];
  const forfeited = g?.forfeited ?? t?.forfeited ?? [];
  const seats = room.seats.flatMap((s, i) => (playing(s) ? [i] : []));
  const ranked = [...seats].sort((a, b) => {
    const w = Number(winners.includes(b)) - Number(winners.includes(a));
    if (w) return w;
    const f = Number(forfeited[a] ?? false) - Number(forfeited[b] ?? false);
    if (f) return f;
    if (g) return (g.phase[b] ?? 0) - (g.phase[a] ?? 0) || (g.scores[a] ?? 0) - (g.scores[b] ?? 0);
    return (t?.scores[b] ?? 0) - (t?.scores[a] ?? 0);
  });
  return ranked.map((seat) => {
    const out = forfeited[seat] ?? false;
    const points = t?.scores[seat] ?? 0;
    const detail = out ? "Left" : g ? `Level ${Math.min((g.phase[seat] ?? 0) + 1, 10)} · ${g.scores[seat] ?? 0}` : `${points > 0 ? "+" : ""}${points}`;
    return { seat, won: winners.includes(seat), out, detail };
  });
}

/** Game over's title. */
export function overTitle(room: RoomView): string {
  if (room.birdwatch) return bwOverTitle(room);
  const winners = room.game?.winners ?? room.tiles?.winners ?? [];
  if (winners.length === 1) return `${seatName(room.seats[winners[0]!])} wins`;
  return winners.length > 1 ? "A tie" : "Game over";
}

/** A moment the whole room should see big: a Cat Tower player laying down their level. */
export type Moment = { seat: number; title: string; sub: string };

export function momentFor(e: RoomEvent, room: RoomView): Moment | null {
  if (e.kind !== "game" || e.event.kind !== "laidDown") return null;
  const seat = e.event.seat;
  const level = Math.min((room.game?.phase[seat] ?? 0) + 1, 10);
  return { seat, title: `${seatName(room.seats[seat])} laid down`, sub: `Level ${level}` };
}

/** The TV's menu: shut, its three choices, or the link for another table. */
export type MenuView = "closed" | "items" | "link";

/** Back on a remote: opens the menu, goes back from the link to the choices, closes the menu. */
export const back = (menu: MenuView): MenuView => (menu === "closed" ? "items" : menu === "link" ? "items" : "closed");

/**
 * Whether the table already cheered the game's end, so game over doesn't cheer again: a Cat
 * Tower game that ends with its last round got that round's fanfare (or leap), and Tuna Tiles'
 * own game over event gets its fanfare at the table. A forfeit, or a TV that only sees the end in
 * a snapshot, leaves the cheer to game over.
 */
export type Cheer = { roundJustEnded: boolean; cheered: boolean };

export const NO_CHEER: Cheer = { roundJustEnded: false, cheered: false };

export function cheerStep(s: Cheer, e: RoomEvent): Cheer {
  if (e.kind === "birdwatch") return s;
  if (e.kind === "tiles") return e.event.kind === "gameOver" ? { roundJustEnded: false, cheered: true } : s;
  if (e.kind !== "game") return s;
  if (e.event.kind === "roundOver") return { roundJustEnded: true, cheered: false };
  if (e.event.kind === "gameOver") return { roundJustEnded: false, cheered: s.roundJustEnded };
  return { roundJustEnded: false, cheered: false };
}

/**
 * Where a TV opens: straight back to the table it kept (a reload, a new deploy), else to the Daily
 * Dish board it kept (every evening, for 30 days), else at Start.
 */
export const bootPhase = (kept: string | null, board: string | null = null): "lobby" | "board" | "start" => (kept ? "lobby" : board ? "board" : "start");

/** A new deploy may reload the TV in the lobby, at game over, or finding its table: never mid-hand. */
export const safeToReload = (phase: RoomPhase): boolean => phase !== "playing";
