/**
 * App Store Server Notifications V2 (consent design §1, D5; plan decisions
 * 28–30): verifies a JWS whose `x5c` chain ends in the pinned Apple Root CA -
 * G3, and reads `RESCIND_CONSENT`'s app transaction. A minimal DER reader
 * covers exactly the X.509 fields the check needs; anything unexpected fails.
 */

/** Apple Root CA - G3, DER, as on apple.com/certificateauthority (SHA-256 63:34:3A:BF:…:3E:91:79). */
const APPLE_ROOT_CA_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQL" +
  "DB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMw" +
  "MTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRp" +
  "ZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA" +
  "BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqX" +
  "l5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8w" +
  "DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWT" +
  "xnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

/** The roots production trusts: only Apple's. Tests pass their own fixture root. */
export const APPLE_ROOTS: readonly string[] = [APPLE_ROOT_CA_G3];

/** Apple Worldwide Developer Relations, on the intermediate. */
export const OID_WWDR = "1.2.840.113635.100.6.2.1";
/** The App Store's signing certificate (Mac App Store receipt signing), on the leaf. */
export const OID_SIGNING = "1.2.840.113635.100.6.11.1";
const OID_EC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, { name: "P-256" | "P-384"; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const HASHES: Record<string, "SHA-256" | "SHA-384"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

const SEQUENCE = 0x30;
const INTEGER = 0x02;
const BIT_STRING = 0x03;
const OID = 0x06;
const UTC_TIME = 0x17;
const GENERALIZED_TIME = 0x18;
const EXPLICIT_0 = 0xa0;
const EXPLICIT_3 = 0xa3;

type Tlv = { tag: number; start: number; body: number; end: number };

class DerError extends Error {}

/** One tag-length-value at `pos`. Definite lengths only, up to 4 length bytes. */
function tlv(b: Uint8Array, pos: number, limit = b.length): Tlv {
  if (pos + 2 > limit) throw new DerError("short");
  const tag = b[pos] as number;
  let len = b[pos + 1] as number;
  let body = pos + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4 || body + n > limit) throw new DerError("length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + (b[body + i] as number);
    body += n;
  }
  const end = body + len;
  if (end > limit) throw new DerError("overrun");
  return { tag, start: pos, body, end };
}

function children(b: Uint8Array, parent: Tlv): Tlv[] {
  const out: Tlv[] = [];
  for (let pos = parent.body; pos < parent.end; ) {
    const t = tlv(b, pos, parent.end);
    out.push(t);
    pos = t.end;
  }
  return out;
}

function expect(t: Tlv | undefined, tag: number): Tlv {
  if (!t || t.tag !== tag) throw new DerError("tag");
  return t;
}

function oid(b: Uint8Array, t: Tlv): string {
  const bytes = b.subarray(t.body, t.end);
  const first = bytes[0] as number;
  const parts = [Math.floor(first / 40), first % 40];
  let v = 0;
  for (const byte of bytes.subarray(1)) {
    v = v * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      parts.push(v);
      v = 0;
    }
  }
  return parts.join(".");
}

function time(b: Uint8Array, t: Tlv): number {
  const s = new TextDecoder().decode(b.subarray(t.body, t.end));
  const m = (t.tag === UTC_TIME ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/ : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/).exec(s);
  if (!m) throw new DerError("time");
  const [y, mo, d, h, mi, sec] = m.slice(1).map(Number) as [number, number, number, number, number, number];
  const year = t.tag === UTC_TIME ? (y < 50 ? 2000 + y : 1900 + y) : y;
  return Date.UTC(year, mo - 1, d, h, mi, sec);
}

export type Cert = {
  der: Uint8Array;
  tbs: Uint8Array;
  hash: "SHA-256" | "SHA-384";
  signature: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: number;
  notAfter: number;
  spki: Uint8Array;
  curve: { name: "P-256" | "P-384"; size: number };
  extensions: Set<string>;
};

/** Reads the fields of an X.509 certificate that the chain check needs. Throws on anything else. */
export function parseCert(der: Uint8Array): Cert {
  const cert = expect(tlv(der, 0), SEQUENCE);
  if (cert.end !== der.length) throw new DerError("trailing");
  const [tbsT, algT, sigT] = children(der, cert);
  const tbs = expect(tbsT, SEQUENCE);
  const hash = HASHES[oid(der, expect(children(der, expect(algT, SEQUENCE))[0], OID))];
  if (!hash) throw new DerError("alg");
  const sig = expect(sigT, BIT_STRING);
  const fields = children(der, tbs);
  // v3 only (Apple's are): the explicit version comes first.
  expect(fields[0], EXPLICIT_0);
  const [, , , issuerT, validityT, subjectT, spkiT] = fields;
  const [nb, na] = children(der, expect(validityT, SEQUENCE));
  const validity = [nb, na].map((t) => {
    if (!t || (t.tag !== UTC_TIME && t.tag !== GENERALIZED_TIME)) throw new DerError("validity");
    return time(der, t);
  }) as [number, number];
  const spki = expect(spkiT, SEQUENCE);
  const [keyAlg] = children(der, spki);
  const [keyType, curveT] = children(der, expect(keyAlg, SEQUENCE));
  if (oid(der, expect(keyType, OID)) !== OID_EC_KEY) throw new DerError("key");
  const curve = CURVES[oid(der, expect(curveT, OID))];
  if (!curve) throw new DerError("curve");
  const extensions = new Set<string>();
  const extT = fields.find((f) => f.tag === EXPLICIT_3);
  if (extT) {
    for (const ext of children(der, expect(children(der, extT)[0], SEQUENCE))) {
      extensions.add(oid(der, expect(children(der, expect(ext, SEQUENCE))[0], OID)));
    }
  }
  return {
    der,
    tbs: der.subarray(tbs.start, tbs.end),
    hash,
    // A BIT STRING's first byte counts unused bits: 0 for a signature.
    signature: der.subarray(sig.body + 1, sig.end),
    issuer: der.subarray((issuerT as Tlv).start, (issuerT as Tlv).end),
    subject: der.subarray(expect(subjectT, SEQUENCE).start, (subjectT as Tlv).end),
    notBefore: validity[0],
    notAfter: validity[1],
    spki: der.subarray(spki.start, spki.end),
    curve,
    extensions,
  };
}

