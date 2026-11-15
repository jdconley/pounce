import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { build } from "esbuild";
import { Miniflare } from "miniflare";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

import { WEB_PLAYER_CSP } from "../src/http/layout";
import { PROTOCOL_VERSION, type ServerMessage } from "../src/protocol";

/**
 * The web player's two needs of the Worker (web player design): game sockets a browser can open
 * and read, and the app itself under /play/. Runs the real Worker in workerd.
 */
const SECRET = "s".repeat(64);
const BASE = "https://play.conleychaos.com";
const WEB_APP = `platform=web; version=2026.1115.1200; build=7; protocol=${PROTOCOL_VERSION}`;

let script = "";
let assets = "";
let mf: Miniflare;

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("../src/index.ts", import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  script = built.outputFiles[0]?.text ?? "";
  // A stand-in build of the web player.
  assets = mkdtempSync(join(tmpdir(), "web-player-"));
  mkdirSync(join(assets, "play/assets"), { recursive: true });
  mkdirSync(join(assets, "play/icons"), { recursive: true });
  writeFileSync(join(assets, "play/index.html"), "<!doctype html><title>Pounce</title><div id=app></div>");
  writeFileSync(join(assets, "play/assets/main-AbC123.js"), "console.log(1)");
  writeFileSync(join(assets, "play/sw.js"), "self.addEventListener('fetch',()=>{})");
  writeFileSync(join(assets, "play/version.json"), '{"build":"abc"}');
  writeFileSync(join(assets, "play/manifest.webmanifest"), '{"name":"Pounce"}');
  writeFileSync(join(assets, "play/icons/icon-192.png"), "png");
  mf = new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
      LIMITS: { className: "Limiter", useSQLite: true },
      REPORTS: { className: "Reports", useSQLite: true },
    },
    // A minimum every app is below, enforced: the web player must not care.
    bindings: { TOKEN_SECRET: SECRET, GAMES: "tiles", APP_MINIMUM: "99.0", APP_MINIMUM_FORCE: "on" },
    assets: {
      directory: assets,
      binding: "ASSETS",
      routerConfig: { has_user_worker: true, static_routing: { user_worker: ["/*"], asset_worker: [] } },
      assetConfig: { html_handling: "none", not_found_handling: "none" },
    },
  });
});

afterAll(async () => {
  await mf?.dispose();
  rmSync(assets, { recursive: true, force: true });
});

const webHeaders = { "x-pounce-app": WEB_APP, "x-pounce-games": "tiles", "content-type": "application/json" };

async function mint(): Promise<string> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: webHeaders });
  expect(res.status).toBe(200);
  return ((await res.json()) as { token: string }).token;
}

async function newTable(token: string, game = "tiles"): Promise<string> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms`, {
    method: "POST",
    headers: { ...webHeaders, authorization: `Bearer ${token}` },
    body: JSON.stringify({ game }),
  });
  expect(res.status).toBe(201);
  return ((await res.json()) as { code: string }).code;
}

/** Opens a socket the way the browser does: no headers of its own, the token as a subprotocol. */
async function browserSocket(code: string, token: string | null, query = `games=tiles&app=${encodeURIComponent(WEB_APP)}`) {
  const protocols = ["pounce", ...(token ? [`pounce.token.${token}`] : [])].join(", ");
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws?${query}`, {
    headers: { upgrade: "websocket", "sec-websocket-protocol": protocols },
  });
  expect(res.status).toBe(101);
  expect(res.headers.get("sec-websocket-protocol")).toBe("pounce");
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  const messages: ServerMessage[] = [];
  const closed = new Promise<{ code: number; reason: string }>((resolve) =>
    ws.addEventListener("close", (e) => resolve({ code: e.code, reason: e.reason })),
  );
  ws.addEventListener("message", (e) => messages.push(JSON.parse(e.data as string) as ServerMessage));
  ws.accept();
  return { ws, messages, closed };
}

async function until<T>(read: () => T | undefined, ms = 5000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const value = read();
    if (value !== undefined) return value;
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 20));
  }
}

