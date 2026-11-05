import { createHash } from "node:crypto";

import { describe, expect, test } from "vitest";

import { der64, GOOD_CHAIN, rescindBody, signJws, TEST_ROOTS } from "../../tests/appstore-fixtures";

import { APPLE_ROOTS, OID_SIGNING, OID_WWDR, parseCert, rawSignature, readNotification, verifyChain, verifyJws } from "./appstore";

const NOW = Date.now();
const BUNDLE = "com.conleychaos.play";
const bytes = (b64: string) => Uint8Array.from(Buffer.from(b64, "base64"));
const chain = (...names: string[]) => names.map(der64);

describe("the pinned root", () => {
  test("is Apple Root CA - G3 (SHA-256 63:34:3A:BF…3E:91:79), and nothing else", () => {
    expect(APPLE_ROOTS).toHaveLength(1);
    const fp = createHash("sha256").update(bytes(APPLE_ROOTS[0] as string)).digest("hex").toUpperCase();
    expect(fp).toBe("63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179");
    const root = parseCert(bytes(APPLE_ROOTS[0] as string));
    expect(new TextDecoder().decode(root.subject)).toContain("Apple Root CA - G3");
    expect(root.curve.name).toBe("P-384");
    expect(root.notAfter).toBe(Date.UTC(2039, 3, 30, 18, 19, 6));
  });
});

describe("parseCert", () => {
  test("reads the fixture chain: curves, OIDs, validity", () => {
    const leaf = parseCert(bytes(der64("leaf")));
    expect(leaf.curve.name).toBe("P-256");
    expect(leaf.hash).toBe("SHA-256");
    expect(leaf.extensions.has(OID_SIGNING)).toBe(true);
    expect(leaf.notBefore).toBeLessThanOrEqual(NOW);
    const inter = parseCert(bytes(der64("intermediate")));
    expect(inter.hash).toBe("SHA-384");
    expect(inter.extensions.has(OID_WWDR)).toBe(true);
    expect(parseCert(bytes(der64("odd-noext"))).extensions.size).toBe(0);
    // Valid past 2050: GeneralizedTime.
    expect(new Date(parseCert(bytes(der64("odd-2060"))).notAfter).getUTCFullYear()).toBeGreaterThanOrEqual(2060);
  });

  test("refuses what it doesn't expect: RSA and P-521 keys, junk, trailing bytes, bad lengths and times", () => {
    expect(() => parseCert(bytes(der64("odd-rsa")))).toThrow("key");
    expect(() => parseCert(bytes(der64("odd-p521")))).toThrow("curve");
    const good = bytes(der64("leaf"));
    expect(() => parseCert(Uint8Array.from([...good, 0]))).toThrow("trailing");
    expect(() => parseCert(Uint8Array.from([0x30]))).toThrow("short");
    expect(() => parseCert(Uint8Array.from([0x30, 0x80]))).toThrow("length");
    expect(() => parseCert(Uint8Array.from([0x30, 0x85, 1, 1, 1, 1, 1]))).toThrow("length");
    expect(() => parseCert(Uint8Array.from([0x30, 0x82, 0x01]))).toThrow("length");
    expect(() => parseCert(Uint8Array.from([0x30, 0x05, 0x00]))).toThrow("overrun");
    expect(() => parseCert(Uint8Array.from([0x31, 0x00]))).toThrow("tag");
    // Swap the leaf's signature algorithm for an unknown one (ecdsa-with-SHA512 is …04 03 04).
    const alg = Uint8Array.from([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]);
    const at = indexOf(good, alg, good.length - 120);
    const odd = Uint8Array.from(good);
    odd[at + alg.length - 1] = 0x04;
    expect(() => parseCert(odd)).toThrow("alg");
    // A UTCTime with a bad suffix, and one from the last century.
    const time = indexOf(good, Uint8Array.from([0x17, 0x0d]), 0);
    const badTime = Uint8Array.from(good);
    badTime[time + 2 + 12] = 0x58; // "X" for "Z"
    expect(() => parseCert(badTime)).toThrow("time");
    const old = Uint8Array.from(good);
    old[time + 2] = 0x39; // "9…"
    old[time + 3] = 0x39;
    expect(new Date(parseCert(old).notBefore).getUTCFullYear()).toBe(1999);
    // A validity field that isn't a time.
    const notTime = Uint8Array.from(good);
    notTime[time] = 0x04;
    expect(() => parseCert(notTime)).toThrow("validity");
  });

  test("rawSignature pads, strips the sign byte, and refuses an oversized integer", () => {
    const r = [0x00, 0x80, ...new Array(31).fill(1)];
    const s = new Array(31).fill(2);
    const der = Uint8Array.from([0x30, 2 + r.length + 2 + s.length, 0x02, r.length, ...r, 0x02, s.length, ...s]);
    const raw = rawSignature(der, 32);
    expect(raw[0]).toBe(0x80);
    expect(raw[32]).toBe(0);
    expect(raw[33]).toBe(2);
    const big = [0x7f, ...new Array(32).fill(1)];
    const bad = Uint8Array.from([0x30, 2 + big.length + 2 + s.length, 0x02, big.length, ...big, 0x02, s.length, ...s]);
    expect(() => rawSignature(bad, 32)).toThrow("integer");
  });
});

