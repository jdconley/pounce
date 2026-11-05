/**
 * Twilio for text plus (consent design D1; plan decisions 24–26): the
 * Messages REST call, basic auth with an API key, and the `X-Twilio-Signature`
 * check on inbound webhooks, which Twilio signs with the account's Auth Token.
 * Optional like the APNs key: without all five secrets nothing is sent.
 */

export type TwilioEnv = {
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_API_KEY_SID?: string;
  TWILIO_API_KEY_SECRET?: string;
  TWILIO_MESSAGING_SERVICE_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
};

export type TwilioConfig = {
  accountSid: string;
  apiKeySid: string;
  apiKeySecret: string;
  messagingServiceSid: string;
  authToken: string;
};

/** Twilio's error for a number that replied STOP: sending to it is blocked. */
export const OPTED_OUT = 21610;
const API = "https://api.twilio.com/2010-04-01";
const encoder = new TextEncoder();

/** All five secrets, or null: consent can't start unless a STOP can end it. */
export function twilioConfig(env: TwilioEnv): TwilioConfig | null {
  const { TWILIO_ACCOUNT_SID: a, TWILIO_API_KEY_SID: k, TWILIO_API_KEY_SECRET: s, TWILIO_MESSAGING_SERVICE_SID: m, TWILIO_AUTH_TOKEN: t } = env;
  if (!a || !k || !s || !m || !t) return null;
  return { accountSid: a, apiKeySid: k, apiKeySecret: s, messagingServiceSid: m, authToken: t };
}

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

/** Twilio's request signature: HMAC-SHA1 over the URL and each field (sorted by name) appended as name then value, base64. */
export async function twilioSignature(authToken: string, url: string, params: [string, string][]): Promise<string> {
  const sorted = [...params].sort(([a, x], [b, y]) => (a < b ? -1 : a > b ? 1 : x < y ? -1 : x > y ? 1 : 0));
  const data = url + sorted.map(([k, v]) => k + v).join("");
  const key = await crypto.subtle.importKey("raw", encoder.encode(authToken), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  return b64(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(data))));
}

function sameText(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** Checks `X-Twilio-Signature` in constant time. */
export async function verifyTwilio(authToken: string, url: string, params: [string, string][], signature: string | null): Promise<boolean> {
  if (!signature) return false;
  return sameText(await twilioSignature(authToken, url, params), signature);
}

export type SendResult = { ok: true } | { ok: false; status: number; code: number | null };

/** Sends one text through the Messaging Service. Never throws. */
export async function sendText(cfg: TwilioConfig, to: string, body: string, fetcher: typeof fetch): Promise<SendResult> {
  try {
    const res = await fetcher(`${API}/Accounts/${encodeURIComponent(cfg.accountSid)}/Messages.json`, {
      method: "POST",
      headers: {
        authorization: `Basic ${btoa(`${cfg.apiKeySid}:${cfg.apiKeySecret}`)}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ To: to, MessagingServiceSid: cfg.messagingServiceSid, Body: body }).toString(),
    });
    if (res.ok) return { ok: true };
    let code: number | null = null;
    try {
      const parsed = (await res.json()) as { code?: unknown };
      code = typeof parsed.code === "number" ? parsed.code : null;
    } catch {
      code = null;
    }
    return { ok: false, status: res.status, code };
  } catch {
    return { ok: false, status: 0, code: null };
  }
}
