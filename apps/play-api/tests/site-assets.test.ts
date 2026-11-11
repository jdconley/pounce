import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";
import { Miniflare } from "miniflare";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

import { MEDIA } from "../src/http/site-media";

/**
 * The landing page's files (./public, wrangler.jsonc `assets`) beside the Worker: every file the
 * page names is served, the clip answers byte ranges, and no file can stand in for a route the
 * Worker owns. Runs the real config's routing rules in workerd.
 */
const BASE = "https://play.conleychaos.com";
const PUBLIC = fileURLToPath(new URL("../public", import.meta.url));

type Assets = { directory: string; binding: string; html_handling: string; not_found_handling: string; run_worker_first: string[] };
/** wrangler.jsonc as JSON: its comments are whole lines. */
const config = JSON.parse(
  readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8")
    .split("\n")
    .filter((line) => !line.trim().startsWith("//"))
    .join("\n"),
) as { assets: Assets; vars: Record<string, string> };

/** Every file under ./public, as the path it is served at. */
const files = (readdirSync(PUBLIC, { recursive: true, withFileTypes: true }) as { name: string; parentPath: string; isFile(): boolean }[])
  .filter((entry) => entry.isFile())
  .map((entry) => `${entry.parentPath.slice(PUBLIC.length)}/${entry.name}`);

let script = "";
const open: Miniflare[] = [];

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
});

