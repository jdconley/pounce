/// <reference lib="webworker" />
/**
 * The web player's service worker (web player design, "PWA"). The shell is cached when the
 * worker installs, so the app opens offline; art and sounds are cached the first time they are
 * used. Hashed files never change, so they are served from the cache; the page itself comes from
 * the network when it can, so a new deploy is seen at once. A new worker waits until the page
 * says it is a safe moment (`skipWaiting`), never mid-hand. The API and game sockets are never
 * touched.
 */
declare const __PRECACHE__: string[];
declare const __BUILD__: string;

const SHELL = `pounce-shell-${__BUILD__}`;
const ASSETS = "pounce-assets";
const PAGE = "/play/";
let claim = false;
const sw = self as unknown as ServiceWorkerGlobalScope;

sw.addEventListener("install", (event: ExtendableEvent) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL);
      await cache.addAll([PAGE, ...__PRECACHE__]);
      const assets = await caches.open(ASSETS);
      // Hashed files from the shell go in the long-lived cache too.
      for (const url of __PRECACHE__) {
        if (!url.startsWith("/play/assets/")) continue;
        const hit = await cache.match(url);
        if (hit) await assets.put(url, hit);
      }
    })(),
  );
});

sw.addEventListener("activate", (event: ExtendableEvent) => {
  event.waitUntil(
    (async () => {
      const keep = new Set([SHELL, ASSETS]);
      for (const key of await caches.keys()) if (!keep.has(key)) await caches.delete(key);
      if (claim) await sw.clients.claim();
    })(),
  );
});

sw.addEventListener("message", (event: ExtendableMessageEvent) => {
  if ((event.data as { t?: string } | null)?.t === "skipWaiting") {
    claim = true;
    void sw.skipWaiting();
  }
});

async function page(request: Request): Promise<Response> {
  try {
    const net = await Promise.race([
      fetch(request),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("slow")), 4000)),
    ]);
    if (net.ok) {
      const cache = await caches.open(SHELL);
      await cache.put(PAGE, net.clone());
    }
    return net;
  } catch {
    const cached = (await caches.match(PAGE)) ?? (await caches.match(request));
    return cached ?? new Response("Offline", { status: 503, headers: { "content-type": "text/plain" } });
  }
}

async function asset(request: Request): Promise<Response> {
  const cached = await caches.match(request);
  if (cached) return cached;
  const net = await fetch(request);
  if (net.ok) {
    const cache = await caches.open(ASSETS);
    await cache.put(request, net.clone());
  }
  return net;
}

sw.addEventListener("fetch", (event: FetchEvent) => {
  const { request } = event;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== sw.location.origin || !url.pathname.startsWith("/play/")) return;
  if (url.pathname === "/play/sw.js" || url.pathname === "/play/version.json") return;
  if (request.mode === "navigate") {
    event.respondWith(page(request));
    return;
  }
  if (url.pathname.startsWith("/play/assets/") || url.pathname.startsWith("/play/icons/") || url.pathname === "/play/manifest.webmanifest") {
    event.respondWith(asset(request));
  }
});
