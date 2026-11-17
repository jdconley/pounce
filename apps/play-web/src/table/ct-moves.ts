/**
 * Cat Tower's moves as the table sees them, without the table: where a card can be hit, whether
 * the trays make a lay-down, who a Cucumber can skip, and how a laid group is named. Pure, so
 * the phone's full table and its controller ask the same questions and get the same answers.
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { canHit, type Group, type HitSide } from "@pounce/play-api/rules/groups";
import { matchPhase } from "@pounce/play-api/rules/phases";

import { mySeats } from "../store/lobby";

import { playing, seatName } from "./seat-names";

import type { GameAim, RoomView } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";

export type HitTarget = { seat: number; group: number; side?: HitSide };

/**
 * Every laid group `id` can be hit on, seat by seat and group by group. A run lists each end the
 * card fits (`start` before `end`); a set or a coat has no side. A seat that hasn't laid down has
 * none. Whether the hitter may hit at all (they must have laid down) is the caller's to ask.
 */
export function hitTargets(id: CardId, laid: (Group[] | null)[]): HitTarget[] {
  const out: HitTarget[] = [];
  laid.forEach((groups, seat) => {
    (groups ?? []).forEach((g, group) => {
      if (g.kind !== "run") {
        if (canHit(g, id).ok) out.push({ seat, group });
        return;
      }
      for (const side of ["start", "end"] as const) if (canHit(g, id, side).ok) out.push({ seat, group, side });
    });
  });
  return out;
}

/** The trays as the groups a lay-down sends, or null when they don't make phase `phase` (an index, 0 = phase 1). */
export function layDownGroups(trays: CardId[][], phase: number): { cards: CardId[]; runStart?: number }[] | null {
  const groups = trays.map((cards) => ({ cards }));
  return matchPhase(phase, groups) === null ? null : groups;
}

/** A Cucumber skips someone: discarding one asks whose turn it skips. */
export const discardNeedsTarget = (id: CardId): boolean => card(id).kind === "cucumber";

/**
 * The seats `seat` can skip with a Cucumber: everyone else at the table (a person or a House Cat,
 * from the room's `seats`) not already skipped and still in the game.
 */
export function skipTargets(view: CatTowerView, seat: number, seats: RoomView["seats"]): number[] {
  return view.forfeited.flatMap((out, i) => (i !== seat && playing(seats[i]) && !out && !view.pendingSkip[i] ? [i] : []));
}

/**
 * The laid group the player whose turn it is points at, mid-round, or null. Never a seat this
 * device holds: it is pointing from here.
 */
export function aimedGroup(room: RoomView, aims: Record<number, GameAim>): { seat: number; group: number } | null {
  const g = room.game;
  if (!g || g.status !== "playing" || mySeats(room).includes(g.turn)) return null;
  const aim = aims[g.turn];
  return aim && "target" in aim ? aim.target : null;
}

const COAT_WORDS: Record<string, string> = { tabby: "tabbies", tuxedo: "tuxedos", calico: "calicos", gray: "grays" };

/**
 * A laid group in a few words, for a list of where a card can go: "Mom's 3s", "Ava's run from 7",
 * "Grandpa's tabbies". The device's own seat is "Your 3s", "Your run"; a shared device (pass and
 * play) names every seat, as "your" would be anyone holding it.
 */
export function targetLabel(room: RoomView, seat: number, group: number): string {
  const own = mySeats(room);
  const yours = own.length === 1 && own[0] === seat;
  const g = room.game?.laid[seat]?.[group];
  const whose = yours ? "Your" : `${seatName(room.seats[seat])}'s`;
  if (!g) return `${whose} group`;
  if (g.kind === "set") return `${whose} ${g.value}s`;
  if (g.kind === "coat") return `${whose} ${COAT_WORDS[g.coat] ?? g.coat}`;
  return yours ? "Your run" : `${whose} run from ${g.start}`;
}