afterAll(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

/** The Worker with ./public mounted as wrangler mounts it (run_worker_first as wrangler reads it). */
function site(bindings: Record<string, string> = {}): Miniflare {
  const rules = config.assets.run_worker_first;
  const mf = new Miniflare({
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
    bindings,
    assets: {
      directory: PUBLIC,
      binding: config.assets.binding,
      routerConfig: {
        has_user_worker: true,
        static_routing: {
          user_worker: rules.filter((rule) => !rule.startsWith("!")),
          asset_worker: rules.filter((rule) => rule.startsWith("!")).map((rule) => rule.slice(1)),
        },
      },
      assetConfig: { html_handling: "none", not_found_handling: "none" },
    },
  });
  open.push(mf);
  return mf;
}

describe("the static assets config", () => {
  test("the Worker answers everything first, except /static/* and the two icon files", () => {
    expect(config.assets).toEqual({
      directory: "./public",
      binding: "ASSETS",
      html_handling: "none",
      not_found_handling: "none",
      run_worker_first: ["/*", "!/static/*", "!/favicon.ico", "!/apple-touch-icon.png"],
    });
  });

  test("./public holds only those files, the clip and the headers file: nothing that could be a page or a route", () => {
    expect(readdirSync(PUBLIC).sort()).toEqual(["_headers", "apple-touch-icon.png", "favicon.ico", "media", "static"]);
    expect(readdirSync(`${PUBLIC}/media`)).toEqual([MEDIA.clip.src.replace("/media/", "")]);
    for (const file of files) {
      expect(file, file).toMatch(/^\/(?:_headers|favicon\.ico|apple-touch-icon\.png|media\/[a-z0-9-]+\.[a-f0-9]{10}\.mp4|static\/[a-z0-9-]+\.[a-f0-9]{10}\.(?:webp|jpg|png|svg))$/);
    }
    // The whole site stays small: a visitor's first page view fetches a fraction of this.
    const bytes = files.reduce((sum, file) => sum + readFileSync(`${PUBLIC}${file}`).byteLength, 0);
    expect(bytes).toBeLessThan(6_000_000);
    expect(readFileSync(`${PUBLIC}${MEDIA.clip.src}`).byteLength).toBeLessThan(1_500_000);
    expect(readFileSync(`${PUBLIC}/_headers`, "utf8")).toContain("/static/*\n  Cache-Control: public, max-age=31536000, immutable");
  });

  test("the install settings: the App Store link is empty until launch, so the site offers the TestFlight beta", () => {
    expect(config.vars.APP_STORE_URL).toBe("");
    expect(config.vars.TESTFLIGHT_URL).toMatch(/^https:\/\/testflight\.apple\.com\/join\/[A-Za-z0-9]{8}$/);
  });
});

describe("the Worker with its static assets", () => {
  test("serves every image the pages name, with its type", async () => {
    const mf = site();
    const types: Record<string, string> = { webp: "image/webp", jpg: "image/jpeg", png: "image/png", svg: "image/svg+xml", ico: "image/vnd.microsoft.icon" };
    const images = files.filter((file) => file.startsWith("/static/") || file === "/favicon.ico" || file === "/apple-touch-icon.png");
    expect(images.length).toBeGreaterThan(40);
    for (const file of images) {
      const res = await mf.dispatchFetch(`${BASE}${file}`);
      expect(res.status, file).toBe(200);
      expect(res.headers.get("content-type"), file).toBe(types[file.split(".").at(-1) as string]);
      await res.arrayBuffer();
    }
  });

  test("serves the clip whole or by byte range, as Safari needs", async () => {
    const mf = site();
    const size = readFileSync(`${PUBLIC}${MEDIA.clip.src}`).byteLength;
    const whole = await mf.dispatchFetch(`${BASE}${MEDIA.clip.src}`);
    expect(whole.status).toBe(200);
    expect(whole.headers.get("content-type")).toBe("video/mp4");
    expect(whole.headers.get("accept-ranges")).toBe("bytes");
    expect(whole.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect((await whole.arrayBuffer()).byteLength).toBe(size);

    const part = await mf.dispatchFetch(`${BASE}${MEDIA.clip.src}`, { headers: { range: "bytes=0-1" } });
    expect(part.status).toBe(206);
    expect(part.headers.get("content-range")).toBe(`bytes 0-1/${size}`);
    expect((await part.arrayBuffer()).byteLength).toBe(2);

    for (const path of ["/media/clip.0000000000.mp4", "/media/", "/static/clip.0000000000.mp4", `${MEDIA.clip.src}/x`]) {
      const res = await mf.dispatchFetch(`${BASE}${path}`);
      expect(res.status, path).toBe(404);
      await res.arrayBuffer();
    }
    expect((await mf.dispatchFetch(`${BASE}${MEDIA.clip.src}`, { method: "POST" })).status).toBe(404);
  });

  test("the Worker still answers its own routes: no file shadows the API, the pages or the association file", async () => {
    const mf = site({ TESTFLIGHT_URL: "https://testflight.apple.com/join/abc123" });
    const aasa = await mf.dispatchFetch(`${BASE}/.well-known/apple-app-site-association`);
    expect(aasa.headers.get("content-type")).toBe("application/json");
    expect(await aasa.json()).toEqual({
      applinks: { details: [{ appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }] }] },
    });
    for (const [path, marker] of [
      ["/", "<h1 id=\"top\">"],
      ["/support", "House Cat"],
      ["/privacy", 'id="coppa"'],
      ["/j/BCDFG", "Join the game"],
      ["/healthz", '"service":"play-api"'],
      ["/robots.txt", "Sitemap:"],
      ["/sitemap.xml", "<urlset"],
    ] as const) {
      const res = await mf.dispatchFetch(`${BASE}${path}`);
      expect(res.status, path).toBe(200);
      expect(await res.text(), path).toContain(marker);
    }
    // Paths with no route are the Worker's JSON 404, never a file listing or a file.
    for (const path of ["/_headers", "/static", "/static/", "/media", "/index.html", "/v1/rooms", "/.well-known/", "/favicon.ico/x"]) {
      const res = await mf.dispatchFetch(`${BASE}${path}`);
      expect(res.status, path).toBe(404);
      await res.arrayBuffer();
    }
    expect(await (await mf.dispatchFetch(`${BASE}/v1/rooms`)).json()).toEqual({ error: "not_found" });
    expect((await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", body: "{}" })).status).toBe(503);
  });

  test("/get and the landing page follow the install settings: TestFlight, then the App Store, then neither", async () => {
    const beta = site({ TESTFLIGHT_URL: "https://testflight.apple.com/join/abc123" });
    const toBeta = await beta.dispatchFetch(`${BASE}/get`, { redirect: "manual" });
    expect(toBeta.status).toBe(302);
    expect(toBeta.headers.get("location")).toBe("https://testflight.apple.com/join/abc123");
    expect(toBeta.headers.get("cache-control")).toBe("no-store");
    expect(await (await beta.dispatchFetch(`${BASE}/`)).text()).toContain("Join the beta on TestFlight");

    const store = site({ APP_STORE_URL: "https://apps.apple.com/app/id6829560061", TESTFLIGHT_URL: "https://testflight.apple.com/join/abc123" });
    const toStore = await store.dispatchFetch(`${BASE}/get`, { redirect: "manual" });
    expect(toStore.headers.get("location")).toBe("https://apps.apple.com/app/id6829560061");
    const page = await (await store.dispatchFetch(`${BASE}/`)).text();
    expect(page).toContain('alt="Download on the App Store"');
    expect(page).toContain('<meta name="apple-itunes-app" content="app-id=6829560061">');
    expect(page).toContain(`<link rel="canonical" href="${BASE}/">`);

    const soon = site({ APP_STORE_URL: "" });
    const home = await soon.dispatchFetch(`${BASE}/get`, { redirect: "manual" });
    expect(home.status).toBe(302);
    expect(home.headers.get("location")).toBe(`${BASE}/`);
    expect(await (await soon.dispatchFetch(`${BASE}/`)).text()).toContain("Coming soon to the App Store");
    expect((await soon.dispatchFetch(`${BASE}/get`, { method: "POST", redirect: "manual" })).status).toBe(404);
  });
});
