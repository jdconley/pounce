/**
 * Putting a table on a TV from a phone: the TV's backup code as typed, and what each answer of
 * `POST /v1/screens/link` says on screen (docs/tv-protocol.md).
 */
import { ROOM_CODE_ALPHABET } from "@pounce/play-api/protocol";

import { ApiError } from "../net/api";

/** A TV's backup code is six characters from the room-code alphabet. */
export const TV_CODE_LENGTH = 6;

/** What the field shows as it is typed: upper case, letters and digits only, six at most. */
export const typedTvCode = (raw: string): string =>
  raw
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, TV_CODE_LENGTH);

/** The code to send, or null when it can't be a TV's code (wrong length, a vowel, a 0 or 1). */
export function normaliseTvCode(raw: string): string | null {
  const code = raw.replace(/\s+/g, "").toUpperCase();
  if (code.length !== TV_CODE_LENGTH) return null;
  return [...code].every((ch) => ROOM_CODE_ALPHABET.includes(ch)) ? code : null;
}

/** The words for a link that failed (a QR's gone token is `linkExpired` instead). */
export function linkWords(error: unknown): string {
  if (!(error instanceof ApiError)) return "Couldn't reach Pounce. Try again.";
  if (error.status === 0) return "You're offline.";
  if (error.status === 404) return "No TV with that code.";
  if (error.status === 429) return "Too many wrong codes. Try again later.";
  if (error.status === 403) return "Take a seat to play.";
  if (error.status === 409 && error.code === "seated") return "This phone is at the table.";
  return "Couldn't reach Pounce. Try again.";
}

/** Why a table just made opened without the TV: its link failed after the table was made. */
export const linkFailedWords = (error: unknown): string => (linkExpired(error) ? "The TV link expired." : linkWords(error));

/** A QR's token that the server no longer knows: the page says the link expired. */
export const linkExpired = (error: unknown): boolean => error instanceof ApiError && error.status === 404;
