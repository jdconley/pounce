import { describe, expect, it } from "vitest";

import { issueDeviceToken, verifyDeviceToken } from "./auth";

const SECRET = "test-secret";
const DEVICE = "abcdEFGH_-123456";

describe("device tokens", () => {
  it("token round-trips", async () => {
    const token = await issueDeviceToken(SECRET, DEVICE);
    expect(token).toMatch(/^v1\.abcdEFGH_-123456\.[A-Za-z0-9_-]{43}$/);
    expect(await verifyDeviceToken(SECRET, token)).toBe(DEVICE);
  });

  it("tampered token -> null", async () => {
    const token = await issueDeviceToken(SECRET, DEVICE);
    const [v, , mac] = token.split(".");
    const otherDevice = `${v}.abcdEFGH_-123457.${mac}`;
    expect(await verifyDeviceToken(SECRET, otherDevice)).toBeNull();
    const flipped = token.slice(0, -1) + (token.endsWith("A") ? "B" : "A");
    expect(await verifyDeviceToken(SECRET, flipped)).toBeNull();
    expect(await verifyDeviceToken(SECRET, token.replace("v1.", "v2."))).toBeNull();
  });

  it("token signed with other secret -> null", async () => {
    const token = await issueDeviceToken("other-secret", DEVICE);
    expect(await verifyDeviceToken(SECRET, token)).toBeNull();
  });

  it("malformed input -> null and never throws", async () => {
    const good = await issueDeviceToken(SECRET, DEVICE);
    const mac = good.split(".")[2] as string;
    const bad = [
      "",
      "garbage",
      "v1.",
      "v1..",
      `v1.${DEVICE}`,
      `v1.${DEVICE}.`,
      `v1.${DEVICE}.${mac}.extra`,
      `v1.short.${mac}`,
      `v1.${"a".repeat(65)}.${mac}`,
      `v1.has space 1234567.${mac}`,
      `v1.${DEVICE}.not base64!`,
      `v1.${DEVICE}.a`, // decodes (length 1 is invalid base64)
      `v1.${DEVICE}.${mac.slice(0, 20)}`, // short signature
      undefined as unknown as string,
      42 as unknown as string,
    ];
    for (const token of bad) expect(await verifyDeviceToken(SECRET, token)).toBeNull();
  });

  it("returns null instead of throwing when the key cannot be imported", async () => {
    const token = await issueDeviceToken(SECRET, DEVICE);
    // WebCrypto rejects zero-length HMAC keys.
    expect(await verifyDeviceToken("", token)).toBeNull();
  });
});
