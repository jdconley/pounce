import { base64url, pemBody, sha256Hex } from "./ids";

import type { Env } from "../env";

export type AppleProof = { identityToken: string; nonce: string; authorizationCode?: string };

const APPLE = "https://appleid.apple.com";
const KEYS_URL = `${APPLE}/auth/keys`;
const KEYS_TTL_SEC = 60 * 60;
/** An unknown `kid` refetches Apple's keys, but no more often than this. */
const KEYS_REFETCH_SEC = 60;
const CLOCK_SKEW_SEC = 60;
const CLIENT_SECRET_TTL_SEC = 300;
const MAX_TOKEN_CHARS = 4096;
const encoder = new TextEncoder();

let keyCache: { fetchedAt: number; keys: Map<string, CryptoKey> } | null = null;

export function resetAppleKeyCache(): void {
  keyCache = null;
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const isText = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= MAX_TOKEN_CHARS;

export function parseAppleProof(proof: unknown): AppleProof | null {
  if (!isObj(proof)) return null;
  const { identityToken, nonce, authorizationCode } = proof;
  if (Object.keys(proof).some((k) => !["identityToken", "nonce", "authorizationCode"].includes(k))) return null;
  if (!isText(identityToken) || !isText(nonce)) return null;
  if ("authorizationCode" in proof && !isText(authorizationCode)) return null;
  return { identityToken, nonce, ...(isText(authorizationCode) ? { authorizationCode } : {}) };
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const decodeJson = (part: string): unknown => JSON.parse(new TextDecoder().decode(fromBase64Url(part)));

async function fetchKeys(fetcher: typeof fetch, nowSec: number): Promise<Map<string, CryptoKey>> {
  const response = await fetcher(KEYS_URL);
  if (!response.ok) throw new Error(`apple_keys_${response.status}`);
  const body = (await response.json()) as { keys?: (JsonWebKey & { kid?: string })[] };
  const keys = new Map<string, CryptoKey>();
  for (const jwk of body.keys ?? []) {
    if (jwk.kty !== "RSA" || typeof jwk.kid !== "string") continue;
    const { kid, ...rest } = jwk;
    keys.set(
      kid,
      await crypto.subtle.importKey("jwk", { ...rest, alg: "RS256", ext: true }, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, [
        "verify",
      ]),
    );
  }
  keyCache = { fetchedAt: nowSec, keys };
  return keys;
}

async function appleKey(kid: string, fetcher: typeof fetch, nowSec: number): Promise<CryptoKey | null> {
  const fresh = keyCache && nowSec - keyCache.fetchedAt < KEYS_TTL_SEC;
  const cached = fresh ? keyCache?.keys.get(kid) : undefined;
  if (cached) return cached;
  if (fresh && keyCache && nowSec - keyCache.fetchedAt < KEYS_REFETCH_SEC) return null;
  return (await fetchKeys(fetcher, nowSec)).get(kid) ?? null;
}

/**
 * Checks a Sign in with Apple identity token: RS256 against Apple's key for
 * its `kid`, then issuer, audience, expiry and the nonce (the claim is the
 * SHA-256 hex of the raw nonce the app made). Never throws.
 */
export async function verifyAppleToken(
  token: string,
  opts: { clientId: string; nonce: string; nowSec: number; fetcher: typeof fetch },
): Promise<{ sub: string; exp: number; nonce: string } | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const [h, p, s] = parts as [string, string, string];
    const header = decodeJson(h) as Obj;
    if (header.alg !== "RS256" || typeof header.kid !== "string") return null;
    const key = await appleKey(header.kid, opts.fetcher, opts.nowSec);
    if (!key) return null;
    const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, fromBase64Url(s), encoder.encode(`${h}.${p}`));
    if (!ok) return null;
    const claims = decodeJson(p) as Obj;
    const { iss, aud, exp, iat, sub, nonce } = claims;
    if (iss !== APPLE || aud !== opts.clientId) return null;
    if (typeof exp !== "number" || exp <= opts.nowSec) return null;
    if (typeof iat !== "number" || iat > opts.nowSec + CLOCK_SKEW_SEC) return null;
    if (typeof sub !== "string" || sub.length === 0) return null;
    if (typeof nonce !== "string" || nonce !== (await sha256Hex(opts.nonce))) return null;
    return { sub, exp, nonce };
  } catch {
    return null;
  }
}

const encodeJson = (value: unknown): string => base64url(encoder.encode(JSON.stringify(value)));

/** The ES256 client secret Apple's token and revoke endpoints take. */
export async function appleClientSecret(
  p8: string,
  keyId: string,
  teamId: string,
  clientId: string,
  nowSec: number,
): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemBody(p8), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${encodeJson({ alg: "ES256", kid: keyId })}.${encodeJson({
    iss: teamId,
    iat: nowSec,
    exp: nowSec + CLIENT_SECRET_TTL_SEC,
    aud: APPLE,
    sub: clientId,
  })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

async function postForm(env: Env, path: string, fields: Record<string, string>, fetcher: typeof fetch, nowSec: number) {
  const secret = await appleClientSecret(env.SIWA_KEY_P8 as string, env.SIWA_KEY_ID as string, env.APNS_TEAM_ID, env.SIWA_CLIENT_ID, nowSec);
  return fetcher(`${APPLE}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.SIWA_CLIENT_ID, client_secret: secret, ...fields }).toString(),
  });
}

const hasKey = (env: Env) => Boolean(env.SIWA_KEY_P8 && env.SIWA_KEY_ID);

/** The refresh token for a sign-in's authorization code, kept only to revoke it. Null without the key. */
export async function exchangeAppleCode(env: Env, code: string, fetcher: typeof fetch, nowSec: number): Promise<string | null> {
  if (!hasKey(env)) return null;
  try {
    const response = await postForm(env, "/auth/token", { grant_type: "authorization_code", code }, fetcher, nowSec);
    if (!response.ok) {
      console.error("siwa_exchange_failed", response.status);
      return null;
    }
    const body = (await response.json()) as { refresh_token?: unknown };
    return typeof body.refresh_token === "string" ? body.refresh_token : null;
  } catch {
    console.error("siwa_exchange_failed", "network_error");
    return null;
  }
}

/** Best effort: Apple's revoke, on unlink and account deletion. Does nothing without the key. */
export async function revokeAppleToken(env: Env, refreshToken: string, fetcher: typeof fetch, nowSec: number): Promise<void> {
  if (!hasKey(env)) return;
  try {
    const response = await postForm(env, "/auth/revoke", { token: refreshToken, token_type_hint: "refresh_token" }, fetcher, nowSec);
    if (!response.ok) console.error("siwa_revoke_failed", response.status);
  } catch {
    console.error("siwa_revoke_failed", "network_error");
  }
}
