import { build } from "esbuild";
import { Miniflare, Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

import type { PushIntent } from "../src/room/core";

let mf: Miniflare;
let script = "";

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("./push-entry.ts", import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  script = built.outputFiles[0]?.text ?? "";
  mf = new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
    },
    // No APNS_KEY_P8 / APNS_KEY_ID: the secrets are unset.
    bindings: { APNS_TEAM_ID: "B222J9J7B8", APNS_TOPIC: "com.conleychaos.play", APNS_HOST: "api.push.apple.com" },
  });
});

afterAll(async () => {
  await mf.dispose();
});

const intent: PushIntent = { deviceId: "dev-1", kind: "your_turn", seat: 0, personName: "Sam", code: "BCDFG" };

describe("DeviceIndex.push", () => {
  test("with a token stored but no APNs secrets configured, nothing is sent", async () => {
    const set = await mf.dispatchFetch("https://x.test/__test/token?device=dev-1&token=" + "ab".repeat(32));
    expect(set.status).toBe(204);
    const res = await mf.dispatchFetch("https://x.test/__test/push?device=dev-1", {
      method: "POST",
      body: JSON.stringify(intent),
    });
    expect(await res.json()).toEqual({ sent: false });
  });

  test("with no token stored, nothing is sent", async () => {
    const res = await mf.dispatchFetch("https://x.test/__test/push?device=dev-2", {
      method: "POST",
      body: JSON.stringify({ ...intent, deviceId: "dev-2" }),
    });
    expect(await res.json()).toEqual({ sent: false });
  });
});

/** A PKCS#8 PEM for a fresh P-256 key, like the .p8 Apple issues. */
async function p8(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
}

describe("DeviceIndex.push when APNs says the token is dead", () => {
  const OLD = "aa".repeat(32);
  const NEW = "bb".repeat(32);
  /** Device tokens APNs was asked to deliver to, in order. */
  let sentTo: string[] = [];
  let onSend: (() => Promise<void>) | null = null;
  let apns: Miniflare;

  beforeAll(async () => {
    apns = new Miniflare({
      modules: true,
      script,
      compatibilityDate: "2026-08-01",
      durableObjects: {
        ROOMS: { className: "GameRoom", useSQLite: true },
        DEVICES: { className: "DeviceIndex", useSQLite: true },
      },
      bindings: {
        APNS_TEAM_ID: "B222J9J7B8",
        APNS_TOPIC: "com.conleychaos.play",
        APNS_HOST: "api.push.apple.com",
        APNS_KEY_P8: await p8(),
        APNS_KEY_ID: "KID-WORKER",
      },
      // Stands in for APNs: every token is unregistered.
      outboundService: async (request: MiniflareRequest) => {
        sentTo.push(new URL(request.url).pathname.split("/").at(-1) as string);
        const hook = onSend;
        onSend = null;
        if (hook) await hook();
        return new MiniflareResponse(JSON.stringify({ reason: "Unregistered" }), { status: 410 });
      },
    });
  });

  afterAll(async () => {
    await apns.dispose();
  });

  const setToken = (device: string, token: string) =>
    apns.dispatchFetch(`https://x.test/__test/token?device=${device}&token=${token}`);
  const push = async (device: string) =>
    (await apns.dispatchFetch(`https://x.test/__test/push?device=${device}`, {
      method: "POST",
      body: JSON.stringify({ ...intent, deviceId: device }),
    }).then((res) => res.json())) as { sent: boolean };

  test("forgets the token, so the next push sends nothing", async () => {
    sentTo = [];
    await setToken("dev-dead", OLD);
    expect(await push("dev-dead")).toEqual({ sent: false });
    expect(await push("dev-dead")).toEqual({ sent: false });
    expect(sentTo).toEqual([OLD]);
  });

  test("keeps a token registered while the push was in flight", async () => {
    sentTo = [];
    await setToken("dev-race", OLD);
    // The device re-registers before APNs answers that the old token is dead.
    onSend = async () => {
      expect((await setToken("dev-race", NEW)).status).toBe(204);
    };
    expect(await push("dev-race")).toEqual({ sent: false });
    expect(await push("dev-race")).toEqual({ sent: false });
    expect(sentTo).toEqual([OLD, NEW]);
  });
});
