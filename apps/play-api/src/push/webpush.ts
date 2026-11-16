/**
 * Web Push for the web player (web player design, "Web Push"): the same alerts as APNs, sent to
 * a browser's push service. The payload is encrypted for the browser alone (RFC 8291,
 * `aes128gcm`), so the push service carries it without being able to read it, and every request
 * is signed with our VAPID key (RFC 8292). All of it with WebCrypto; no library.
 *
 * Off until both VAPID keys exist (`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`: made by
 * scripts/vapid-keys.mjs). Without them the web player never asks to notify.
 */

export type WebPushEnv = { VAPID_PUBLIC_KEY?: string; VAPID_PRIVATE_KEY?: string };

/** A browser's push subscription, as `PushSubscription.toJSON()` gives it. */
export type WebPushSubscription = { endpoint: string; keys: { p256dh: string; auth: string } };

/** What the service worker shows. */
export type WebPushMessage = { title: string; body: string; code?: string; kind?: string; tag?: string };

const encoder = new TextEncoder();
/** Who to contact about our pushes, for the push services: our site, never an address. */
const SUBJECT = "https://play.conleychaos.com";
const JWT_SECONDS = 12 * 60 * 60;
const RECORD_SIZE = 4096;
const MAX_ENDPOINT = 1024;
/** The push services of Chrome and Android, Firefox, Safari and Edge. Nothing else is sent to. */
const PUSH_HOSTS = [/^fcm\.googleapis\.com$/, /^updates\.push\.services\.mozilla\.com$/, /^web\.push\.apple\.com$/, /^[a-z0-9-]+\.notify\.windows\.com$/];
const B64URL = /^[A-Za-z0-9_-]+$/;

export function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const concat = (...parts: Uint8Array[]): Uint8Array<ArrayBuffer> => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
};

export const webPushOn = (env: WebPushEnv): boolean => Boolean(env.VAPID_PUBLIC_KEY && env.VAPID_PRIVATE_KEY);

/** A subscription off the wire, or null: an endpoint at a known push service, and keys of the right sizes. */
export function parseSubscription(body: unknown): WebPushSubscription | null {
  if (typeof body !== "object" || body === null) return null;
  const { endpoint, keys } = body as { endpoint?: unknown; keys?: unknown };
  if (Object.keys(body).some((k) => k !== "endpoint" && k !== "keys" && k !== "expirationTime")) return null;
  if (typeof endpoint !== "string" || endpoint.length > MAX_ENDPOINT) return null;
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || !PUSH_HOSTS.some((h) => h.test(url.hostname))) return null;
  if (typeof keys !== "object" || keys === null) return null;
  const { p256dh, auth } = keys as { p256dh?: unknown; auth?: unknown };
  if (typeof p256dh !== "string" || typeof auth !== "string" || !B64URL.test(p256dh) || !B64URL.test(auth)) return null;
  try {
    if (fromBase64url(p256dh).length !== 65 || fromBase64url(auth).length !== 16) return null;
  } catch {
    return null;
  }
  return { endpoint, keys: { p256dh, auth } };
}

async function hmac(key: Uint8Array<ArrayBuffer>, data: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
}

/** HKDF (RFC 5869) with one block of output, which is all RFC 8291 needs. */
async function hkdf(salt: Uint8Array<ArrayBuffer>, ikm: Uint8Array<ArrayBuffer>, info: Uint8Array<ArrayBuffer>, length: number): Promise<Uint8Array<ArrayBuffer>> {
  const prk = await hmac(salt, ikm);
  return (await hmac(prk, concat(info, new Uint8Array([1])))).slice(0, length);
}

/**
 * Encrypts `plaintext` for one subscription (RFC 8291, one `aes128gcm` record). `ephemeral` and
 * `salt` are made fresh for every push; tests pass their own.
 */
