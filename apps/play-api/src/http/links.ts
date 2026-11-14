import { DEFAULT_GAME, gameTitle, isGameId } from "../games";
import { ROOM_CODE } from "../room/codes";

import { CACHE, CSP, css, escapeHtml, shell } from "./layout";
import { OG_IMAGE_BASE64 } from "./og-image";
import { MEDIA } from "./site-media";

import type { InvitePeek } from "../safety/safety";

const association = (pounces: boolean) =>
  JSON.stringify({
    applinks: {
      details: [
        { appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }, ...(pounces ? [{ "/": "/p/*" }] : [])] },
      ],
    },
  });

const CAT = `<svg class="cat" viewBox="0 0 120 110" role="img" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M18 6 44 30q16-6 32 0L102 6q8 22 4 48 8 10 8 24 0 28-54 28T6 78q0-14 8-24Q10 28 18 6Z"/><circle cx="43" cy="62" r="6" fill="#fff"/><circle cx="77" cy="62" r="6" fill="#fff"/></svg>`;

/**
 * The invite card: who invited you and to what, one big button, and the table code as the way
 * in that always works. One panel in the middle of the page, full width on a phone.
 */
const STYLE = css(`
.invite{display:flex;align-items:center;justify-content:center;padding:12px 12px 8px;text-align:center}
.card{width:100%;max-width:440px;padding:22px 20px 26px;background:var(--panel);color:var(--text);border:3px solid var(--ink);border-radius:28px;box-shadow:0 8px 0 var(--ink)}
.cat{width:104px;height:auto;color:var(--ink)}
.host{display:block;width:150px;height:150px;margin:-6px auto 0}
.card h1{margin:6px 0 10px;font-size:clamp(1.55rem,7.4vw,2rem);color:var(--h1);overflow-wrap:anywhere}
.game{display:inline-block;margin:0 0 6px;padding:5px 16px;border:3px solid var(--ink);border-radius:999px;font-family:var(--round);font-size:1.05rem;font-weight:900;line-height:1.2;box-shadow:0 3px 0 var(--ink)}
.game.cat-tower{background:var(--violet);color:#fff}
.game.tiles{background:var(--sky);color:var(--ink)}
.table{margin:4px auto 0;color:var(--muted);font-weight:700;overflow-wrap:anywhere}
.go{display:block;margin:20px 0 0;padding:15px 20px;border:3px solid var(--ink);border-radius:999px;background:linear-gradient(#FFC21A,#FF8A00);box-shadow:0 6px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.35rem;font-weight:900;text-decoration:none}
.go:active{transform:translateY(4px);box-shadow:0 2px 0 var(--ink)}
.go.done{background:linear-gradient(#B8F25A,#7CC51C)}
.next{margin:12px auto 0;font-weight:700}
.code{margin:20px 0 0;padding:10px 12px 12px;background:var(--inset);border:3px solid var(--ink);border-radius:20px}
.code span{display:block;color:var(--muted);font-size:.9rem;font-weight:800;letter-spacing:.06em;text-transform:uppercase}
.code strong{display:block;font-family:var(--round);font-size:clamp(2.4rem,13vw,3.2rem);font-weight:900;letter-spacing:.14em;line-height:1.1;user-select:all;-webkit-user-select:all}
.note{margin:14px auto 0;color:var(--muted);font-size:.92rem}
.card p.lead{max-width:24em;margin:0 auto}
@media (prefers-color-scheme:dark){.cat{color:#fff}.cat circle{fill:var(--ink)}}
`);

/**
 * The one script the invite pages run: the button copies the invite link, so the app can offer
 * "Paste invite" on its first launch (the NativeLink idea, without a vendor), then goes to the
 * store. Without a clipboard (or without scripts) the button is a plain link to the store.
 * Allowed by its hash alone (`INVITE_CSP`); `links.test.ts` checks the hash.
 */
