import { describe, expect, test } from "vitest";

import { base64url, encrypt, fromBase64url, parseSubscription, sendWebPush, vapidAuthorization, webMessage, webPushOn, type WebPushSubscription } from "./webpush";

const enc = new TextEncoder();

async function hmac(key: Uint8Array<ArrayBuffer>, data: Uint8Array<ArrayBuffer>) {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
}
async function hkdf(salt: Uint8Array<ArrayBuffer>, ikm: Uint8Array<ArrayBuffer>, info: Uint8Array<ArrayBuffer>, n: number) {
  const prk = await hmac(salt, ikm);
  const withOne = new Uint8Array(info.length + 1);
  withOne.set(info);
  withOne[info.length] = 1;
  return (await hmac(prk, withOne)).slice(0, n);
}

/** A browser: its key pair and auth secret, and a subscription the server would get. */
async function browser() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"])) as CryptoKeyPair;
  const pub = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const auth = crypto.getRandomValues(new Uint8Array(16));
  const sub: WebPushSubscription = { endpoint: "https://fcm.googleapis.com/fcm/send/abc123", keys: { p256dh: base64url(pub), auth: base64url(auth) } };
  return { pair, pub, auth, sub };
}

/** What the browser does with a push (RFC 8291, receiving side). */
async function decrypt(b: Awaited<ReturnType<typeof browser>>, body: Uint8Array<ArrayBuffer>): Promise<string> {
  const salt = body.slice(0, 16);
  const rs = new DataView(body.buffer, body.byteOffset).getUint32(16);
  expect(rs).toBe(4096);
  const idlen = body[20] as number;
  const asPublic = body.slice(21, 21 + idlen);
  const record = body.slice(21 + idlen);
  const as = await crypto.subtle.importKey("raw", asPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: as }, b.pair.privateKey, 256));
  const info = new Uint8Array([...enc.encode("WebPush: info\0"), ...b.pub, ...asPublic]);
  const ikm = await hkdf(b.auth, shared, info, 32);
  const cek = await hkdf(salt, ikm, enc.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, enc.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["decrypt"]);
  const plain = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: nonce }, key, record));
  expect(plain.at(-1)).toBe(2);
  return new TextDecoder().decode(plain.slice(0, -1));
}

async function vapidKeys() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pub = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  return { env: { VAPID_PUBLIC_KEY: base64url(pub), VAPID_PRIVATE_KEY: jwk.d as string }, publicKey: pair.publicKey };
}