describe("a game socket from the browser", () => {
  test("opens with the token in a subprotocol, the games and app in the query, past any minimum", async () => {
    const token = await mint();
    const code = await newTable(token);
    const { ws, messages } = await browserSocket(code, token);
    const snap = await until(() => messages.find((m) => m.t === "snapshot"));
    expect(snap.t === "snapshot" && snap.protocol).toBe(PROTOCOL_VERSION);
    expect(snap.t === "snapshot" && snap.room.gameId).toBe("tiles");
    ws.close();
  });

  test("a table of a game the query doesn't list is refused, readably", async () => {
    const token = await mint();
    const code = await newTable(token, "tiles");
    const { closed } = await browserSocket(code, token, `app=${encodeURIComponent(WEB_APP)}`);
    expect((await closed).code).toBeGreaterThanOrEqual(4400);
  });

  test("no such table closes with 4404, no token with 4401", async () => {
    const token = await mint();
    expect((await (await browserSocket("BCDFG", token)).closed).code).toBe(4404);
    const code = await newTable(token);
    expect(await (await browserSocket(code, null)).closed).toEqual({ code: 4401, reason: "unauthorized" });
    expect((await (await browserSocket(code, "v1.nope.nope")).closed).code).toBe(4401);
  });

  test("a socket without the pounce subprotocol is the app's, answered as before", async () => {
    const token = await mint();
    const code = await newTable(token, "cat-tower");
    const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, { headers: { upgrade: "websocket" } });
    expect(res.status).toBe(401);
    expect(res.headers.get("sec-websocket-protocol")).toBeNull();
    await res.arrayBuffer();
  });
});

describe("the web player's files", () => {
  test("every path under /play/ is the app, with its CSP, never cached", async () => {
    for (const path of ["/play/", "/play/j/BCDFG", "/play/p/abc", "/play/t/BCDFG/x"]) {
      const res = await mf.dispatchFetch(`${BASE}${path}`);
      expect(res.status, path).toBe(200);
      expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
      expect(res.headers.get("content-security-policy")).toBe(WEB_PLAYER_CSP);
      expect(res.headers.get("cache-control")).toBe("no-cache");
      expect(await res.text()).toContain('<div id=app>');
    }
  });

  test("/play goes to /play/", async () => {
    const res = await mf.dispatchFetch(`${BASE}/play?x=1`, { redirect: "manual" });
    expect(res.status).toBe(301);
    expect(res.headers.get("location")).toBe(`${BASE}/play/?x=1`);
  });

  test("hashed files are cached for good; the service worker, version and manifest never are", async () => {
    const js = await mf.dispatchFetch(`${BASE}/play/assets/main-AbC123.js`);
    expect(js.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect(await js.text()).toBe("console.log(1)");
    const sw = await mf.dispatchFetch(`${BASE}/play/sw.js`);
    expect(sw.headers.get("cache-control")).toBe("no-cache");
    expect(sw.headers.get("service-worker-allowed")).toBe("/play/");
    await sw.arrayBuffer();
    const manifest = await mf.dispatchFetch(`${BASE}/play/manifest.webmanifest`);
    expect(manifest.headers.get("content-type")).toBe("application/manifest+json");
    await manifest.arrayBuffer();
    const icon = await mf.dispatchFetch(`${BASE}/play/icons/icon-192.png`);
    expect(icon.headers.get("cache-control")).toBe("public, max-age=86400");
    await icon.arrayBuffer();
  });

  test("a missing file is a 404, never the app", async () => {
    for (const path of ["/play/assets/gone-123.js", "/play/missing.png", "/play/icons/none.png", "/play/index.html/x.js"]) {
      const res = await mf.dispatchFetch(`${BASE}${path}`);
      expect(res.status, path).toBe(404);
      await res.arrayBuffer();
    }
    expect((await mf.dispatchFetch(`${BASE}/play/`, { method: "POST" })).status).toBe(404);
  });
});
