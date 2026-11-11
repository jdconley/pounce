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

const STYLE = `body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff7ec;color:#2b2118;font-family:system-ui,sans-serif;text-align:center}main{padding:24px}.cat{width:120px;height:auto;color:#2b2118}h1{margin:16px 0 8px;font-size:1.25rem;font-weight:600}p{max-width:32em;margin:0 auto 20px;line-height:1.45}.code{font-size:3.5rem;font-weight:800;letter-spacing:.15em;margin:0 auto 8px;font-family:ui-monospace,monospace}a{display:inline-block;padding:12px 24px;border-radius:999px;background:#2b2118;color:#fff7ec;text-decoration:none;font-weight:600}@media (prefers-color-scheme:dark){body{background:#1c1612;color:#fff7ec}.cat{color:#fff7ec}a{background:#fff7ec;color:#1c1612}}`;

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

/** Where the pages send people without the app: the App Store listing, or before launch TestFlight. */
export type Install = { appStoreUrl?: string | undefined; testflightUrl?: string | undefined };

const https = (url: string | undefined): string | null => (url?.startsWith("https://") ? url : null);

/** The App Store app id in `https://apps.apple.com/.../id123456789`, or null. */
export function appStoreId(url: string | undefined): string | null {
  const ok = https(url);
  if (!ok) return null;
  return /\/id(\d{6,12})(?:[/?#]|$)/.exec(ok)?.[1] ?? null;
}

/**
 * Safari's Smart App Banner (`apple-itunes-app`): "Open" for people with Pounce, "Get" for
 * people without, and the app gets this page's link back as `app-argument`. Only once the App
 * Store id is known (`APP_STORE_URL`); without it there is no banner.
 */
function banner(install: Install, pageUrl: string): string {
  const id = appStoreId(install.appStoreUrl);
  return id ? `<meta name="apple-itunes-app" content="app-id=${id}, app-argument=${escapeHtml(pageUrl)}">\n` : "";
}

/** The install button: the App Store when it's set, else TestFlight, else nothing. */
function getTheApp(install: Install): string {
  const url = https(install.appStoreUrl) ?? https(install.testflightUrl);
  return url ? `<a href="${escapeHtml(url)}">Get the app</a>` : "";
}

const NOINDEX = { "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex" };

function page(opts: { title: string; head?: string; body: string }): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${opts.title}</title>
${opts.head ?? ""}<style>${STYLE}</style>
</head>
<body>
<main>
${CAT}
${opts.body}
</main>
</body>
</html>
`;
}

/**
 * A friendly 404 for a link that no longer works: an invite that expired, was used, or
 * never existed. Says nothing about which, and nothing about who sent it.
 */
export function deadLinkPage(install: Install): Response {
  const html = page({
    title: "This invite has expired",
    body: `<h1>This invite has expired</h1>
<p>Invite links work for 7 days, until someone plays. Ask the person who sent it for a new one.</p>
${getTheApp(install)}`,
  });
  return new Response(html, {
    status: 404,
    headers: { ...NOINDEX, "content-type": "text/html; charset=utf-8", "content-security-policy": CSP },
  });
}

/**
 * The landing page for a pounce link (§12.4), for Messages' preview and for
 * people without the app: "Mia wants to play", the bell card, how to get the
 * app and come back. Never cached and never indexed; an unknown, used or
 * expired link is a 404 page that says only that it has expired.
 */
export function pouncePage(from: { name: string; cat: number } | null, token: string, install: Install, origin: string): Response {
  if (!from) return deadLinkPage(install);
  const title = escapeHtml(`${from.name} wants to play`);
  const url = `${origin}/p/${token}`;
  const og = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="Cat Tower">`,
    `<meta property="og:url" content="${escapeHtml(url)}">`,
    `<meta property="og:image" content="${escapeHtml(`${origin}/og/pounce.jpg`)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
  const html = page({
    title,
    head: `${banner(install, url)}${og}\n`,
    body: `<h1>${title}</h1>
<p>Have Pounce? Tap this link on your iPhone or iPad. No app yet? Install it, then tap this link again.</p>
${getTheApp(install)}`,
  });
  return new Response(html, { headers: { ...NOINDEX, "content-type": "text/html; charset=utf-8", "content-security-policy": CSP } });
}

/** The landing page for a shared room link, for people without the app. */
export function sharePage(code: string, install: Install, origin: string): Response {
  if (!ROOM_CODE.test(code)) return deadLinkPage(install);
  const safeCode = escapeHtml(code);
  const url = `${origin}/j/${code}`;
  const og = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="Cat Tower">`,
    `<meta property="og:description" content="${safeCode}">`,
    `<meta property="og:url" content="${escapeHtml(url)}">`,
    `<meta property="og:image" content="${escapeHtml(`${origin}/og/room.jpg`)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
  const html = page({
    title: safeCode,
    head: `${banner(install, url)}${og}\n`,
    body: `<h1>Join the game</h1>
<p class="code">${safeCode}</p>
<p>No app yet? Install Pounce, then tap this link again. Or open Pounce, tap Join and enter the code ${safeCode}.</p>
${getTheApp(install)}`,
  });
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
