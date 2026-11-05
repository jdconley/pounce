import { describe, expect, it, vi } from "vitest";

import { createApnsJwt, pushAlert, pushDismiss, pushLive, pushWidget, pushYourTurn, sendApns } from "./apns";

import type { Env } from "../env";
import type { YourTurnIntent } from "../room/core";

const TEAM = "B222J9J7B8";
const NOW = 1_800_000_000;
const TOKEN = "ab".repeat(32);

const decoder = new TextDecoder();

function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const decodeJson = (part: string): unknown => JSON.parse(decoder.decode(fromBase64url(part)));

async function keyPair(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const body = btoa(String.fromCharCode(...der)).match(/.{1,64}/g)?.join("\n") ?? "";
  return {
    pem: `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`,
    publicKey: pair.publicKey,
  };
}

describe("createApnsJwt", () => {
  it("has an ES256 header with kid and iss/iat claims, and verifies with the public key", async () => {
    const { pem, publicKey } = await keyPair();
    const jwt = await createApnsJwt(pem, "KID-VERIFY", TEAM, NOW);
    const [header, claims, signature] = jwt.split(".") as [string, string, string];

    expect(decodeJson(header)).toEqual({ alg: "ES256", kid: "KID-VERIFY" });
    expect(decodeJson(claims)).toEqual({ iss: TEAM, iat: NOW });
    // Raw r||s, not DER.
    expect(fromBase64url(signature)).toHaveLength(64);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      fromBase64url(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("reuses the token for 50 minutes per key id, then signs a fresh one", async () => {
    const { pem } = await keyPair();
    const first = await createApnsJwt(pem, "KID-CACHE", TEAM, NOW);
    expect(await createApnsJwt(pem, "KID-CACHE", TEAM, NOW + 49 * 60)).toBe(first);

    const refreshed = await createApnsJwt(pem, "KID-CACHE", TEAM, NOW + 50 * 60);
    expect(refreshed).not.toBe(first);
    expect(decodeJson(refreshed.split(".")[1] as string)).toEqual({ iss: TEAM, iat: NOW + 50 * 60 });

    // A different key id never shares the cache.
    const other = await createApnsJwt(pem, "KID-OTHER", TEAM, NOW + 50 * 60);
    expect(decodeJson(other.split(".")[0] as string)).toEqual({ alg: "ES256", kid: "KID-OTHER" });
  });
});

type Call = { url: string; init: RequestInit };

function fakeFetch(response: Response | Error): { fetcher: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (response instanceof Error) throw response;
    return response.clone();
  }) as unknown as typeof fetch;
  return { fetcher, calls };
}

const CFG = { host: "api.push.apple.com", topic: "com.conleychaos.play", jwt: "the.jwt.value" };
const PAYLOAD = { title: "Sam", body: "Your turn", code: "BCDFG" };

describe("sendApns", () => {
  it("builds the request exactly", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    const result = await sendApns(fetcher, CFG, TOKEN, PAYLOAD);

    expect(result).toEqual({ ok: true, status: 200, unregistered: false, reason: null });
    expect(calls).toHaveLength(1);
    const { url, init } = calls[0] as Call;
    expect(url).toBe(`https://api.push.apple.com/3/device/${TOKEN}`);
    expect(init.method).toBe("POST");
    expect(init.headers).toEqual({
      authorization: "bearer the.jwt.value",
      "apns-topic": "com.conleychaos.play",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": "BCDFG",
    });
    expect(JSON.parse(init.body as string)).toEqual({
      aps: { alert: { title: "Sam", body: "Your turn" }, sound: "default", "thread-id": "BCDFG" },
      code: "BCDFG",
    });
  });

  it("marks 410 as unregistered", async () => {
    const { fetcher } = fakeFetch(new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 }));
    expect(await sendApns(fetcher, CFG, TOKEN, PAYLOAD)).toEqual({
      ok: false,
      status: 410,
      unregistered: true,
      reason: "Unregistered",
    });
  });

  it("marks 400 BadDeviceToken as unregistered, but not other 400 reasons", async () => {
    const bad = fakeFetch(new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 }));
    expect((await sendApns(bad.fetcher, CFG, TOKEN, PAYLOAD)).unregistered).toBe(true);

    const other = fakeFetch(new Response(JSON.stringify({ reason: "PayloadEmpty" }), { status: 400 }));
    expect(await sendApns(other.fetcher, CFG, TOKEN, PAYLOAD)).toEqual({
      ok: false,
      status: 400,
      unregistered: false,
      reason: "PayloadEmpty",
    });
  });

  it("treats other failures as not ok, with an unparseable or reasonless body tolerated", async () => {
    for (const body of ["<html>", "{}"]) {
      const { fetcher } = fakeFetch(new Response(body, { status: 503 }));
      expect(await sendApns(fetcher, CFG, TOKEN, PAYLOAD)).toEqual({
        ok: false,
        status: 503,
        unregistered: false,
        reason: null,
      });
    }
  });
});

