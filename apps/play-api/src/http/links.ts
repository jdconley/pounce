import { olderThan } from "../app/version";
import { DEFAULT_GAME, gameTitle, isGameId, sameRoomGame } from "../games";
import { ROOM_CODE } from "../room/codes";

import { CACHE, CSP, css, escapeHtml, shell } from "./layout";
import { OG_IMAGE_BASE64 } from "./og-image";
import { MEDIA } from "./site-media";

import type { InvitePeek } from "../safety/safety";

const association = (pounces: boolean, tv: boolean, easel: boolean) =>
  JSON.stringify({
    applinks: {
      details: [
        {
          appIDs: ["B222J9J7B8.com.conleychaos.play"],
          components: [{ "/": "/j/*" }, ...(pounces ? [{ "/": "/p/*" }] : []), ...(tv ? [{ "/": "/tv/*" }] : []), ...(easel ? [{ "/": "/e/*" }] : [])],
        },
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
.game.birdwatch{background:var(--lime);color:var(--ink)}
.game.purrtrait{background:var(--magenta);color:var(--ink)}
.game.tumble{background:var(--orange);color:var(--ink)}
.table{margin:4px auto 0;color:var(--muted);font-weight:700;overflow-wrap:anywhere}
.go{display:block;margin:20px 0 0;padding:15px 20px;border:3px solid var(--ink);border-radius:999px;background:linear-gradient(#FFC21A,#FF8A00);box-shadow:0 6px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.35rem;font-weight:900;text-decoration:none}
.go:active{transform:translateY(4px);box-shadow:0 2px 0 var(--ink)}
.go.done{background:linear-gradient(#B8F25A,#7CC51C)}
.next{margin:12px auto 0;font-weight:700}
.code{margin:20px 0 0;padding:10px 12px 12px;background:var(--inset);border:3px solid var(--ink);border-radius:20px}
.code span{display:block;color:var(--muted);font-size:.9rem;font-weight:800;letter-spacing:.06em;text-transform:uppercase}
.code strong{display:block;font-family:var(--round);font-size:clamp(2.4rem,13vw,3.2rem);font-weight:900;letter-spacing:.14em;line-height:1.1;user-select:all;-webkit-user-select:all}
.note{margin:14px auto 0;color:var(--muted);font-size:.92rem}
.go.web{background:linear-gradient(#6AF5EA,#00B3A6)}
.alt{margin:14px auto 0;font-weight:800}
.alt a{color:var(--link);font-family:var(--round);font-size:1.1rem;font-weight:900}
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

/**
 * Apple fetches this to bind `/j/*` links on our domain to the app: with pushes on, `/p/*` pounce
 * links too, and with `TV` on, `/tv/*` TV links (docs/tv-protocol.md). With `TV` off a `/tv/` link
 * is a 404, so the app doesn't claim it. `easel`: Purrtrait's TV QR links, `/e/*`, with
 * `PURRTRAIT_APPLINKS` on (since 1.4, the first version that draws the game, went to App Review).
 */
export function appSiteAssociation(pounces = false, tv = false, easel = false): Response {
  return new Response(association(pounces, tv, easel), {
    headers: { "content-type": "application/json", "cache-control": CACHE },
  });
}

/**
 * Where the pages send people without the app: the App Store listing, or before launch TestFlight.
 * `storeVersion` is the version the App Store gives out right now (Apple's lookup, null when not
 * known yet): a page only promises what that version can do.
 */
export type Install = {
  appStoreUrl?: string | undefined;
  testflightUrl?: string | undefined;
  storeVersion?: string | null;
  /**
   * Who is looking (web player design, "The way in"): "apple" for an iPhone or iPad, where the
   * app stays the big button and the browser is a link under it; "other" for everyone else,
   * where playing in the browser is the big button. Unset: as "apple".
   */
  viewer?: "apple" | "other";
};

/** The viewer from a request's user agent: only an iPhone, iPad or iPod is "apple". */
export function viewerOf(userAgent: string | null): "apple" | "other" {
  return /\b(iPhone|iPad|iPod)\b/.test(userAgent ?? "") ? "apple" : "other";
}

/** The first app version that pastes an invite (first-run funnel, Part 2). */
export const PASTE_SINCE = "1.1";

/** The Dish, to the install logic: an "app game" that needs `DISH_SINCE`. */
const DISH_GAME = "daily";

/**
 * The first App Store version with the Daily Dish. Until Apple's lookup names one at least this
 * new, the Dish's page sends iPhones to the beta and shows no App Store banner.
 */
export const DISH_SINCE = "1.2";

/**
 * The first App Store version with Birdwatch. TestFlight builds have it since 1.3, but 1.3 never
 * reached the App Store (it was pulled from review for 1.4). Until Apple's lookup names 1.4, a
 * Birdwatch invite sends iPhones to the beta and says the game is coming to the iPhone app.
 */
export const BIRDWATCH_SINCE = "1.4";

/**
 * Where the next app version stands, said after "in 1.4" on the site while Apple reviews it. When
 * 1.4 is on the App Store, the lines that use it change to say what the app has.
 */
export const IN_REVIEW = "now in App Review";

/** The first App Store version with Toy Tumble. Until then it plays in the browser only. */
export const TUMBLE_SINCE = "1.4";

/**
 * The first iPhone and Apple TV app version with Purrtrait (`GAME_MIN_APP`). Until then it plays in
 * the browser and on the browser TV page. Its links never go to the App Store: a Purrtrait table is
 * joined only from its TV's code.
 */
export const PURRTRAIT_SINCE = "1.4";

/** The first app version that can play each game, for games newer than the first release. */
export const GAME_SINCE: Readonly<Record<string, string>> = { tiles: "1.1", birdwatch: BIRDWATCH_SINCE, tumble: TUMBLE_SINCE, [DISH_GAME]: DISH_SINCE };

/**
 * Games no build of the app plays yet, the TestFlight beta included: Toy Tumble, while TestFlight
 * still builds 1.3. A link to one of these tables plays in the browser on every device and says
 * which version brings it to the iPhone, with no Get Pounce, no beta and no App Store banner. Take
 * a game out once the beta plays it; `GAME_SINCE` then sends iPhones to the beta until the App
 * Store has it.
 */
export const BETA_LACKS: ReadonlySet<string> = new Set(["tumble"]);

/**
 * Whether the App Store's current version is at least `since`. Unknown counts as no: a page
 * then sends people to the beta or says the older way, and corrects itself once Apple answers.
 */
export function storeHas(install: Install, since: string): boolean {
  if (!https(install.appStoreUrl) || !install.storeVersion) return false;
  return !olderThan(install.storeVersion, since);
}

/** Whether the App Store's version can open a table of `game`. */
function storePlays(install: Install, game: string): boolean {
  const since = GAME_SINCE[game];
  return since === undefined || storeHas(install, since);
}

/** A table game the App Store has the app for, but whose version there can't open it yet. */
function notInStoreYet(install: Install, game: string): boolean {
  return isGameId(game) && https(install.appStoreUrl) !== null && !storePlays(install, game);
}

/** A table game that plays only in the browser for now: no app build has it, the beta included. */
function browserOnly(install: Install, game: string): boolean {
  return BETA_LACKS.has(game) && !storePlays(install, game);
}

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
function banner(install: Install, pageUrl: string, game: string = DEFAULT_GAME): string {
  // No "Get" for a table the App Store's version can't open: the button goes to the beta then.
  if (!storePlays(install, game)) return "";
  const id = appStoreId(install.appStoreUrl);
  return id ? `<meta name="apple-itunes-app" content="app-id=${id}, app-argument=${escapeHtml(pageUrl)}">\n` : "";
}

/**
 * The store the button opens: the App Store when it's set and its version plays `game`, else
 * TestFlight, else none.
 */
function store(install: Install, game: string = DEFAULT_GAME): { url: string; beta: boolean } | null {
  const listing = https(install.appStoreUrl);
  if (listing && storePlays(install, game)) return { url: listing, beta: false };
  const beta = https(install.testflightUrl);
  return beta ? { url: beta, beta: true } : null;
}

/** One line under the button, so nobody is surprised to land on a beta page. */
const BETA_NOTE = `<p class="note">Pounce is in beta. This opens TestFlight.</p>`;

/** The beta line for a game the App Store's version can't open yet: it's the game that's coming, not Pounce. */
const comingNote = (game: string): string => `<p class="note">${escapeHtml(gameTitle(game))} is coming to the iPhone app. This opens the beta on TestFlight.</p>`;

/**
 * The button: copies `invite` (the page's own link) and opens the store; with nothing to copy,
 * just the store. Then the one line that says what to do once it's installed.
 */
function getButton(install: Install, invite: string | null, opts: { game?: string; code?: boolean; web?: string } = {}): string {
  const web = opts.web ? escapeHtml(opts.web) : null;
  if (web && opts.game && browserOnly(install, opts.game)) {
    // No app plays it yet, not even the beta: the browser is the way in for everyone.
    const when = install.viewer === "other" ? "" : `\n<p class="note">${escapeHtml(gameTitle(opts.game))} is coming to the iPhone app in ${GAME_SINCE[opts.game] ?? "a later version"}, ${IN_REVIEW}.</p>`;
    return `<a class="go web" href="${web}">Play in your browser</a>${when}`;
  }
  const to = store(install, opts.game);
  if (web && install.viewer === "other") {
    // Not an iPhone: the browser is the way in; the app is for later.
    const app = to ? `\n<p class="alt"><a href="${escapeHtml(to.url)}">Get the iPhone app</a></p>` : "";
    return `<a class="go web" href="${web}">Play in your browser</a>${app}`;
  }
  const browser = web ? `\n<p class="alt"><a href="${web}">Play in your browser</a></p>` : "";
  if (!to) return browser.trimStart();
  const href = escapeHtml(to.url);
  // The beta is always the newest app; the App Store's version may not paste yet.
  const paste = to.beta || storeHas(install, PASTE_SINCE);
  const next = paste ? "Then open Pounce and tap Paste." : opts.code ? "Then open Pounce and tap Join." : "Then tap this link again.";
  const button = invite
    ? `<a class="go" id="get" href="${href}" data-invite="${escapeHtml(invite)}" data-copied="Invite copied">Get Pounce</a>
<p class="next">${next}</p>`
    : `<a class="go" href="${href}">Get Pounce</a>`;
  const note = !to.beta ? "" : opts.game && notInStoreYet(install, opts.game) ? `\n${comingNote(opts.game)}` : `\n${BETA_NOTE}`;
  return `${button}${note}${browser}`;
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
  // A game with no preview of its own yet (Birdwatch, until its release) uses the site's.
  const previews: Partial<Record<string, string>> = MEDIA.invite.previews;
  const image = o.game === DISH_GAME ? MEDIA.invite.dish : isGameId(o.game) ? (previews[o.game] ?? MEDIA.og.src) : MEDIA.og.src;
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
    head: `${banner(install, url, game)}${previewTags({ title, description: gameTitle(game), url, origin, game })}\n`,
    script: true,
    body: [face(from.cat), `<h1>${escapeHtml(title)}</h1>`, gameChip(game), getButton(install, url, { game, web: `/play/p/${token}` })]
      .filter(Boolean)
      .join("\n"),
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
  // A same-room table is joined only from its TV's code (Purrtrait, design §5.1): no way in here.
  if (known && sameRoomGame(known.game)) return scanPage();
  const url = `${origin}/j/${code}`;
  const host = known?.host ?? null;
  const game = known?.game ?? DEFAULT_GAME;
  const title = host ? `${host.name} saved you a seat` : "Come play Pounce";
  const description = known ? [gameTitle(game), known.table].filter(Boolean).join(" · ") : `Table ${code}`;
  // "Update it first" only when an update helps: not for a game the App Store's version can't open yet.
  const update = known ? game !== DEFAULT_GAME && !notInStoreYet(install, game) && !browserOnly(install, game) : newest;
  const html = page({
    title: escapeHtml(title),
    head: `${banner(install, url, game)}${previewTags({ title, description, url, origin, game: known ? game : "" })}\n`,
    script: true,
    body: [
      face(host?.cat ?? null),
      `<h1>${escapeHtml(title)}</h1>`,
      known ? gameChip(game) : "",
      known?.table ? `<p class="table">${escapeHtml(known.table)}</p>` : "",
      getButton(install, url, { game, code: true, web: `/play/j/${code}` }),
      `<div class="code"><span>Table code</span><strong>${escapeHtml(code)}</strong></div>`,
      update ? `<p class="note">Have Pounce? Update it first.</p>` : "",
    ]
      .filter(Boolean)
      .join("\n"),
  });
  return new Response(html, { headers: { ...HTML, "content-security-policy": INVITE_CSP } });
}

/**
 * A Purrtrait table's links that can't let anyone in: `/j/<code>`, and `/e/<code>` without a live
 * near key (design §5.1). Only the TV's own QR, fresh, is a way in, so the page names nobody and
 * offers no button, no code and no store. Never cached and never indexed, like the invite pages.
 */
export function scanPage(): Response {
  const title = "Scan the code on the TV.";
  const html = page({ title, body: [CAT, `<h1>${title}</h1>`, gameChip("purrtrait")].join("\n") });
  return new Response(html, { headers: { ...HTML, "content-security-policy": CSP } });
}

/**
 * Where a Daily Dish share link lands (`/daily`, only while `DAILY` is on): what the Dish is, and
 * the ways in, the browser and the app. Nothing about a puzzle, a person or a result, so a shared
 * card spoils nothing. Never cached and never indexed, like the invite pages.
 */
export function dailyPage(install: Install, origin: string): Response {
  const title = "The Daily Dish";
  const url = `${origin}/daily`;
  const html = page({
    title,
    head: `${banner(install, url, DISH_GAME)}${previewTags({ title, description: "Four new puzzles every day.", url, origin, game: DISH_GAME })}\n`,
    body: [CAT, `<h1>${title}</h1>`, `<p class="lead">Four new puzzles every day.</p>`, getButton(install, null, { game: DISH_GAME, web: "/play/daily" })].join("\n"),
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
