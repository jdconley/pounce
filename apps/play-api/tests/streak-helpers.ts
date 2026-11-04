import { addDays, localToInstant, type Day } from "../src/streaks/clock";
import { advance, newPair, report, type PairPerson, type PairState } from "../src/streaks/pair-core";

export const LA = "America/Los_Angeles";
export const NY = "America/New_York";
export const A = "p_aaaaaaaaaaaaaaaaaaaaaa";
export const B = "p_bbbbbbbbbbbbbbbbbbbbbb";
/** A third person at a family table: never a member of the pair under test. */
export const C = "p_cccccccccccccccccccccc";
export const D0: Day = "2026-11-02";

export const person = (id: string, zone: string | null = LA, quietStart = 22 * 60): PairPerson => ({
  id,
  name: id === A ? "JD" : "Mia",
  cat: id === A ? 1 : 2,
  zone,
  quietStart,
});

/** The instant of `hh:mm` local on `day`; past midnight runs into the next date. */
export function at(day: Day, hhmm: string, zone = LA): number {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return localToInstant(day, h * 60 + m, zone);
}

export function pairOn(day: Day = D0, people: [PairPerson, PairPerson] = [person(A), person(B)]): PairState {
  return newPair("pair_1", people, at(day, "08:00"), [1, 2, 3, 4]);
}

/** `who` completes a turn on `code`, passing the move to `next`. */
export function play(s: PairState, who: string, now: number, next: string | null, code = "ROOM1"): void {
  report(s, { code, at: now, by: who, holder: next, over: false }, now);
}

/** The move moves without a member's turn (a bot or a third person). */
export function pass(s: PairState, now: number, next: string | null, code = "ROOM1"): void {
  report(s, { code, at: now, by: null, holder: next, over: false }, now);
}

/** A at 09:00 hands to B, B at 10:00 hands back: a kept day. */
export function keepDay(s: PairState, day: Day): void {
  play(s, A, at(day, "09:00"), B);
  play(s, B, at(day, "10:00"), A);
}

export function keepDays(s: PairState, from: Day, n: number): void {
  for (let i = 0; i < n; i++) keepDay(s, addDays(from, i));
}

/** Runs everything due through the settlement of `day` (LA). */
export function settle(s: PairState, day: Day): void {
  advance(s, at(addDays(day, 1), "04:10"));
}

/**
 * A missed day: the move sits with A (A holds it all day and never plays).
 * Leaves A holding at the end.
 */
export function missDay(s: PairState, day: Day): void {
  pass(s, at(day, "04:05"), A);
}
