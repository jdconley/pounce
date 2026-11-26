/**
 * Purrtrait as the web player reads it: the wire's types (the server's wire contract), and what
 * each screen says, worked out from the room. Pure, so it is tested without a page.
 */
import { seatName } from "./seat-names";

import type { InkOp } from "./purr-ink";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Group, Level, PurrEvent, PurrOptions } from "@pounce/play-api/purrtrait/engine";
import type { PurrView } from "@pounce/play-api/purrtrait/view";

export type { Group, Level, PurrAction, PurrEvent, PurrOptions, PurrPhase } from "@pounce/play-api/purrtrait/engine";
export type { PurrView } from "@pounce/play-api/purrtrait/view";
export type Timer = PurrOptions["timer"];

/** Only the screen's snapshot has it: the join key the TV's QR carries, and the code to type. */
export type NearView = { key: string; code: string; expiresIn: number };

/** The ink messages the room sends (no seq; never in a snapshot). */
export type InkMessage =
  | { t: "ink"; seat: number; turn: string; ops: InkOp[] }
  | { t: "inkSync"; turn: string; ops: InkOp[] }
  | { t: "inkResend"; turn: string };

/** A room as a Purrtrait table sees it: the snapshot's own fields beside `RoomView`'s. */
export type PurrRoom = RoomView & { purrtrait?: PurrView; near?: NearView };

export const purrOf = (room: RoomView | null | undefined): PurrView | undefined => (room as PurrRoom | null | undefined)?.purrtrait;
export const nearOf = (room: RoomView | null | undefined): NearView | undefined => (room as PurrRoom | null | undefined)?.near;
export const isPurr = (room: Pick<RoomView, "gameId"> | null | undefined): boolean => (room?.gameId as string | undefined) === "purrtrait";

/** The lobby's timer pills, in seconds. */
export const TIMERS: readonly Timer[] = [45, 60, 90];
export const timerOf = (room: RoomView): Timer => ((room.options as { timer?: Timer } | undefined)?.timer ?? 60) as Timer;
export const timerMessage = (timer: Timer) => ({ t: "setOptions" as const, options: { timer } });

/** What the TV shows as the hint, one word. */
export const GROUP_WORDS: Record<Group, string> = {
  animals: "Animal",
  food: "Food",
  home: "Home",
  outside: "Outside",
  things: "Thing",
  actions: "Action",
  jobs: "Job",
  places: "Place",
};

export const POINTS: Record<Level, number> = { easy: 1, tricky: 2 };

/** A countdown as the TV and the drawer show it: 1:00, 0:42, 0:05. */
export function clock(ms: number): string {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/** The time left now, from the snapshot's `remainingMs` and how long ago it came. */
export function leftNow(remainingMs: number | null, paused: boolean, since: number, now: number): number | null {
  if (remainingMs === null) return null;
  return paused ? remainingMs : Math.max(0, remainingMs - (now - since));
}

/** The seat that draws after this turn: the next in order, round 2 starting again at the first. Null when this is the last turn. */
export function nextDrawer(v: PurrView): number | null {
  if (v.phase === "over" || v.drawer === null || v.order.length === 0) return null;
  const at = v.order.indexOf(v.drawer);
  if (at >= 0 && at + 1 < v.order.length) return v.order[at + 1]!;
  // The drawer left mid-round: the next seat in order after theirs.
  if (at < 0) {
    const after = v.order.find((s) => s > v.drawer!);
    if (after !== undefined) return after;
  }
  return v.round < v.rounds ? v.order[0]! : null;
}

/** This device's seats in the game (still in). */
export const mineIn = (room: RoomView, v: PurrView): number[] => room.seats.flatMap((s, i) => (s.yours && s.kind === "human" && !v.out[i] ? [i] : []));

/** What this device is in this turn. */
export type PurrRole = "drawer" | "guesser" | "watcher";

/** The drawer's device (it picks the word, or holds the drawing turn), a guesser, or a device with no seat in. */
export function roleOf(room: RoomView, v: PurrView): PurrRole {
  if (v.choices || v.youDraw) return "drawer";
  return mineIn(room, v).length > 0 ? "guesser" : "watcher";
}

/** The line under "Look at the TV", and the TV's: who is up and what they are doing. */
export function turnLine(room: RoomView, v: PurrView): string {
  if (v.drawer === null) return "";
  const who = seatName(room.seats[v.drawer]);
  if (v.phase === "choosing") return `${who} is picking`;
  if (v.phase === "drawing") return `${who} is drawing`;
  return "";
}

/** The reveal's line: who got it, or why nobody did. */
export function revealLine(room: RoomView, v: PurrView, reason: "time" | "gaveUp" | "left" | null): string {
  const last = v.last;
  if (!last) return "";
  if (last.guesser !== null) return `${seatName(room.seats[last.guesser])} got it`;
  if (reason === "gaveUp") return "Gave up";
  if (reason === "left") return "Nobody got it";
  return "Time's up";
}

/** Everyone in the game, best first; out seats last. */
export function purrStandings(room: RoomView, v: PurrView): { seat: number; score: number; won: boolean; out: boolean }[] {
  const seats = room.seats.flatMap((s, i) => (i < v.seats && (s.kind === "human" || s.kind === "bot") ? [i] : []));
  return seats
    .map((seat) => ({ seat, score: v.scores[seat] ?? 0, won: v.winners.includes(seat), out: v.out[seat] ?? false }))
    .sort((a, b) => Number(a.out) - Number(b.out) || b.score - a.score || a.seat - b.seat);
}

/** Game over's title. */
export function purrOverTitle(room: RoomView, v: PurrView): string {
  if (v.winners.length === 1) return `${seatName(room.seats[v.winners[0]!])} wins`;
  return v.winners.length > 1 ? "A tie" : "Game over";
}

/** The code a phone types: the room code and the key's first letters, spaced as the TV shows it. */
export const spacedCode = (code: string, roomCode: string): string => (code.startsWith(roomCode) ? `${roomCode} ${code.slice(roomCode.length)}` : code);

/** The TV's join QR: the easel link, not an invite (`/e/`, design §5.2). */
export const easelLink = (origin: string, code: string, key: string): string => `${origin}/e/${code}?near=${encodeURIComponent(key)}`;

/** The shown view folded forward by an event, for timing only: the snapshot that follows replaces it. */
export function foldPurr(v0: PurrView, e: PurrEvent): PurrView {
  const v: PurrView = { ...v0, remainingMs: null };
  delete v.choices;
  delete v.word;
  delete v.youDraw;
  switch (e.type) {
    case "turn":
      return { ...v, phase: "choosing", drawer: e.drawer, round: e.round, group: null, level: null };
    case "chosen":
      return { ...v, phase: "drawing", drawer: e.drawer, group: e.group, level: e.level };
    case "guessed": {
      const scores = [...v.scores];
      scores[e.drawer] = (scores[e.drawer] ?? 0) + e.points;
      scores[e.guesser] = (scores[e.guesser] ?? 0) + e.points;
      return { ...v, phase: "reveal", scores, last: { word: e.word, guesser: e.guesser, points: e.points } };
    }
    case "missed":
      return { ...v, phase: "reveal", last: { word: e.word, guesser: null, points: 0 } };
    case "over":
      return { ...v, phase: "over", drawer: null, winners: [...e.winners], scores: [...e.scores] };
    default:
      return v;
  }
}