export const INVITE_SCRIPT = `(function(){var b=document.getElementById("get");if(!b)return;b.addEventListener("click",function(e){var c=navigator.clipboard;if(!c||!c.writeText)return;e.preventDefault();var go=function(){location.href=b.href};c.writeText(b.getAttribute("data-invite")).then(function(){b.classList.add("done");b.textContent=b.getAttribute("data-copied");setTimeout(go,600)},go)})})();`;
export const INVITE_SCRIPT_HASH = "sha256-NHWXU2onSqv10XNR64R7LEbWf1mVG2lmEbNfyQlfj7g=";

/** The invite pages load the inviter's cat from /static and run their one script. */
export const INVITE_CSP = `default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; script-src '${INVITE_SCRIPT_HASH}'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

/** Apple fetches this to bind `/j/*` links (and, with streaks on, `/p/*` pounce links) on our domain to the app. */
export function appSiteAssociation(pounces = false): Response {
  return new Response(association(pounces), {
    headers: { "content-type": "application/json", "cache-control": CACHE },
  });
}

/** Where the pages send people without the app: the App Store listing, or before launch TestFlight. */
export type Install = { appStoreUrl?: string | undefined; testflightUrl?: string | undefined };

export const https = (url: string | undefined): string | null => (url?.startsWith("https://") ? url : null);

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

/** The store the button opens: the App Store when it's set, else TestFlight, else none. */
function store(install: Install): { url: string; beta: boolean } | null {
  const listing = https(install.appStoreUrl);
  if (listing) return { url: listing, beta: false };
  const beta = https(install.testflightUrl);
  return beta ? { url: beta, beta: true } : null;
}

/** One line under the button, so nobody is surprised to land on a beta page. */
const BETA_NOTE = `<p class="note">Pounce is in beta. This opens TestFlight.</p>`;

/**
 * The button: copies `invite` (the page's own link) and opens the store; with nothing to copy,
 * just the store. Then the one line that says what to do once it's installed.
 */
function getButton(install: Install, invite: string | null): string {
  const to = store(install);
  if (!to) return "";
  const href = escapeHtml(to.url);
  const button = invite
    ? `<a class="go" id="get" href="${href}" data-invite="${escapeHtml(invite)}" data-copied="Invite copied">Get Pounce</a>
<p class="next">Then open Pounce and tap Paste invite.</p>`
    : `<a class="go" href="${href}">Get Pounce</a>`;
  return `${button}${to.beta ? `\n${BETA_NOTE}` : ""}`;
}

const NOINDEX = { "cache-control": "no-store", "referrer-policy": "no-referrer", "x-robots-tag": "noindex" };
const HTML = { ...NOINDEX, "content-type": "text/html; charset=utf-8" };

function page(opts: { title: string; head?: string; body: string; script?: boolean }): string {
  return shell({
    title: opts.title,
    ...(opts.head === undefined ? {} : { head: opts.head }),
    style: STYLE,
    links: false,
    body: `<main class="invite">
<div class="card">
${opts.body}
</div>
</main>${opts.script ? `\n<script>${INVITE_SCRIPT}</script>` : ""}`,
  });
}

/** Who invited you: their cat, or the plain one when nobody is named. */
function face(cat: number | null): string {
  const art = cat === null ? undefined : MEDIA.invite.cats[cat];
  return art ? `<img class="host" src="${art}" alt="" width="150" height="150">` : CAT;
}

/** The game as a chip in its shelf colour. A game this server has no name for gets none. */
function gameChip(game: string): string {
  return isGameId(game) ? `<p class="game ${game}">${escapeHtml(gameTitle(game))}</p>` : "";
}

