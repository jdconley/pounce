import { base64url, pemBody } from "../players/ids";

import type { Env } from "../env";
import type { Level } from "../notify/policy";
import type { YourTurnIntent } from "../room/core";

/** Apple rejects provider tokens older than an hour; refresh well before that. */
const JWT_TTL_SEC = 50 * 60;
const encoder = new TextEncoder();

let cachedJwt: { kid: string; iat: number; jwt: string } | null = null;

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
/**
 * The original "your turn" alert; a background push (`content-available`, no
 * alert) whose data sits beside `aps`; a built alert body (§12.7, sent at
 * priority 5 when passive); a WidgetKit push (§11.2); or a live table's
 * Live Activity push (§11.3).
 */
export type ApnsPayload =
  | { title: string; body: string; code: string }
  | { background: Record<string, unknown>; collapseId: string }
  | { alert: Record<string, unknown>; collapseId: string; level: Level }
  | { widget: true }
  | { live: Record<string, unknown>; priority: 5 | 10 };
export type ApnsResult = { ok: boolean; status: number; unregistered: boolean; reason: string | null };

async function apnsReason(response: Response): Promise<string | null> {
  try {
    const body = (await response.json()) as { reason?: unknown };
    return typeof body.reason === "string" ? body.reason : null;
  } catch {
    return null;
  }
}

/** Headers and JSON body for each kind of push. */
function request(cfg: ApnsConfig, payload: ApnsPayload): { headers: Record<string, string>; body: unknown } {
  const auth = { authorization: `bearer ${cfg.jwt}` };
  if ("widget" in payload) {
    return {
      headers: { ...auth, "apns-topic": `${cfg.topic}.push-type.widgets`, "apns-push-type": "widgets", "apns-priority": "5" },
      body: { aps: { "content-changed": true } },
    };
  }
  if ("live" in payload) {
    return {
      headers: {
        ...auth,
        "apns-topic": `${cfg.topic}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": String(payload.priority),
      },
      body: payload.live,
    };
  }
  if ("alert" in payload) {
    return {
      headers: {
        ...auth,
        "apns-topic": cfg.topic,
        "apns-push-type": "alert",
        "apns-priority": payload.level === "active" ? "10" : "5",
        "apns-collapse-id": payload.collapseId,
      },
      body: payload.alert,
    };
  }
  const background = "background" in payload;
  return {
    headers: {
      ...auth,
      "apns-topic": cfg.topic,
      "apns-push-type": background ? "background" : "alert",
      // Apple requires priority 5 for background pushes.
      "apns-priority": background ? "5" : "10",
      "apns-collapse-id": background ? payload.collapseId : payload.code,
    },
    body: background
      ? { aps: { "content-available": 1 }, ...payload.background }
      : {
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: "default",
            "thread-id": payload.code,
          },
          code: payload.code,
        },
  };
}

export async function sendApns(
  fetcher: typeof fetch,
  cfg: ApnsConfig,
  deviceToken: string,
  payload: ApnsPayload,
): Promise<ApnsResult> {
  const { headers, body } = request(cfg, payload);
  const response = await fetcher(`https://${cfg.host}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (response.ok) return { ok: true, status: response.status, unregistered: false, reason: null };

  const reason = await apnsReason(response);
  const unregistered = response.status === 410 || (response.status === 400 && reason === "BadDeviceToken");
  return { ok: false, status: response.status, unregistered, reason };
}

/**
 * Sends one push. Does nothing without a device token or the APNs secrets.
 * `unregistered` tells the caller to forget the token. Neither the token nor
 * the key is ever logged.
 */
async function deliver(
  env: Env,
  deviceToken: string | null,
  payload: ApnsPayload,
  fetcher: typeof fetch,
  nowSec: number,
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
    const result = await sendApns(fetcher, { host: env.APNS_HOST, topic: env.APNS_TOPIC, jwt }, deviceToken, payload);
    if (!result.ok) console.error("apns_push_failed", result.status, result.reason);
    return { sent: result.ok, unregistered: result.unregistered };
  } catch {
    // The error text could echo the request URL, which carries the token.
    console.error("apns_push_failed", "network_error");
    return none;
  }
}

/** Pushes "your turn" to one device. */
export function pushYourTurn(
  env: Env,
  deviceToken: string | null,
  intent: YourTurnIntent,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  return deliver(
    env,
    deviceToken,
    { title: intent.personName, body: `Your turn at ${intent.tableName}`, code: intent.code },
    fetcher,
    nowSec,
  );
}

/** Tells one device to clear a table's delivered notifications: the player took the turn elsewhere (§12.5). */
export function pushDismiss(
  env: Env,
  deviceToken: string | null,
  code: string,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  return deliver(env, deviceToken, { background: { kind: "dismiss", code }, collapseId: `dismiss:${code}` }, fetcher, nowSec);
}

/** Sends a built alert body (§12.7) to one device. */
export function pushAlert(
  env: Env,
  deviceToken: string | null,
  body: Record<string, unknown>,
  collapseId: string,
  level: Level,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  return deliver(env, deviceToken, { alert: body, collapseId, level }, fetcher, nowSec);
}

/** Tells one device's widgets to reload (§11.2). The push carries no data. */
export function pushWidget(
  env: Env,
  widgetToken: string | null,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  return deliver(env, widgetToken, { widget: true }, fetcher, nowSec);
}

/** A live table's start, update or end (§11.3), to a push-to-start or an activity's update token. */
export function pushLive(
  env: Env,
  token: string | null,
  body: Record<string, unknown>,
  priority: 5 | 10,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  return deliver(env, token, { live: body, priority }, fetcher, nowSec);
}
