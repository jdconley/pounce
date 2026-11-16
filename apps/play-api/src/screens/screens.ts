/**
 * Screen links (Pounce on the TV): a TV asks for a link, shows its token as a QR and its code
 * as a backup, and a phone at a table sends either one to open that table on the TV. The pure
 * half: minting, parsing and the decision. `screen-links.ts` keeps the links.
 */
import { newMoveCode, ROOM_CODE, ROOM_CODE_ALPHABET } from "../room/codes";

import type { Rng } from "../rules/rng";

/** How long a link lives. The TV asks for a new one before then. */
export const SCREEN_LINK_TTL_MS = 600_000;

const TOKEN_BYTES = 16;

/** A well-formed link token: 128 bits, base64url, no padding. */
export const LINK_TOKEN = /^[A-Za-z0-9_-]{22}$/;
/** A well-formed backup code: six characters of the room code alphabet, upper case. */
export const LINK_CODE = new RegExp(`^[${ROOM_CODE_ALPHABET}]{6}$`);

/** The token for 16 random bytes. */
export function newLinkToken(bytes: Uint8Array): string {
  if (bytes.length !== TOKEN_BYTES) throw new RangeError("a link token is 16 bytes");
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A backup code: short enough to type off a TV across the room. */
export function newLinkCode(rng: Rng): string {
  return newMoveCode(rng);
}

/** `POST /v1/screens`: nothing, or the table the TV already shows. Null: a bad request. */
export function parseScreenBody(body: Record<string, unknown> | null): { showing: string | null } | null {
  if (!body) return null;
  const keys = Object.keys(body);
  if (keys.length === 0) return { showing: null };
  if (keys.length !== 1 || typeof body.showing !== "string" || !ROOM_CODE.test(body.showing)) return null;
  return { showing: body.showing };
}

export type LinkRest = { room: string; move: boolean };

/**
 * `POST /v1/screens/link`: exactly one of `token` or `code`, the phone's `room`, and `move` when
 * the TV may leave the table it shows. A code is read in any case. Null: a bad request.
 */
export function parseLinkBody(body: Record<string, unknown> | null): ({ token: string } & LinkRest) | ({ code: string } & LinkRest) | null {
  if (!body) return null;
  if (Object.keys(body).some((key) => key !== "token" && key !== "code" && key !== "room" && key !== "move")) return null;
  if (typeof body.room !== "string" || !ROOM_CODE.test(body.room)) return null;
  if ("move" in body && typeof body.move !== "boolean") return null;
  const rest = { room: body.room, move: body.move === true };
  if ("token" in body === "code" in body) return null;
  if ("token" in body) return typeof body.token === "string" && LINK_TOKEN.test(body.token) ? { token: body.token, ...rest } : null;
  const code = typeof body.code === "string" ? body.code.toUpperCase() : "";
  return LINK_CODE.test(code) ? { code, ...rest } : null;
}

/**
 * What a phone's link does. `gone`: no such link, or it expired or was used. `showing`: the TV
 * shows another table and the phone didn't ask to move it. `already`: the TV shows this table.
 */
export function linkDecision(
  link: { showing: string | null; spent: boolean; expires: number } | null,
  room: string,
  move: boolean,
  now: number,
): "link" | "already" | "showing" | "gone" {
  if (!link || link.expires <= now || link.spent) return "gone";
  if (link.showing === room) return "already";
  if (link.showing !== null && !move) return "showing";
  return "link";
}
