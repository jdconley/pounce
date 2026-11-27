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

const NEAR_KEY_LENGTH = 8;
/** A typed near code is the room code and this many of the key's first characters: 8 in all. */
const NEAR_TYPED_EXTRA = NEAR_KEY_LENGTH - ROOM_CODE_LENGTH;

/** A well-formed near key, or typed near code: 8 characters from the alphabet (Purrtrait, design §5.2). */
export const NEAR = new RegExp(`^[${ROOM_CODE_ALPHABET}]{${NEAR_KEY_LENGTH}}$`);

/** A near key or typed near code as a query gave it, in any case: upper-cased, or null when it is no such thing. */
export function parseNear(raw: string | null | undefined): string | null {
  const near = raw?.toUpperCase() ?? null;
  return near !== null && NEAR.test(near) ? near : null;
}

/** An 8-character near key: what a Purrtrait TV's QR carries, changed every 30 seconds. */
export function newNearKey(rng: Rng): string {
  return randomCode(rng, NEAR_KEY_LENGTH);
}

/** What a phone types in place of the QR: the room code, then the key's first characters. */
export function typedNear(code: string, key: string): string {
  return `${code}${key.slice(0, NEAR_TYPED_EXTRA)}`;
}