describe("background pushes", () => {
  it("send content-available only, at low priority, with the data beside aps", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    const result = await sendApns(fetcher, CFG, TOKEN, { background: { kind: "dismiss", code: "BCDFG" }, collapseId: "dismiss:BCDFG" });
    expect(result.ok).toBe(true);
    const { init } = calls[0] as Call;
    expect(init.headers).toEqual({
      authorization: "bearer the.jwt.value",
      "apns-topic": "com.conleychaos.play",
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-collapse-id": "dismiss:BCDFG",
    });
    expect(JSON.parse(init.body as string)).toEqual({ aps: { "content-available": 1 }, kind: "dismiss", code: "BCDFG" });
  });
});

describe("pushYourTurn", () => {
  const intent: YourTurnIntent = {
    deviceId: "dev",
    kind: "your_turn",
    seat: 1,
    personName: "Sam",
    tableName: "Taco Night",
    code: "BCDFG",
  };

  async function env(extra: Partial<Env> = {}): Promise<Env> {
    const { pem } = await keyPair();
    return {
      APNS_TEAM_ID: TEAM,
      APNS_TOPIC: "com.conleychaos.play",
      APNS_HOST: "api.push.apple.com",
      APNS_KEY_P8: pem,
      APNS_KEY_ID: "KID-PUSH",
      ...extra,
    } as Env;
  }

  it("sends the person's name and 'Your turn at' the table's name, with the room code", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    const result = await pushYourTurn(await env(), TOKEN, intent, fetcher, NOW);

    expect(result).toEqual({ sent: true, unregistered: false });
    const { url, init } = calls[0] as Call;
    expect(url).toBe(`https://api.push.apple.com/3/device/${TOKEN}`);
    expect((init.headers as Record<string, string>).authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(JSON.parse(init.body as string)).toEqual({
      aps: { alert: { title: "Sam", body: "Your turn at Taco Night" }, sound: "default", "thread-id": "BCDFG" },
      code: "BCDFG",
    });
  });

  it("is a no-op without a device token", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    expect(await pushYourTurn(await env(), null, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(calls).toHaveLength(0);
  });

  it("is a no-op when either APNs secret is missing", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    const noKey = await env({ APNS_KEY_P8: undefined });
    const noKid = await env({ APNS_KEY_ID: undefined });
    expect(await pushYourTurn(noKey, TOKEN, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(await pushYourTurn(noKid, TOKEN, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(calls).toHaveLength(0);
  });

  it("reports an unregistered token so the caller can clear it", async () => {
    const { fetcher } = fakeFetch(new Response(null, { status: 410 }));
    const spy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    expect(await pushYourTurn(await env(), TOKEN, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: true });
    spy.mockRestore();
  });

  it("logs a key that cannot sign as apns_key_invalid, apart from network errors, without the error text", async () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    // A fresh kid each time, so no cached token from another test can hide the failure.
    const garbled = await env({ APNS_KEY_ID: "KID-GARBLED", APNS_KEY_P8: "-----BEGIN PRIVATE KEY-----\n%%%\n-----END PRIVATE KEY-----" });
    const notEc = await env({ APNS_KEY_ID: "KID-NOT-EC", APNS_KEY_P8: btoa("not a pkcs8 key at all") });
    expect(await pushYourTurn(garbled, TOKEN, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(await pushYourTurn(notEc, TOKEN, intent, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(calls).toHaveLength(0);
    expect(spy.mock.calls).toEqual([
      ["apns_push_failed", "apns_key_invalid"],
      ["apns_push_failed", "apns_key_invalid"],
    ]);
    spy.mockRestore();
  });

  it("logs only the status and reason on failure, never the token or key", async () => {
    const e = await env();
    const spy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const rejected = fakeFetch(new Response(JSON.stringify({ reason: "TooManyRequests" }), { status: 429 }));
    expect(await pushYourTurn(e, TOKEN, intent, rejected.fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    const down = fakeFetch(new Error(`connect failed for ${TOKEN}`));
    expect(await pushYourTurn(e, TOKEN, intent, down.fetcher, NOW)).toEqual({ sent: false, unregistered: false });

    const logged = JSON.stringify(spy.mock.calls);
    expect(spy.mock.calls[0]).toEqual(["apns_push_failed", 429, "TooManyRequests"]);
    expect(spy.mock.calls[1]).toEqual(["apns_push_failed", "network_error"]);
    expect(logged).not.toContain(TOKEN);
    expect(logged).not.toContain("PRIVATE KEY");
    spy.mockRestore();
  });
});

describe("pushDismiss", () => {
  it("tells a device to clear a table's notifications, and is a no-op without a token or the secrets", async () => {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
    const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    const env = {
      APNS_TEAM_ID: TEAM,
      APNS_TOPIC: "com.conleychaos.play",
      APNS_HOST: "api.push.apple.com",
      APNS_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`,
      APNS_KEY_ID: "KID-DISMISS",
    } as Env;
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    expect(await pushDismiss(env, TOKEN, "BCDFG", fetcher, NOW)).toEqual({ sent: true, unregistered: false });
    expect(JSON.parse((calls[0] as Call).init.body as string)).toEqual({
      aps: { "content-available": 1 },
      kind: "dismiss",
      code: "BCDFG",
    });
    expect(await pushDismiss(env, null, "BCDFG", fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(await pushDismiss({ ...env, APNS_KEY_ID: undefined }, TOKEN, "BCDFG", fetcher, NOW)).toEqual({
      sent: false,
      unregistered: false,
    });
    expect(calls).toHaveLength(1);
  });
});

describe("rich alerts (§12.5)", () => {
  it("send the built body at priority 10 when active and 5 when passive, collapsed by id", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    const body = { aps: { alert: { title: "JD", body: "hi" } }, kind: "nap" };
    await sendApns(fetcher, CFG, TOKEN, { alert: body, collapseId: "nap:pr_1", level: "passive" });
    await sendApns(fetcher, CFG, TOKEN, { alert: body, collapseId: "GH2VD", level: "active" });
    const [passive, active] = calls as [Call, Call];
    expect(passive.init.headers).toEqual({
      authorization: "bearer the.jwt.value",
      "apns-topic": "com.conleychaos.play",
      "apns-push-type": "alert",
      "apns-priority": "5",
      "apns-collapse-id": "nap:pr_1",
    });
    expect((active.init.headers as Record<string, string>)["apns-priority"]).toBe("10");
    expect(JSON.parse(passive.init.body as string)).toEqual(body);
  });

  it("pushAlert delivers through the configured key", async () => {
    const { pem } = await keyPair();
    const env = { APNS_TEAM_ID: TEAM, APNS_TOPIC: "com.conleychaos.play", APNS_HOST: "api.push.apple.com", APNS_KEY_P8: pem, APNS_KEY_ID: "KID-RICH" } as Env;
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    expect(await pushAlert(env, TOKEN, { aps: {} }, "x", "active", fetcher, NOW)).toEqual({ sent: true, unregistered: false });
    expect(await pushAlert(env, null, { aps: {} }, "x", "active", fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(calls).toHaveLength(1);
  });
});

describe("widget pushes (§11.2)", () => {
  it("send content-changed to the widgets topic at priority 5, with no collapse id", async () => {
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    await sendApns(fetcher, CFG, TOKEN, { widget: true });
    const { init } = calls[0] as Call;
    expect(init.headers).toEqual({
      authorization: "bearer the.jwt.value",
      "apns-topic": "com.conleychaos.play.push-type.widgets",
      "apns-push-type": "widgets",
      "apns-priority": "5",
    });
    expect(JSON.parse(init.body as string)).toEqual({ aps: { "content-changed": true } });
  });

  it("pushWidget is a no-op without a token", async () => {
    const { pem } = await keyPair();
    const env = { APNS_TEAM_ID: TEAM, APNS_TOPIC: "com.conleychaos.play", APNS_HOST: "api.push.apple.com", APNS_KEY_P8: pem, APNS_KEY_ID: "KID-WIDGET" } as Env;
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    expect(await pushWidget(env, null, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(await pushWidget(env, TOKEN, fetcher, NOW)).toEqual({ sent: true, unregistered: false });
    expect(calls).toHaveLength(1);
  });
});

describe("live table pushes (§11.3)", () => {
  it("go to the liveactivity topic at the priority asked, with no collapse id", async () => {
    const body = { aps: { timestamp: NOW, event: "update", "content-state": { table: "Couch Cats" } } };
    for (const priority of [5, 10] as const) {
      const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
      await sendApns(fetcher, CFG, TOKEN, { live: body, priority });
      const { init } = calls[0] as Call;
      expect(init.headers).toEqual({
        authorization: "bearer the.jwt.value",
        "apns-topic": "com.conleychaos.play.push-type.liveactivity",
        "apns-push-type": "liveactivity",
        "apns-priority": String(priority),
      });
      expect(JSON.parse(init.body as string)).toEqual(body);
    }
  });

  it("pushLive is a no-op without a token", async () => {
    const { pem } = await keyPair();
    const env = { APNS_TEAM_ID: TEAM, APNS_TOPIC: "com.conleychaos.play", APNS_HOST: "api.push.apple.com", APNS_KEY_P8: pem, APNS_KEY_ID: "KID-LIVE" } as Env;
    const { fetcher, calls } = fakeFetch(new Response(null, { status: 200 }));
    expect(await pushLive(env, null, { aps: {} }, 5, fetcher, NOW)).toEqual({ sent: false, unregistered: false });
    expect(await pushLive(env, TOKEN, { aps: {} }, 10, fetcher, NOW)).toEqual({ sent: true, unregistered: false });
    expect(calls).toHaveLength(1);
  });
});