/** The Open Graph and Twitter tags Messages reads for its preview (TN3156: server-rendered, no scripts). */
function previewTags(o: { title: string; description: string; url: string; origin: string; game: string }): string {
  const image = isGameId(o.game) ? MEDIA.invite.previews[o.game] : MEDIA.og.src;
  return [
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Pounce">`,
    `<meta property="og:title" content="${escapeHtml(o.title)}">`,
    `<meta property="og:description" content="${escapeHtml(o.description)}">`,
    `<meta property="og:url" content="${escapeHtml(o.url)}">`,
    `<meta property="og:image" content="${escapeHtml(`${o.origin}${image}`)}">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
}

/**
 * A friendly 404 for a link that no longer works: an invite that expired, was used, or
 * never existed, or a table whose game is over. Says nothing about which, and nothing about
 * who sent it.
 */
export function deadLinkPage(install: Install): Response {
  const html = page({
    title: "This invite has expired",
    body: `${CAT}
<h1>This invite has expired</h1>
<p class="lead">Ask for a new link.</p>
${getButton(install, null)}`,
  });
  return new Response(html, { status: 404, headers: { ...HTML, "content-security-policy": CSP } });
}

/**
 * The landing page for a pounce link (§12.4), for Messages' preview and for people without the
 * app: "Mia wants to play", the game, and the button that copies the link and gets the app.
 * Never cached and never indexed; an unknown, used or expired link is the expired page.
 * A link pounce always deals a new table of `game` (Cat Tower: the app's invite has no game).
 */
export function pouncePage(
  from: { name: string; cat: number } | null,
  token: string,
  install: Install,
  origin: string,
  game: string = DEFAULT_GAME,
): Response {
  if (!from) return deadLinkPage(install);
  const title = `${from.name} wants to play`;
  const url = `${origin}/p/${token}`;
  const html = page({
    title: escapeHtml(title),
    head: `${banner(install, url)}${previewTags({ title, description: gameTitle(game), url, origin, game })}\n`,
    script: true,
    body: [face(from.cat), `<h1>${escapeHtml(title)}</h1>`, gameChip(game), getButton(install, url)].filter(Boolean).join("\n"),
  });
  return new Response(html, { headers: { ...HTML, "content-security-policy": INVITE_CSP } });
}

/**
 * The landing page for a table's link (`/j/<code>`), for Messages' preview and for people
 * without the app: who saved you a seat, the game and the table, the button, and the code.
 * `peek` is what the table may say of itself (`peekInvite`): `hidden` names nobody and is the
 * same page for every code, `gone` is the expired page. `newest`: some tables need the newest
 * app (the `GAMES` flag), so a page that can't say the game says what to do then; one that can
 * says it only for a game other than Cat Tower.
 */
export function sharePage(code: string, install: Install, origin: string, peek: InvitePeek | "gone" | "hidden" = "hidden", newest = false): Response {
  if (!ROOM_CODE.test(code) || peek === "gone") return deadLinkPage(install);
  const known = peek === "hidden" ? null : peek;
  const url = `${origin}/j/${code}`;
  const host = known?.host ?? null;
  const game = known?.game ?? DEFAULT_GAME;
  const title = host ? `${host.name} saved you a seat` : "Come play Pounce";
  const description = known ? [gameTitle(game), known.table].filter(Boolean).join(" · ") : `Table ${code}`;
  const update = known ? game !== DEFAULT_GAME : newest;
  const html = page({
    title: escapeHtml(title),
    head: `${banner(install, url)}${previewTags({ title, description, url, origin, game: known ? game : "" })}\n`,
    script: true,
    body: [
      face(host?.cat ?? null),
      `<h1>${escapeHtml(title)}</h1>`,
      known ? gameChip(game) : "",
      known?.table ? `<p class="table">${escapeHtml(known.table)}</p>` : "",
      getButton(install, url),
      `<div class="code"><span>Table code</span><strong>${escapeHtml(code)}</strong></div>`,
      update ? `<p class="note">Have Pounce? Update it first.</p>` : "",
    ]
      .filter(Boolean)
      .join("\n"),
  });
  return new Response(html, { headers: { ...HTML, "content-security-policy": INVITE_CSP } });
}

let ogBytes: Uint8Array<ArrayBuffer> | undefined;

function decodeOgImage(): Uint8Array<ArrayBuffer> {
  const bin = atob(OG_IMAGE_BASE64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** The 1200x630 image older invite previews (`/og/room.jpg`, `/og/pounce.jpg`) still point at. */
export function ogImage(): Response {
  ogBytes ??= decodeOgImage();
  return new Response(ogBytes, {
    headers: { "content-type": "image/jpeg", "cache-control": "public, max-age=86400" },
  });
}
