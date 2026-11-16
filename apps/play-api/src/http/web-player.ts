/**
 * The web player (web player design): a single-page app under `/play/`, built by
 * `apps/play-web` into `./public/play` and deployed with this Worker from the same commit.
 *
 * - `/play/assets/*` and `/play/art/*` carry a content hash in their name: cached for a year.
 * - `/play/sw.js`, `/play/version.json` and `/play/manifest.webmanifest` are checked on every
 *   visit, so a new deploy is found at once.
 * - Every other `/play/...` path is the app itself (`index.html`), which routes on the client:
 *   `/play/j/<code>`, `/play/p/<token>`, `/play/t/<code>`.
 *
 * Nothing here is a route the API owns, and nothing is served from outside `/play/`.
 */
import { WEB_PLAYER_CSP } from "./layout";

type Fetcher = { fetch(input: Request | string, init?: RequestInit): Promise<Response> };

const IMMUTABLE = "public, max-age=31536000, immutable";
const REVALIDATE = "no-cache";
/** A file name the build gave a content hash: `name.<hash>.ext` or `name-<hash>.ext`. */
const HASHED = /^\/play\/(?:assets|art)\/[A-Za-z0-9_.-]+$/;
/** Files that are fetched by name and must always be the newest. */
const FRESH = new Set(["/play/sw.js", "/play/version.json", "/play/manifest.webmanifest"]);
/** Icons the manifest and the page name. */
const ICON = /^\/play\/icons\/[a-z0-9-]+\.png$/;

const SECURITY = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

function withHeaders(res: Response, headers: Record<string, string>): Response {
  const out = new Response(res.body, res);
  for (const [name, value] of Object.entries(headers)) out.headers.set(name, value);
  return out;
}

/** True for a path the web player answers: `/play` and everything under it. */
export const isWebPlayerPath = (pathname: string): boolean => pathname === "/play" || pathname.startsWith("/play/");

/**
 * The web player's answer for `pathname` (a GET or HEAD), or null when the build isn't there
 * (a Worker deployed without it, or tests): the caller answers 404 then.
 */
export async function webPlayer(request: Request, assets: Fetcher | undefined): Promise<Response | null> {
  const url = new URL(request.url);
  const { pathname } = url;
  if (pathname === "/play") return Response.redirect(`${url.origin}/play/${url.search}`, 301);
  if (!assets) return null;
  const file = (path: string) => assets.fetch(new Request(new URL(path, url.origin).toString(), { method: request.method }));
  if (HASHED.test(pathname) || ICON.test(pathname)) {
    const res = await file(pathname);
    if (!res.ok) return null;
    return withHeaders(res, { ...SECURITY, "cache-control": ICON.test(pathname) ? "public, max-age=86400" : IMMUTABLE });
  }
  if (FRESH.has(pathname)) {
    const res = await file(pathname);
    if (!res.ok) return null;
    const extra: Record<string, string> = pathname === "/play/sw.js" ? { "service-worker-allowed": "/play/" } : {};
    if (pathname === "/play/manifest.webmanifest") extra["content-type"] = "application/manifest+json";
    return withHeaders(res, { ...SECURITY, ...extra, "cache-control": REVALIDATE });
  }
  // A path with a dot in its last part is a file that isn't there, not a page.
  if ((pathname.split("/").at(-1) ?? "").includes(".")) return null;
  const res = await file("/play/index.html");
  if (!res.ok) return null;
  return withHeaders(res, {
    ...SECURITY,
    "content-type": "text/html; charset=utf-8",
    "cache-control": REVALIDATE,
    "content-security-policy": WEB_PLAYER_CSP,
    "x-robots-tag": "noindex",
  });
}
