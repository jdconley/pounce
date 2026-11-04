import { build } from "esbuild";
import { Miniflare, Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

import type { YourTurnIntent } from "../src/room/core";

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
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
    },
    // No APNS_KEY_P8 / APNS_KEY_ID: the secrets are unset.
    bindings: { APNS_TEAM_ID: "B222J9J7B8", APNS_TOPIC: "com.conleychaos.play", APNS_HOST: "api.push.apple.com" },
  });
});

afterAll(async () => {
  await mf.dispose();
});

const intent: YourTurnIntent = { deviceId: "dev-1", kind: "your_turn", seat: 0, personName: "Sam",
  tableName: "Taco Night",
  code: "BCDFG",
};

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
        PLAYERS: { className: "Player", useSQLite: true },
        IDENTITIES: { className: "Identities", useSQLite: true },
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

/** An IANA zone where it is `hour` o'clock right now (Etc/GMT names have inverted signs). */
function zoneAtHour(hour: number): string {
  let offset = (hour - new Date().getUTCHours() + 24) % 24;
  if (offset > 14) offset -= 24;
  return offset === 0 ? "Etc/GMT" : `Etc/GMT${offset > 0 ? "-" : "+"}${Math.abs(offset)}`;
}

describe("DeviceIndex.push by age band", () => {
  let sent: { token: string; type: string | null }[] = [];
  let ok: Miniflare;

  beforeAll(async () => {
    ok = new Miniflare({
      modules: true,
      script,
      compatibilityDate: "2026-08-01",
      durableObjects: {
        ROOMS: { className: "GameRoom", useSQLite: true },
        DEVICES: { className: "DeviceIndex", useSQLite: true },
        PLAYERS: { className: "Player", useSQLite: true },
        IDENTITIES: { className: "Identities", useSQLite: true },
      },
      bindings: {
        APNS_TEAM_ID: "B222J9J7B8",
        APNS_TOPIC: "com.conleychaos.play",
        APNS_HOST: "api.push.apple.com",
        APNS_KEY_P8: await p8(),
        APNS_KEY_ID: "KID-BANDS",
      },
      outboundService: async (request: MiniflareRequest) => {
        sent.push({ token: new URL(request.url).pathname.split("/").at(-1) as string, type: request.headers.get("apns-push-type") });
        return new MiniflareResponse(null, { status: 200 });
      },
    });
  });

  afterAll(async () => {
    await ok.dispose();
  });

  async function device(name: string, band: string, zone: string): Promise<void> {
    await ok.dispatchFetch(`https://x.test/__test/token?device=${name}&token=${"cd".repeat(32)}`);
    await ok.dispatchFetch(`https://x.test/__test/profile?device=${name}&band=${band}&zone=${encodeURIComponent(zone)}`);
  }
  const push = async (name: string, body: unknown) =>
    (await ok.dispatchFetch(`https://x.test/__test/push?device=${name}`, { method: "POST", body: JSON.stringify(body) }).then((r) =>
      r.json(),
    )) as { sent: boolean };
  const dismiss = { kind: "dismiss", playerId: "p_x", exceptDeviceId: "other", code: "BCDFG" };

  test("a kitten's device gets nothing, not even a background push", async () => {
    sent = [];
    await device("kitten", "kitten", "UTC");
    expect(await push("kitten", { ...intent, deviceId: "kitten" })).toEqual({ sent: false });
    expect(await push("kitten", dismiss)).toEqual({ sent: false });
    expect(sent).toEqual([]);
  });

  test("a teen's device gets nothing at 2 a.m., not even a background push (§14.1)", async () => {
    sent = [];
    await device("teen-night", "teen", zoneAtHour(2));
    expect(await push("teen-night", { ...intent, deviceId: "teen-night" })).toEqual({ sent: false });
    expect(await push("teen-night", dismiss)).toEqual({ sent: false });
    expect(sent).toEqual([]);
  });

  test("a teen at noon and an adult at 2 a.m. get their alerts", async () => {
    sent = [];
    await device("teen-noon", "teen", zoneAtHour(12));
    await device("adult-night", "adult", zoneAtHour(2));
    expect(await push("teen-noon", { ...intent, deviceId: "teen-noon" })).toEqual({ sent: true });
    expect(await push("adult-night", { ...intent, deviceId: "adult-night" })).toEqual({ sent: true });
    expect(sent.map((s) => s.type)).toEqual(["alert", "alert"]);
  });
});
