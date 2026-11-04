import { beforeEach, describe, expect, it } from "vitest";

import {
  appleClientSecret,
  exchangeAppleCode,
  parseAppleProof,
  resetAppleKeyCache,
  revokeAppleToken,
  verifyAppleToken,
} from "./apple";
import { base64url, sha256Hex } from "./ids";

import type { Env } from "../env";

const CLIENT_ID = "com.conleychaos.play";
const NOW = 1_800_000_000;
const encoder = new TextEncoder();
const b64json = (v: unknown) => base64url(encoder.encode(JSON.stringify(v)));

const pair = (await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true,
  ["sign", "verify"],
)) as CryptoKeyPair;
const jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid: "K1", use: "sig", alg: "RS256" };

let jwksFetches = 0;
let requests: { url: string; body: string }[] = [];
let tokenResponse: Response | null = null;

const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = String(input);
  if (url === "https://appleid.apple.com/auth/keys") {
    jwksFetches += 1;
    return Response.json({ keys: [jwk] });
  }
  requests.push({ url, body: String(init?.body ?? "") });
  return tokenResponse ?? new Response(null, { status: 200 });
}) as typeof fetch;

async function token(claims: Record<string, unknown> = {}, header: Record<string, unknown> = {}): Promise<string> {
  const input = `${b64json({ alg: "RS256", kid: "K1", ...header })}.${b64json({
    iss: "https://appleid.apple.com",
    aud: CLIENT_ID,
    exp: NOW + 600,
    iat: NOW,
    sub: "001234.abcdef.0001",
    nonce: await sha256Hex("raw-nonce"),
    ...claims,
  })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, encoder.encode(input));
  return `${input}.${base64url(new Uint8Array(sig))}`;
}

const verify = (t: string, nonce = "raw-nonce", nowSec = NOW) =>
  verifyAppleToken(t, { clientId: CLIENT_ID, nonce, nowSec, fetcher });

beforeEach(() => {
  resetAppleKeyCache();
  jwksFetches = 0;
  requests = [];
  tokenResponse = null;
});

describe("verifyAppleToken", () => {
  it("accepts a good token and returns its subject", async () => {
    expect(await verify(await token())).toEqual({ sub: "001234.abcdef.0001", exp: NOW + 600, nonce: await sha256Hex("raw-nonce") });
  });

  it("fetches Apple's keys once for two verifications", async () => {
    await verify(await token());
    await verify(await token());
    expect(jwksFetches).toBe(1);
  });

  it.each([
    ["the wrong audience", { aud: "com.example.other" }],
    ["the wrong issuer", { iss: "https://evil.example" }],
    ["an expired token", { exp: NOW - 1 }],
    ["a token issued in the future", { iat: NOW + 3600 }],
    ["no subject", { sub: "" }],
  ])("rejects %s", async (_, claims) => {
    expect(await verify(await token(claims))).toBeNull();
  });

  it("rejects a nonce that doesn't match", async () => {
    expect(await verify(await token(), "other-nonce")).toBeNull();
  });

  it("rejects a tampered payload", async () => {
    const [h, , s] = (await token()).split(".");
    const forged = b64json({ iss: "https://appleid.apple.com", aud: CLIENT_ID, exp: NOW + 600, iat: NOW, sub: "someone-else" });
    expect(await verify(`${h}.${forged}.${s}`)).toBeNull();
  });

  it("rejects alg none and malformed tokens", async () => {
    const [, p] = (await token()).split(".");
    expect(await verify(`${b64json({ alg: "none", kid: "K1" })}.${p}.`)).toBeNull();
    expect(await verify("not.a.jwt.at.all")).toBeNull();
    expect(await verify("!!.@@.##")).toBeNull();
  });

  it("refetches the keys once for an unknown kid, at most once a minute", async () => {
    await verify(await token());
    expect(await verify(await token({}, { kid: "K2" }))).toBeNull();
    expect(jwksFetches).toBe(1);
    expect(await verify(await token({}, { kid: "K2" }), "raw-nonce", NOW + 61)).toBeNull();
    expect(jwksFetches).toBe(2);
  });

  it("fails closed when Apple's keys can't be fetched", async () => {
    const down = (async () => new Response("no", { status: 503 })) as unknown as typeof fetch;
    expect(await verifyAppleToken(await token(), { clientId: CLIENT_ID, nonce: "raw-nonce", nowSec: NOW, fetcher: down })).toBeNull();
  });
});

describe("parseAppleProof", () => {
  it("accepts a token and nonce, with an optional code", () => {
    expect(parseAppleProof({ identityToken: "t", nonce: "n" })).toEqual({ identityToken: "t", nonce: "n" });
    expect(parseAppleProof({ identityToken: "t", nonce: "n", authorizationCode: "c" })).toEqual({
      identityToken: "t",
      nonce: "n",
      authorizationCode: "c",
    });
  });

  it.each([[null], [{ identityToken: "t" }], [{ identityToken: 1, nonce: "n" }], [{ identityToken: "t", nonce: "n", x: 1 }], [{ identityToken: "t", nonce: "", }], [{ identityToken: "t", nonce: "n", authorizationCode: 5 }]])(
    "rejects %j",
    (proof) => {
      expect(parseAppleProof(proof)).toBeNull();
    },
  );
});

const ecPair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", ecPair.privateKey));
const P8 = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
const keyed = { SIWA_CLIENT_ID: CLIENT_ID, APNS_TEAM_ID: "B222J9J7B8", SIWA_KEY_P8: P8, SIWA_KEY_ID: "SIWAKEY" } as Env;
const unkeyed = { SIWA_CLIENT_ID: CLIENT_ID, APNS_TEAM_ID: "B222J9J7B8" } as Env;

describe("the client secret, code exchange and revocation", () => {
  it("signs a client secret Apple can verify", async () => {
    const secret = await appleClientSecret(P8, "SIWAKEY", "B222J9J7B8", CLIENT_ID, NOW);
    const [h, p, s] = secret.split(".") as [string, string, string];
    const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    expect(decode(h)).toEqual({ alg: "ES256", kid: "SIWAKEY" });
    expect(decode(p)).toEqual({ iss: "B222J9J7B8", iat: NOW, exp: NOW + 300, aud: "https://appleid.apple.com", sub: CLIENT_ID });
    const sig = Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, ecPair.publicKey, sig, encoder.encode(`${h}.${p}`))).toBe(true);
  });

  it("without the key, exchanging and revoking make no request", async () => {
    expect(await exchangeAppleCode(unkeyed, "code", fetcher, NOW)).toBeNull();
    await revokeAppleToken(unkeyed, "refresh", fetcher, NOW);
    expect(requests).toEqual([]);
  });

  it("exchanges a code for the refresh token", async () => {
    tokenResponse = Response.json({ refresh_token: "r-123", access_token: "a" });
    expect(await exchangeAppleCode(keyed, "code-1", fetcher, NOW)).toBe("r-123");
    const sent = new URLSearchParams(requests[0]?.body);
    expect(requests[0]?.url).toBe("https://appleid.apple.com/auth/token");
    expect(sent.get("grant_type")).toBe("authorization_code");
    expect(sent.get("code")).toBe("code-1");
    expect(sent.get("client_id")).toBe(CLIENT_ID);
    expect(sent.get("client_secret")?.split(".")).toHaveLength(3);
  });

  it("returns null when Apple refuses the code", async () => {
    tokenResponse = Response.json({ error: "invalid_grant" }, { status: 400 });
    expect(await exchangeAppleCode(keyed, "code-1", fetcher, NOW)).toBeNull();
  });

  it("revokes a refresh token", async () => {
    await revokeAppleToken(keyed, "r-123", fetcher, NOW);
    const sent = new URLSearchParams(requests[0]?.body);
    expect(requests[0]?.url).toBe("https://appleid.apple.com/auth/revoke");
    expect(sent.get("token")).toBe("r-123");
    expect(sent.get("token_type_hint")).toBe("refresh_token");
  });

  it("a network failure while revoking doesn't throw", async () => {
    const broken = (async () => {
      throw new Error("offline");
    }) as unknown as typeof fetch;
    await expect(revokeAppleToken(keyed, "r", broken, NOW)).resolves.toBeUndefined();
    await expect(exchangeAppleCode(keyed, "c", broken, NOW)).resolves.toBeNull();
  });
});
