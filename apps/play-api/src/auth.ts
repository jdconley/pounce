const DEVICE_ID = /^[A-Za-z0-9_-]{16,64}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;
const encoder = new TextEncoder();

function toBase64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> | null {
  if (!BASE64URL.test(text)) return null;
  try {
    const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

function hmacKey(secret: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [usage],
  );
}

/** `v1.<deviceId>.<base64url HMAC-SHA256 of "v1.<deviceId>">`. */
export async function issueDeviceToken(
  secret: string,
  deviceId: string,
): Promise<string> {
  const body = `v1.${deviceId}`;
  const mac = await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), encoder.encode(body));
  return `${body}.${toBase64Url(new Uint8Array(mac))}`;
}

/** Returns the device id for a genuine token, otherwise null. Never throws. */
export async function verifyDeviceToken(
  secret: string,
  token: string,
): Promise<string | null> {
  try {
    if (typeof token !== "string") return null;
    const parts = token.split(".");
    if (parts.length !== 3 || parts[0] !== "v1") return null;
    const [, deviceId, mac] = parts as [string, string, string];
    if (!DEVICE_ID.test(deviceId)) return null;
    const sig = fromBase64Url(mac);
    if (!sig) return null;
    // crypto.subtle.verify compares in constant time.
    const ok = await crypto.subtle.verify(
      "HMAC",
      await hmacKey(secret, "verify"),
      sig,
      encoder.encode(`v1.${deviceId}`),
    );
    return ok ? deviceId : null;
  } catch {
    return null;
  }
}
