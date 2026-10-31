import type { Rng } from "../rules/rng";

/** Consonants and digits only: no vowels (no words) and no look-alikes. */
export const ROOM_CODE_ALPHABET = "BCDFGHJKLMNPQRTVWXZ2346789";

const ROOM_CODE_LENGTH = 5;

/** A well-formed room code: exactly five characters from the alphabet. */
export const ROOM_CODE = new RegExp(`^[${ROOM_CODE_ALPHABET}]{${ROOM_CODE_LENGTH}}$`);
const MOVE_CODE_LENGTH = 6;

function randomCode(rng: Rng, length: number): string {
  let out = "";
  for (let i = 0; i < length; i++) {
    out += ROOM_CODE_ALPHABET[Math.floor(rng() * ROOM_CODE_ALPHABET.length)];
  }
  return out;
}

/** A 5-character room code. */
export function newRoomCode(rng: Rng): string {
  return randomCode(rng, ROOM_CODE_LENGTH);
}

/** A 6-character one-time code for moving a seat to another device. */
export function newMoveCode(rng: Rng): string {
  return randomCode(rng, MOVE_CODE_LENGTH);
}