/** An ECDSA DER signature (SEQUENCE of two INTEGERs) as WebCrypto's raw r||s. */
export function rawSignature(der: Uint8Array, size: number): Uint8Array {
  const [r, s] = children(der, expect(tlv(der, 0), SEQUENCE));
  const out = new Uint8Array(size * 2);
  for (const [i, t] of [r, s].entries()) {
    let v = der.subarray(expect(t, INTEGER).body, (t as Tlv).end);
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new DerError("integer");
    out.set(v, i * size + size - v.length);
  }
  return out;
}

const equalBytes = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((x, i) => x === b[i]);

function fromBase64(s: string): Uint8Array<ArrayBuffer> {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const fromBase64url = (s: string) => fromBase64(s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "="));

const copy = (b: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(b);

function importKey(c: Cert): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", copy(c.spki), { name: "ECDSA", namedCurve: c.curve.name }, false, ["verify"]);
}

async function signedBy(child: Cert, issuer: Cert): Promise<boolean> {
  if (!equalBytes(child.issuer, issuer.subject)) return false;
  const key = await importKey(issuer);
  return crypto.subtle.verify({ name: "ECDSA", hash: child.hash }, key, copy(rawSignature(child.signature, issuer.curve.size)), copy(child.tbs));
}

/**
 * The leaf's key when `x5c` is leaf, Apple WWDR intermediate, pinned root:
 * each one signs the one before, names chain, all are valid at `now`, and the
 * OIDs are where Apple puts them. Null otherwise.
 */
export async function verifyChain(x5c: unknown, roots: readonly string[], now: number): Promise<{ key: CryptoKey; cert: Cert } | null> {
  try {
    if (!Array.isArray(x5c) || x5c.length !== 3 || !x5c.every((c) => typeof c === "string")) return null;
    const ders = (x5c as string[]).map(fromBase64);
    if (!roots.some((r) => equalBytes(fromBase64(r), ders[2] as Uint8Array))) return null;
    const [leaf, inter, root] = ders.map(parseCert) as [Cert, Cert, Cert];
    if (![leaf, inter, root].every((c) => c.notBefore <= now && now <= c.notAfter)) return null;
    if (!leaf.extensions.has(OID_SIGNING) || !inter.extensions.has(OID_WWDR)) return null;
    if (!(await signedBy(leaf, inter)) || !(await signedBy(inter, root))) return null;
    return { key: await importKey(leaf), cert: leaf };
  } catch {
    return null;
  }
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);

/** A JWS signed with ES256 by the App Store: its payload, or null. */
export async function verifyJws(jws: unknown, roots: readonly string[], now: number): Promise<Obj | null> {
  try {
    if (typeof jws !== "string") return null;
    const parts = jws.split(".");
    if (parts.length !== 3) return null;
    const [h, p, s] = parts as [string, string, string];
    const header: unknown = JSON.parse(new TextDecoder().decode(fromBase64url(h)));
    if (!isObj(header) || header.alg !== "ES256") return null;
    const chain = await verifyChain(header.x5c, roots, now);
    if (!chain || chain.cert.curve.name !== "P-256") return null;
    const sig = fromBase64url(s);
    const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, chain.key, sig, new TextEncoder().encode(`${h}.${p}`));
    if (!ok) return null;
    const payload: unknown = JSON.parse(new TextDecoder().decode(fromBase64url(p)));
    return isObj(payload) ? payload : null;
  } catch {
    return null;
  }
}

const ENVIRONMENTS = ["Production", "Sandbox"];

/**
 * A notification body (`{signedPayload}`): `rescind` with the app
 * transaction id for a verified `RESCIND_CONSENT` for this app, `ignored`
 * for any other verified notification, null when it doesn't verify.
 */
export async function readNotification(
  body: unknown,
  bundleId: string,
  roots: readonly string[],
  now: number,
): Promise<{ rescind: string } | { ignored: true } | null> {
  if (!isObj(body)) return null;
  const payload = await verifyJws(body.signedPayload, roots, now);
  if (!payload) return null;
  if (payload.notificationType !== "RESCIND_CONSENT") return { ignored: true };
  const app = payload.appData;
  if (!isObj(app) || app.bundleId !== bundleId || !ENVIRONMENTS.includes(app.environment as string)) return null;
  const tx = await verifyJws(app.signedAppTransactionInfo, roots, now);
  if (!tx || tx.bundleId !== bundleId || typeof tx.appTransactionId !== "string" || tx.appTransactionId === "") return null;
  return { rescind: tx.appTransactionId };
}
