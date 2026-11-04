import { describe, expect, it } from "vitest";

import { provider } from "./providers";

import type { Env } from "../env";

describe("identity providers", () => {
  it("apple signs in, device binds through the profile, others don't exist yet", () => {
    expect(provider("apple")?.signIn).toBe(true);
    expect(provider("device")?.signIn).toBe(false);
    expect(provider("google")).toBeNull();
    expect(provider("__proto__")).toBeNull();
  });

  it("the device provider's subject is the person id", async () => {
    const id = "11111111-1111-4111-8111-111111111111";
    const env = {} as Env;
    expect(await provider("device")?.verify({ id, key: "k".repeat(43) }, env, fetch, 0)).toEqual({ subject: id });
    expect(await provider("device")?.verify({ id }, env, fetch, 0)).toBeNull();
  });

  it("apple rejects a proof that isn't one", async () => {
    expect(await provider("apple")?.verify({ nope: 1 }, { SIWA_CLIENT_ID: "x" } as Env, fetch, 0)).toBeNull();
  });

  it("apple's revoke sends the stored refresh token", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
    const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    const env = {
      SIWA_CLIENT_ID: "com.conleychaos.play",
      APNS_TEAM_ID: "T",
      SIWA_KEY_ID: "K",
      SIWA_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`,
    } as Env;
    const bodies: string[] = [];
    const fetcher = (async (_url: unknown, init?: RequestInit) => {
      bodies.push(String(init?.body));
      return new Response(null, { status: 200 });
    }) as unknown as typeof fetch;
    await provider("apple")?.revoke?.("refresh-9", env, fetcher, 1_800_000_000);
    expect(new URLSearchParams(bodies[0]).get("token")).toBe("refresh-9");
  });
});