describe("web push", () => {
  test("only the browser can read what we send it", async () => {
    const b = await browser();
    const body = await encrypt(b.sub, enc.encode('{"title":"Your move"}'));
    expect(await decrypt(b, body)).toBe('{"title":"Your move"}');
    // Another browser's keys can't.
    const other = await browser();
    await expect(decrypt(other, body)).rejects.toThrow();
  });

  test("every request is signed with our VAPID key, for that push service, by our site", async () => {
    const { env, publicKey } = await vapidKeys();
    const header = await vapidAuthorization(env, "https://fcm.googleapis.com/fcm/send/abc", 1_000_000);
    const [, jwt, k] = /^vapid t=([^,]+), k=(.+)$/.exec(header) as RegExpExecArray;
    expect(k).toBe(env.VAPID_PUBLIC_KEY);
    const [h, c, s] = (jwt as string).split(".") as [string, string, string];
    expect(JSON.parse(new TextDecoder().decode(fromBase64url(c)))).toEqual({ aud: "https://fcm.googleapis.com", exp: 1_000_000 + 43_200, sub: "https://play.conleychaos.com" });
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, fromBase64url(s), enc.encode(`${h}.${c}`))).toBe(true);
  });

  test("subscriptions: only the big browsers' push services, with keys of the right size", async () => {
    const b = await browser();
    expect(parseSubscription(b.sub)).toEqual(b.sub);
    expect(parseSubscription({ ...b.sub, expirationTime: null })).toEqual(b.sub);
    for (const endpoint of ["https://updates.push.services.mozilla.com/wpush/v2/x", "https://web.push.apple.com/x", "https://wns2-par02p.notify.windows.com/w/?token=x"]) {
      expect(parseSubscription({ ...b.sub, endpoint })?.endpoint).toBe(endpoint);
    }
    for (const endpoint of ["http://fcm.googleapis.com/x", "https://evil.example/x", "https://u:p@fcm.googleapis.com/x", "not a url", 7, "https://fcm.googleapis.com/" + "x".repeat(1100)]) {
      expect(parseSubscription({ ...b.sub, endpoint }), String(endpoint)).toBeNull();
    }
    expect(parseSubscription({ ...b.sub, keys: { p256dh: b.sub.keys.p256dh, auth: "AAAA" } })).toBeNull();
    expect(parseSubscription({ ...b.sub, keys: { p256dh: "AAAA", auth: b.sub.keys.auth } })).toBeNull();
    expect(parseSubscription({ ...b.sub, keys: { p256dh: "!!", auth: b.sub.keys.auth } })).toBeNull();
    expect(parseSubscription({ ...b.sub, keys: null })).toBeNull();
    expect(parseSubscription({ ...b.sub, extra: 1 })).toBeNull();
    expect(parseSubscription(null)).toBeNull();
  });

  test("sends to the push service; a gone subscription is forgotten; nothing without keys", async () => {
    const b = await browser();
    const { env } = await vapidKeys();
    const sent: { url: string; init: RequestInit }[] = [];
    let status = 201;
    const fetcher = (async (url: string, init: RequestInit) => {
      sent.push({ url, init });
      return new Response(null, { status });
    }) as unknown as typeof fetch;
    const message = { title: "Your move", body: "Grandma played.", code: "BCDFG", tag: "move:BCDFG" };
    expect(await sendWebPush(env, b.sub, message, true, fetcher)).toEqual({ sent: true, unregistered: false });
    const headers = sent[0]?.init.headers as Record<string, string>;
    expect(sent[0]?.url).toBe(b.sub.endpoint);
    expect(headers["content-encoding"]).toBe("aes128gcm");
    expect(headers.urgency).toBe("high");
    expect(headers.topic?.length).toBeLessThanOrEqual(32);
    expect(JSON.parse(await decrypt(b, sent[0]?.init.body as Uint8Array<ArrayBuffer>))).toEqual(message);
    status = 410;
    expect(await sendWebPush(env, b.sub, message, false, fetcher)).toEqual({ sent: false, unregistered: true });
    status = 500;
    expect(await sendWebPush(env, b.sub, message, false, fetcher)).toEqual({ sent: false, unregistered: false });
    expect(await sendWebPush({}, b.sub, message, false, fetcher)).toEqual({ sent: false, unregistered: false });
    expect(await sendWebPush(env, null, message, false, fetcher)).toEqual({ sent: false, unregistered: false });
    const failing = (async () => {
      throw new Error("down");
    }) as unknown as typeof fetch;
    expect(await sendWebPush(env, b.sub, message, false, failing)).toEqual({ sent: false, unregistered: false });
    expect(webPushOn(env)).toBe(true);
    expect(webPushOn({ VAPID_PUBLIC_KEY: "x" })).toBe(false);
  });

  test("a web message is the alert's title and text, and which table", () => {
    expect(webMessage({ aps: { alert: { title: "The Sleepy Sardines", body: "Your move." } }, code: "BCDFG", kind: "your_move" }, "move:BCDFG")).toEqual({
      title: "The Sleepy Sardines",
      body: "Your move.",
      code: "BCDFG",
      kind: "your_move",
      tag: "move:BCDFG",
    });
    expect(webMessage({ aps: { alert: { title: "Hi" } } }, "x")).toBeNull();
    expect(webMessage({}, "x")).toBeNull();
    expect(webMessage({ aps: { alert: { title: "A", body: "B" } } }, "t")).toEqual({ title: "A", body: "B", tag: "t" });
  });
});