export async function encrypt(
  sub: WebPushSubscription,
  plaintext: Uint8Array<ArrayBuffer>,
  ephemeral?: CryptoKeyPair,
  salt: Uint8Array<ArrayBuffer> = crypto.getRandomValues(new Uint8Array(16)),
): Promise<Uint8Array<ArrayBuffer>> {
  const pair = ephemeral ?? ((await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"])) as CryptoKeyPair);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const uaPublic = fromBase64url(sub.keys.p256dh);
  const auth = fromBase64url(sub.keys.auth);
  const ua = await crypto.subtle.importKey("raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: ua }, pair.privateKey, 256));
  const ikm = await hkdf(auth, shared, concat(encoder.encode("WebPush: info\0"), uaPublic, asPublic), 32);
  const cek = await hkdf(salt, ikm, encoder.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, encoder.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  // One record: the payload and its delimiter (2: the last record), no padding.
  const record = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, concat(plaintext, new Uint8Array([2]))));
  const header = new Uint8Array(21 + asPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, RECORD_SIZE);
  header[20] = asPublic.length;
  header.set(asPublic, 21);
  return concat(header, record);
}

/** Our VAPID private key, from its JWK parts: `d` (the secret) and the public key's x and y. */
async function vapidKey(env: Required<WebPushEnv>): Promise<CryptoKey> {
  const pub = fromBase64url(env.VAPID_PUBLIC_KEY);
  const jwk = { kty: "EC", crv: "P-256", d: env.VAPID_PRIVATE_KEY, x: base64url(pub.slice(1, 33)), y: base64url(pub.slice(33, 65)), ext: false };
  return crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** `vapid t=<JWT>, k=<public key>` for the push service at `endpoint` (RFC 8292). */
export async function vapidAuthorization(env: Required<WebPushEnv>, endpoint: string, nowSec: number): Promise<string> {
  const header = base64url(encoder.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const claims = base64url(encoder.encode(JSON.stringify({ aud: new URL(endpoint).origin, exp: nowSec + JWT_SECONDS, sub: SUBJECT })));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await vapidKey(env), encoder.encode(`${header}.${claims}`)));
  return `vapid t=${header}.${claims}.${base64url(signature)}, k=${env.VAPID_PUBLIC_KEY}`;
}

/** The message for one APNs alert body (`apnsBody`): its title and text, and which table. */
export function webMessage(body: Record<string, unknown>, collapseId: string): WebPushMessage | null {
  const aps = body.aps as { alert?: { title?: unknown; body?: unknown } } | undefined;
  const title = aps?.alert?.title;
  const text = aps?.alert?.body;
  if (typeof title !== "string" || typeof text !== "string") return null;
  return {
    title,
    body: text,
    ...(typeof body.code === "string" ? { code: body.code } : {}),
    ...(typeof body.kind === "string" ? { kind: body.kind } : {}),
    tag: collapseId,
  };
}

/**
 * Sends one message to one subscription. `unregistered`: the push service says the
 * subscription is gone (404, 410), so the device forgets it. Never throws.
 */
export async function sendWebPush(
  env: WebPushEnv,
  sub: WebPushSubscription | null,
  message: WebPushMessage,
  urgent: boolean,
  fetcher: typeof fetch = fetch,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: boolean; unregistered: boolean }> {
  if (!sub || !webPushOn(env)) return { sent: false, unregistered: false };
  try {
    const body = await encrypt(sub, encoder.encode(JSON.stringify(message)));
    const res = await fetcher(sub.endpoint, {
      method: "POST",
      headers: {
        authorization: await vapidAuthorization(env as Required<WebPushEnv>, sub.endpoint, nowSec),
        "content-encoding": "aes128gcm",
        "content-type": "application/octet-stream",
        ttl: "86400",
        urgency: urgent ? "high" : "normal",
        // One at a time per table: a newer push replaces one not yet delivered.
        ...(message.tag ? { topic: base64url(encoder.encode(message.tag)).slice(0, 32) } : {}),
      },
      body,
    });
    if (res.status === 404 || res.status === 410) return { sent: false, unregistered: true };
    return { sent: res.status >= 200 && res.status < 300, unregistered: false };
  } catch {
    return { sent: false, unregistered: false };
  }
}
