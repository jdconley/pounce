import type { Env } from "../env";
import type { PushIntent } from "../room/core";

/** Apple rejects provider tokens older than an hour; refresh well before that. */
const JWT_TTL_SEC = 50 * 60;
const encoder = new TextEncoder();

let cachedJwt: { kid: string; iat: number; jwt: string } | null = null;

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const byte of bytes) bin += String.fromCharCode(byte);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemBody(pem: string): Uint8Array<ArrayBuffer> {
  const bin = atob(pem.replace(/-----(BEGIN|END)[^-]*-----/g, "").replace(/\s+/g, ""));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const encodeJson = (value: unknown): string => base64url(encoder.encode(JSON.stringify(value)));

/**
 * An ES256 provider token for APNs. WebCrypto already signs as raw r||s, the
 * JWS form, so the signature is used as returned.
 */
export async function createApnsJwt(p8: string, keyId: string, teamId: string, nowSec: number): Promise<string> {
  if (cachedJwt && cachedJwt.kid === keyId && nowSec - cachedJwt.iat < JWT_TTL_SEC) return cachedJwt.jwt;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBody(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signingInput = `${encodeJson({ alg: "ES256", kid: keyId })}.${encodeJson({ iss: teamId, iat: nowSec })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cachedJwt = { kid: keyId, iat: nowSec, jwt };
  return jwt;
}

export type ApnsConfig = { host: string; topic: string; jwt: string };
export type ApnsPayload = { title: string; body: string; code: string };
export type ApnsResult = { ok: boolean; status: number; unregistered: boolean; reason: string | null };

async function apnsReason(response: Response): Promise<string | null> {
  try {
    const body = (await response.json()) as { reason?: unknown };
    return typeof body.reason === "string" ? body.reason : null;
  } catch {
    return null;
  }
}

export async function sendApns(
  fetcher: typeof fetch,
  cfg: ApnsConfig,
  deviceToken: string,
  payload: ApnsPayload,
): Promise<ApnsResult> {
  const response = await fetcher(`https://${cfg.host}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${cfg.jwt}`,
      "apns-topic": cfg.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": payload.code,
    },
    body: JSON.stringify({
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: "default",
        "thread-id": payload.code,
      },
      code: payload.code,
    }),
  });
  if (response.ok) return { ok: true, status: response.status, unregistered: false, reason: null };

  const reason = await apnsReason(response);
  const unregistered = response.status === 410 || (response.status === 400 && reason === "BadDeviceToken");
  return { ok: false, status: response.status, unregistered, reason };
}

/**
 * Pushes "your turn" to one device. Does nothing without a device token or the
 * APNs secrets. `unregistered` tells the caller to forget the token. Neither
 * the token nor the key is ever logged.
 */
export async function pushYourTurn(
  env: Env,
  deviceToken: string | null,
  intent: PushIntent,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  const none = { sent: false, unregistered: false };
  if (!deviceToken || !env.APNS_KEY_P8 || !env.APNS_KEY_ID) return none;

  let jwt: string;
  try {
    jwt = await createApnsJwt(env.APNS_KEY_P8, env.APNS_KEY_ID, env.APNS_TEAM_ID, nowSec);
  } catch {
    // A bad APNS_KEY_P8 is an operator fix, not an outage: name it apart. The
    // error text could echo key material, so it is not logged.
    console.error("apns_push_failed", "apns_key_invalid");
    return none;
  }

  try {
    const result = await sendApns(
      fetcher,
      { host: env.APNS_HOST, topic: env.APNS_TOPIC, jwt },
      deviceToken,
      { title: intent.personName, body: "Your turn", code: intent.code },
    );
    if (!result.ok) console.error("apns_push_failed", result.status, result.reason);
    return { sent: result.ok, unregistered: result.unregistered };
  } catch {
    // The error text could echo the request URL, which carries the token.
    console.error("apns_push_failed", "network_error");
    return none;
  }
}
