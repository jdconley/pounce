/**
 * Sniff's wire shapes. Client-safe: the web player imports this file, so it never imports the
 * answers or the module.
 */

/** A letter's mark: right spot (a filled paw), elsewhere in the word (an outlined paw), or not in it (plain). */
export type Mark = "spot" | "near" | "none";

/** A guess and its marks, as the server worked them out. */
export type Guess = { word: string; marks: Mark[] };

/** The one move: a guess, lowercase a to z, five letters. */
export type SniffMove = { k: "guess"; word: string };

/** What start returns as the puzzle: no answer, only its size. */
export type SniffPublic = { letters: 5; tries: 6 };

/** A run's state as a resuming client or a watching TV sees it. The answer only once it ended. */
export type SniffView = { guesses: Guess[]; answer?: string };

/** A guess's reveal: its marks, and the answer when that guess ended the run. */
export type SniffReveal = Guess & { answer?: string };

export const LETTERS = 5;
export const TRIES = 6;
