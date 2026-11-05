/** `p_` + 16 random bytes, base64url. Never derived from a provider's user id. */
export const PLAYER_ID = /^p_[A-Za-z0-9_-]{22}$/;
/** A pair's id: `pr_` + 16 random bytes, base64url (§13.2). */
export const PAIR_ID = /^pr_[A-Za-z0-9_-]{22}$/;
/** A person's id: a UUID made on the device. */
export const PERSON_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** A person's key: 32 random bytes from the device's Keychain, base64url. */
export const PERSON_KEY = /^[A-Za-z0-9_-]{43}$/;

const PLAYER_ID_BYTES = 16;
const encoder = new TextEncoder();

export function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function newPlayerId(): string {
  return `p_${base64url(crypto.getRandomValues(new Uint8Array(PLAYER_ID_BYTES)))}`;
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text)));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** What the identities index stores in place of a provider's raw user id. */
export function subjectHash(provider: string, subject: string): Promise<string> {
  return sha256Hex(`${provider}:${subject}`);
}

/** The DER bytes inside a PEM block, such as a .p8 key. */
export function pemBody(pem: string): Uint8Array<ArrayBuffer> {
  const bin = atob(pem.replace(/-----(BEGIN|END)[^-]*-----/g, "").replace(/\s+/g, ""));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}
