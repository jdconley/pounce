import { ROOM_CODE } from "../room/codes";

import { OG_IMAGE_BASE64 } from "./og-image";

const CACHE = "public, max-age=300";
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

const association = (pounces: boolean) =>
  JSON.stringify({
    applinks: {
      details: [
        { appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }, ...(pounces ? [{ "/": "/p/*" }] : [])] },
      ],
    },
  });

const CAT = `<svg class="cat" viewBox="0 0 120 110" role="img" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M18 6 44 30q16-6 32 0L102 6q8 22 4 48 8 10 8 24 0 28-54 28T6 78q0-14 8-24Q10 28 18 6Z"/><circle cx="43" cy="62" r="6" fill="#fff"/><circle cx="77" cy="62" r="6" fill="#fff"/></svg>`;

const STYLE = `body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff7ec;color:#2b2118;font-family:system-ui,sans-serif;text-align:center}main{padding:24px}.cat{width:120px;height:auto;color:#2b2118}h1{margin:16px 0 8px;font-size:1.25rem;font-weight:600}.code{font-size:3.5rem;font-weight:800;letter-spacing:.15em;margin:0 0 24px;font-family:ui-monospace,monospace}a{display:inline-block;padding:12px 24px;border-radius:999px;background:#2b2118;color:#fff7ec;text-decoration:none;font-weight:600}@media (prefers-color-scheme:dark){body{background:#1c1612;color:#fff7ec}.cat{color:#fff7ec}a{background:#fff7ec;color:#1c1612}}`;

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (ch) => ESCAPES[ch] as string);
}

/** Apple fetches this to bind `/j/*` links (and, with streaks on, `/p/*` pounce links) on our domain to the app. */
export function appSiteAssociation(pounces = false): Response {
  return new Response(association(pounces), {
    headers: { "content-type": "application/json", "cache-control": CACHE },
  });
}

/**
 * The landing page for a pounce link (§12.4), for Messages' preview and for
 * people without the app: "Mia wants to play", the bell card, and the
 * TestFlight link. Never cached and never indexed; an unknown, used or
 * expired link is a 404 that says nothing.
 */
export function pouncePage(from: { name: string; cat: number } | null, token: string, testflightUrl: string | undefined, origin: string): Response {
  const headers = { "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex" };
  if (!from) return new Response("Not found", { status: 404, headers: { ...headers, "content-type": "text/plain; charset=utf-8" } });
  const title = escapeHtml(`${from.name} wants to play`);
  const link = testflightUrl?.startsWith("https://") ? `<a href="${escapeHtml(testflightUrl)}">Get the app</a>` : "";
  const og = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="Cat Tower">`,
    `<meta property="og:url" content="${escapeHtml(`${origin}/p/${token}`)}">`,
    `<meta property="og:image" content="${escapeHtml(`${origin}/og/pounce.jpg`)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
${og}
<style>${STYLE}</style>
</head>
<body>
<main>
${CAT}
<h1>${title}</h1>
${link}
</main>
</body>
</html>
`;
  return new Response(html, { headers: { ...headers, "content-type": "text/html; charset=utf-8", "content-security-policy": CSP } });
}

/** The landing page for a shared room link, for people without the app. */
export function sharePage(code: string, testflightUrl: string | undefined, origin: string): Response {
  if (!ROOM_CODE.test(code)) {
    return new Response("Not found", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  const link = testflightUrl?.startsWith("https://")
    ? `<a href="${escapeHtml(testflightUrl)}">Get the app</a>`
    : "";
  const safeCode = escapeHtml(code);
  const og = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="Cat Tower">`,
    `<meta property="og:description" content="${safeCode}">`,
    `<meta property="og:url" content="${escapeHtml(`${origin}/j/${code}`)}">`,
    `<meta property="og:image" content="${escapeHtml(`${origin}/og/room.jpg`)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${safeCode}</title>
${og}
<style>${STYLE}</style>
</head>
<body>
<main>
${CAT}
<h1>Join the game</h1>
<p class="code">${escapeHtml(code)}</p>
${link}
</main>
</body>
</html>
`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": CACHE,
      "content-security-policy": CSP,
    },
  });
}

let ogBytes: Uint8Array<ArrayBuffer> | undefined;

function decodeOgImage(): Uint8Array<ArrayBuffer> {
  const bin = atob(OG_IMAGE_BASE64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** The 1200x630 image Messages shows in the invite bubble. */
export function ogImage(): Response {
  ogBytes ??= decodeOgImage();
  return new Response(ogBytes, {
    headers: { "content-type": "image/jpeg", "cache-control": "public, max-age=86400" },
  });
}