function indexOf(hay: Uint8Array, needle: Uint8Array, from: number): number {
  for (let i = from; i <= hay.length - needle.length; i++) if (needle.every((b, j) => hay[i + j] === b)) return i;
  throw new Error("not found");
}

describe("verifyChain", () => {
  test("accepts leaf, WWDR intermediate and the pinned root", async () => {
    const ok = await verifyChain(chain(...GOOD_CHAIN), TEST_ROOTS, NOW);
    expect(ok?.cert.curve.name).toBe("P-256");
  });

  test("Apple's pin refuses the fixture chain (production trusts only Apple's root)", async () => {
    expect(await verifyChain(chain(...GOOD_CHAIN), APPLE_ROOTS, NOW)).toBeNull();
  });

  test("refuses a wrong root, a missing OID, a broken signature or name, and dates outside validity", async () => {
    expect(await verifyChain(chain("leaf", "intermediate", "wrong-root"), TEST_ROOTS, NOW)).toBeNull();
    // Pinned, but it didn't sign the intermediate.
    expect(await verifyChain(chain("leaf", "intermediate", "wrong-root"), [der64("wrong-root")], NOW)).toBeNull();
    expect(await verifyChain(chain("leaf-plain", "intermediate", "root"), TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyChain(chain("leaf", "intermediate-plain", "root"), TEST_ROOTS, NOW)).toBeNull();
    // Same names, different key: the leaf's signature doesn't verify.
    expect(await verifyChain(chain("leaf", "intermediate-2", "root"), TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyChain(chain(...GOOD_CHAIN), TEST_ROOTS, Date.UTC(2099, 0))).toBeNull();
    expect(await verifyChain(chain(...GOOD_CHAIN), TEST_ROOTS, Date.UTC(2001, 0))).toBeNull();
  });

  test("refuses the wrong shape", async () => {
    expect(await verifyChain(chain("leaf", "root"), TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyChain("leaf", TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyChain([1, 2, 3], TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyChain(["!!", "??", der64("root")], TEST_ROOTS, NOW)).toBeNull();
  });
});

describe("verifyJws", () => {
  test("a fixture-signed ES256 JWS gives its payload", async () => {
    expect(await verifyJws(await signJws({ hello: "cats" }), TEST_ROOTS, NOW)).toEqual({ hello: "cats" });
  });

  test("refuses another alg, a P-384 leaf, a tampered payload, a non-object payload and junk", async () => {
    expect(await verifyJws(await signJws({ a: 1 }, { alg: "ES384" }), TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyJws(await signJws({ a: 1 }, { key: "leaf-p384", chain: ["leaf-p384", "intermediate", "root"] }), TEST_ROOTS, NOW)).toBeNull();
    const [h, , s] = (await signJws({ a: 1 })).split(".");
    const forged = `${h}.${Buffer.from(JSON.stringify({ a: 2 })).toString("base64url")}.${s}`;
    expect(await verifyJws(forged, TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyJws(await signJws([1, 2]), TEST_ROOTS, NOW)).toBeNull();
    const notObject = `${Buffer.from("[1]").toString("base64url")}.e30.AA`;
    expect(await verifyJws(notObject, TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyJws("a.b", TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyJws("%%%.%%%.%%%", TEST_ROOTS, NOW)).toBeNull();
    expect(await verifyJws(42, TEST_ROOTS, NOW)).toBeNull();
  });
});

describe("readNotification (RESCIND_CONSENT)", () => {
  test("gives the app transaction id", async () => {
    expect(await readNotification(await rescindBody("tx-123"), BUNDLE, TEST_ROOTS, NOW)).toEqual({ rescind: "tx-123" });
    expect(await readNotification(await rescindBody("tx-9", { environment: "Sandbox" }), BUNDLE, TEST_ROOTS, NOW)).toEqual({ rescind: "tx-9" });
  });

  test("any other verified notification is ignored", async () => {
    expect(await readNotification(await rescindBody("tx", { type: "TEST" }), BUNDLE, TEST_ROOTS, NOW)).toEqual({ ignored: true });
  });

  test("refuses another app, another environment, a bad inner JWS, an empty id, and unverified bodies", async () => {
    expect(await readNotification(await rescindBody("tx", { bundleId: "com.other" }), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    expect(await readNotification(await rescindBody("tx", { environment: "Xcode" }), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    expect(await readNotification(await rescindBody("tx", { inner: "nope" }), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    const otherApp = await signJws({ appTransactionId: "tx", bundleId: "com.other" });
    expect(await readNotification(await rescindBody("tx", { inner: otherApp }), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    expect(await readNotification(await rescindBody(""), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    const noId = await signJws({ bundleId: BUNDLE });
    expect(await readNotification(await rescindBody("tx", { inner: noId }), BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    const noApp = await signJws({ notificationType: "RESCIND_CONSENT" });
    expect(await readNotification({ signedPayload: noApp }, BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    expect(await readNotification(await rescindBody("tx"), BUNDLE, APPLE_ROOTS, NOW)).toBeNull();
    expect(await readNotification({ signedPayload: "x.y.z" }, BUNDLE, TEST_ROOTS, NOW)).toBeNull();
    expect(await readNotification("body", BUNDLE, TEST_ROOTS, NOW)).toBeNull();
  });
});
