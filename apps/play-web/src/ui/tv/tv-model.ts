/**
 * What the TV's screens say, worked out from the room: pure, so it is tested without a page.
 */
import { GAME_IDS, type GameId } from "../../lib/catalog";
import { playing, seatName } from "../../table/seat-names";

import type { RoomEvent, RoomView } from "@pounce/play-api/protocol";

/** The room's game. */
export const gameOf = (room: RoomView): GameId => room.gameId ?? "cat-tower";

/** The game a TV's "Change game" makes instead. */
export const otherGame = (id: GameId): GameId => GAME_IDS.find((g) => g !== id) ?? id;

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
  const g = room.game ?? room.tiles;
  if (!g || g.status !== "playing") return null;
  return g.turn;
}

/** The turn banner: "<Name>'s turn", or nothing. */
export function turnWords(room: RoomView): string {
  const s = turnSeat(room);
  return s === null ? "" : `${seatName(room.seats[s])}'s turn`;
}

export type Standing = { seat: number; won: boolean; out: boolean; detail: string };

/** Everyone who played, best first (GameOverView.swift's order), with what they finished on. */
export function standings(room: RoomView): Standing[] {
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
