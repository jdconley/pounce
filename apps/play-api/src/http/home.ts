/**
 * The landing page at `/`: what Pounce is, the real game (the App Store screenshots and a short
 * clip cut from the App Store preview), and how to install it. Static HTML, no scripts; images
 * and the clip come from this Worker's own /static files (scripts/build-site-media.mjs).
 *
 * The copy follows the App Store listing. The kids and privacy claims go only as far as the
 * privacy policy (privacy.ts) does: change them together.
 */
import { CACHE, css, escapeHtml, shell } from "./layout";
import { appStoreId, https } from "./links";
import { MEDIA } from "./site-media";

import type { Install } from "./links";

/**
 * The landing page loads its own images and clip, and still nothing from any other host. No
 * script runs here, so `connect-src 'self'` opens nothing; it is there so that audit tools
 * (Lighthouse) can fetch /robots.txt and /llms.txt from the page they are checking.
 */
export const HOME_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; media-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const NAME = "Pounce: Family Games";
const SUBTITLE = "Card game for couples and kids";
const DESCRIPTION =
  "Game night, one turn at a time. Play Cat Tower with your partner, your kids or the whole family, on one phone or from anywhere.";

/** How the page offers the app: the App Store, else the TestFlight beta, else "coming soon". */
export type InstallState = { kind: "store"; url: string } | { kind: "beta"; url: string } | { kind: "soon" };

export function installState(install: Install): InstallState {
  const store = https(install.appStoreUrl);
  if (store) return { kind: "store", url: store };
  const beta = https(install.testflightUrl);
  return beta ? { kind: "beta", url: beta } : { kind: "soon" };
}

type Art = { readonly width: number; readonly height: number; readonly webp: string; readonly png: string };

/** A decorative piece of the app's art: WebP with a PNG fallback, hidden from screen readers. */
const art = (a: Art, cls = ""): string =>
  `<picture><source type="image/webp" srcset="${a.webp}"><img${cls ? ` class="${cls}"` : ""} src="${a.png}" alt="" width="${a.width}" height="${a.height}" loading="lazy" decoding="async"></picture>`;

/** The App Store screenshots, in upload order, with what each one shows (AppStore/captions.md). */
const SHOTS = [
  "Game night, a turn at a time. The Cat Tower card table on your turn, with your hand of cards fanned along the bottom.",
  "Play your person. Keep the streak. A 128-day streak with one person, with two cats beside a cat tower.",
  "Room for the whole family. A lobby with five people and a House Cat bot seated around the rug, under the room code.",
  "Climb all ten levels. The scoreboard above the list of levels, each level naming the sets and runs it needs.",
  "Safe for kids. No chat. No ads. A child's first launch: pick a cat, and a name from the list.",
  "Take the crown. Game over, with the winning cat wearing a crown.",
] as const;

const SHOT_SIZES = "(min-width: 1100px) 170px, 220px";

const srcset = (files: readonly { readonly src: string; readonly w: number }[]): string => files.map((f) => `${f.src} ${f.w}w`).join(", ");

const shots = (): string =>
  MEDIA.shots
    .map(
      (s, i) =>
        `<li><picture><source type="image/webp" srcset="${srcset(s.webp)}" sizes="${SHOT_SIZES}"><img src="${s.jpg[0].src}" srcset="${srcset(s.jpg)}" sizes="${SHOT_SIZES}" alt="${SHOTS[i] as string}" width="${s.width}" height="${s.height}" loading="lazy" decoding="async"></picture></li>`,
    )
    .join("\n");

/** The QR code for `/get`, for people reading on a computer; shown only on wide screens with a mouse. */
const qr = (line: string): string => {
  const q = MEDIA.qr;
  const quiet = 3;
  const side = q.size + quiet * 2;
  return `<div class="qr"><svg viewBox="${-quiet} ${-quiet} ${side} ${side}" width="112" height="112" role="img" aria-label="QR code for play.conleychaos.com/get" shape-rendering="crispEdges"><rect x="${-quiet}" y="${-quiet}" width="${side}" height="${side}" fill="#fff"/><path fill="#1B0B3A" d="${q.path}"/></svg><p><strong>On a computer?</strong> ${line}</p></div>`;
};

/** The install action, the same at the top and the bottom of the page. */
function installBlock(state: InstallState): string {
  if (state.kind === "store") {
    const b = MEDIA.badge;
    return `<div class="get">
<a class="badge" href="${escapeHtml(state.url)}"><img src="${b.src}" alt="Download on the App Store" width="${b.width}" height="${b.height}"></a>
${qr("Point your iPhone or iPad camera at this code.")}
</div>
<p class="fine">Free, for iPhone and iPad.</p>`;
  }
  if (state.kind === "beta") {
    return `<div class="get">
<a class="btn" href="${escapeHtml(state.url)}">Join the beta on TestFlight</a>
${qr("Point your iPhone or iPad camera at this code to join the beta.")}
</div>
<p class="fine"><strong>This is a beta.</strong> Pounce is coming soon to the App Store. Until then it installs through TestFlight, Apple's app for trying apps early. Free, for iPhone and iPad.</p>`;
  }
  return `<div class="get">
<p class="soon">Coming soon to the App Store</p>
</div>
<p class="fine">Free, for iPhone and iPad.</p>`;
}

const STYLE = css(`
h2{margin:0 0 12px;font-size:clamp(1.9rem,5.2vw,2.7rem);text-shadow:-2px -2px 0 var(--ink),2px -2px 0 var(--ink),-2px 2px 0 var(--ink),2px 2px 0 var(--ink),0 -2px 0 var(--ink),0 2px 0 var(--ink),-2px 0 0 var(--ink),2px 0 0 var(--ink),0 5px 0 var(--ink)}
h3{margin:0 0 6px;font-size:1.3rem}
.band{padding:40px 0 8px}
.sub{max-width:38em;margin:0 0 24px;font-size:1.12rem}
.panel{background:var(--panel);color:var(--text);border:3px solid var(--ink);border-radius:24px;box-shadow:0 7px 0 var(--ink)}
.panel p{margin:0;color:var(--muted)}
.hero{overflow:hidden;padding:14px 0 36px}
.hero-grid{display:grid;gap:30px;align-items:center}
.chip{display:inline-block;margin:0 0 16px;padding:6px 15px;border:3px solid var(--ink);border-radius:999px;background:var(--teal);box-shadow:0 3px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:.98rem;font-weight:900}
h1{margin:0 0 18px;font-size:clamp(2.6rem,10.5vw,4.5rem);line-height:1.02;text-shadow:-3px -3px 0 var(--ink),3px -3px 0 var(--ink),-3px 3px 0 var(--ink),3px 3px 0 var(--ink),0 -3px 0 var(--ink),0 3px 0 var(--ink),-3px 0 0 var(--ink),3px 0 0 var(--ink),0 8px 0 var(--ink)}
h1 span{display:block;color:var(--sun);text-wrap:balance}
.lede{max-width:33em;margin:0 0 22px;font-size:1.18rem}
.get{display:flex;flex-wrap:wrap;align-items:center;gap:16px 26px}
.badge{display:inline-block;margin:14px 14px 14px 0;border-radius:10px;line-height:0}
.badge img{display:block;width:auto;height:56px}
.badge:hover,.btn:hover{filter:brightness(1.08)}
.btn{display:inline-block;padding:13px 22px;border:3px solid var(--ink);border-radius:999px;background:linear-gradient(#FFC21A,#FF8A00);box-shadow:0 5px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.1rem;font-weight:900;text-decoration:none}
.btn:active{transform:translateY(3px);box-shadow:0 2px 0 var(--ink)}
.soon{margin:0;padding:12px 20px;border:3px solid var(--ink);border-radius:18px;background:var(--deep);color:#fff;font-family:var(--round);font-size:1.1rem;font-weight:900}
@media (min-width:420px){.btn,.soon{padding:14px 28px;font-size:1.25rem}}
.qr{display:none;align-items:center;gap:14px;max-width:340px;padding:8px 18px 8px 8px;border:3px solid var(--ink);border-radius:18px;background:#fff;box-shadow:0 5px 0 var(--ink);color:var(--ink);font-size:.95rem;line-height:1.3}
.qr svg{flex:none;display:block;border-radius:8px}
.qr p{margin:0}
.qr strong{display:block;font-family:var(--round);font-weight:900;font-size:1.05rem}
@media (min-width:900px) and (hover:hover) and (pointer:fine){.qr{display:flex}}
.fine{max-width:36em;margin:14px 0 0;color:#F0E9FF;font-size:.95rem}
.hero-art{position:relative;display:flex;justify-content:center;padding:6px 0 18px}
.hero-art::before{content:"";position:absolute;left:50%;top:50%;width:150%;max-width:760px;aspect-ratio:1;transform:translate(-50%,-50%);border-radius:50%;background:repeating-conic-gradient(rgba(255,255,255,.16) 0 9deg,transparent 9deg 18deg);-webkit-mask-image:radial-gradient(closest-side,#000 30%,transparent);mask-image:radial-gradient(closest-side,#000 30%,transparent)}
.phone{position:relative;z-index:1;width:min(66vw,280px);aspect-ratio:${MEDIA.clip.width}/${MEDIA.clip.height};overflow:hidden;border:9px solid var(--ink);border-radius:42px;background:var(--ink);box-shadow:0 12px 0 rgba(27,11,58,.5);transform:rotate(2.5deg)}
.phone video,.phone img{display:block;width:100%;height:100%;object-fit:cover}
.phone .still{display:none}
@media (prefers-reduced-motion:reduce){.phone .clip{display:none}.phone .still{display:block}}
.hero-cat{position:absolute;z-index:2;left:calc(50% - min(48vw,236px));bottom:0;width:min(34vw,160px);height:auto}
.strip{margin:0 auto;max-width:1140px;overflow-x:auto;scroll-snap-type:x proximity;-webkit-overflow-scrolling:touch}
.strip ul{display:flex;gap:16px;width:max-content;margin:0;padding:6px 20px 22px;list-style:none}
.strip li{flex:none;width:220px;scroll-snap-align:center}
.strip img{display:block;width:100%;height:auto;border:3px solid var(--ink);border-radius:22px;box-shadow:0 6px 0 var(--ink)}
.steps{display:grid;gap:20px;margin:0;padding:0;list-style:none;counter-reset:step}
.steps li{padding:20px 20px 24px;counter-increment:step}
.steps li::before{content:counter(step);display:grid;place-items:center;width:46px;height:46px;margin-bottom:12px;border:3px solid var(--ink);border-radius:50%;background:var(--sun);box-shadow:0 3px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.4rem;font-weight:900}
.ways{display:grid;gap:20px}
.way{overflow:hidden}
.way .art{display:flex;align-items:flex-end;justify-content:center;height:150px;padding-top:14px;border-bottom:3px solid var(--ink)}
.pink{background:var(--magenta)}.teal{background:var(--teal)}.orange{background:var(--orange)}.sky{background:var(--sky)}
.way .art picture{flex:none;margin:0 -10px}
.way .art img{display:block;width:auto;max-width:none;height:136px}
.way .trio picture{margin:0 -14px}
.way .trio img{height:116px}
.way .txt{padding:16px 20px 24px}
.kids{display:grid;gap:24px;align-items:start;padding:26px 22px 30px}
.kids h2,.first h2{color:var(--h1);text-shadow:none}
.kids .cat{display:block;width:150px;height:auto;margin:0 0 6px -8px}
.kids p{margin:0 0 14px}
.kids .more{display:flex;flex-wrap:wrap;gap:8px 22px;margin:0;font-weight:700}
.panel a{color:var(--link)}
.checks{display:grid;gap:16px;margin:0;padding:0;list-style:none;color:var(--muted)}
.checks li{position:relative;padding-left:42px}
.checks li::before{content:"";position:absolute;left:0;top:0;width:28px;height:28px;border:3px solid var(--ink);border-radius:50%;background:var(--lime)}
.checks li::after{content:"";position:absolute;left:10px;top:6px;width:8px;height:13px;border:solid var(--ink);border-width:0 3px 3px 0;transform:rotate(45deg)}
.checks strong{display:block;color:var(--text);font-family:var(--round);font-size:1.12rem;font-weight:900}
.first{display:grid;gap:18px;align-items:center;padding:24px 22px 28px}
.first picture{display:block}
.first img{display:block;width:min(100%,280px);height:auto}
.first p{font-size:1.08rem}
.last{position:relative;overflow:hidden;padding:30px 22px 34px;border:3px solid var(--ink);border-radius:28px;background:linear-gradient(135deg,var(--violet),#C2188A);box-shadow:0 8px 0 var(--ink)}
.last h2{position:relative}
.last .sub,.last .get,.last .fine{position:relative}
.last .cat{position:absolute;right:-18px;bottom:-14px;width:150px;height:auto;opacity:.95}
@media (prefers-color-scheme:dark){.last{background:linear-gradient(135deg,#5B1FD1,#8A1466)}}
@media (min-width:640px){.steps,.ways{grid-template-columns:1fr 1fr}.first{grid-template-columns:minmax(0,280px) 1fr;gap:32px;padding:28px 32px 32px}.last{padding:40px 40px 44px}.last .cat{width:210px;right:24px}}
@media (min-width:720px){.hero-grid{grid-template-columns:1.15fr .85fr;gap:24px}h1{font-size:2.9rem}.phone{width:250px}.hero-cat{left:calc(50% - 215px);width:150px}}
@media (min-width:900px){.hero{padding:26px 0 48px}.hero-grid{grid-template-columns:1.3fr .7fr;gap:36px}h1{font-size:clamp(2.9rem,5.1vw,3.9rem)}h1 span{white-space:nowrap}.phone{width:300px}.hero-cat{left:calc(50% - 262px);width:190px}.kids{grid-template-columns:.9fr 1.1fr;gap:40px;padding:36px 40px 40px}.band{padding:56px 0 8px}}
@media (min-width:1000px){.steps,.ways{grid-template-columns:repeat(4,1fr)}}
@media (min-width:1100px){.strip{overflow:visible}.strip ul{display:grid;grid-template-columns:repeat(6,1fr);width:auto;padding-bottom:10px}.strip li{width:auto}}
`);

const json = (value: unknown): string => JSON.stringify(value).replace(/</g, "\\u003c");

function head(state: InstallState, origin: string): string {
  const url = `${origin}/`;
  const image = `${origin}${MEDIA.og.src}`;
  const id = state.kind === "store" ? appStoreId(state.url) : null;
  const app = {
    "@context": "https://schema.org",
    "@type": "MobileApplication",
    name: NAME,
    description: DESCRIPTION,
    url,
    image,
    applicationCategory: "GameApplication",
    operatingSystem: "iOS",
    author: { "@type": "Organization", name: "Conley Chaos LLC", url: "https://conleychaos.com" },
    // The store link, and the price that goes with it, only once the app can be downloaded there.
    ...(state.kind === "store" ? { installUrl: state.url, offers: { "@type": "Offer", price: "0", priceCurrency: "USD" } } : {}),
  };
  const title = `${NAME} | ${SUBTITLE}`;
  return [
    `<meta name="description" content="${DESCRIPTION}">`,
    `<link rel="canonical" href="${escapeHtml(url)}">`,
    `<link rel="icon" type="image/png" sizes="192x192" href="${MEDIA.icon192}">`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png">`,
    ...(id ? [`<meta name="apple-itunes-app" content="app-id=${id}">`] : []),
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Pounce">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${DESCRIPTION}">`,
    `<meta property="og:url" content="${escapeHtml(url)}">`,
    `<meta property="og:image" content="${escapeHtml(image)}">`,
    `<meta property="og:image:width" content="${MEDIA.og.width}">`,
    `<meta property="og:image:height" content="${MEDIA.og.height}">`,
    `<meta property="og:image:alt" content="The Pounce app icon beside two screenshots of the Cat Tower card game.">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${DESCRIPTION}">`,
    `<meta name="twitter:image" content="${escapeHtml(image)}">`,
    `<link rel="preload" as="image" href="${MEDIA.clip.poster}">`,
    `<script type="application/ld+json">${json(app)}</script>`,
    "",
  ].join("\n");
}

const LAST: Record<InstallState["kind"], { title: string; line: string }> = {
  store: { title: "Get Pounce", line: "Start a table tonight. The first turn takes a minute." },
  beta: { title: "Try the beta", line: "Pounce is in beta before it reaches the App Store. Start a table tonight." },
  soon: { title: "Almost here", line: "Pounce is on its way to the App Store, for iPhone and iPad." },
};

function body(state: InstallState, consent: boolean): string {
  const c = MEDIA.clip;
  const install = installBlock(state);
  const last = LAST[state.kind];
  const alerts = consent
    ? `<li><strong>A parent decides on turn alerts.</strong> A child under 13 gets no notifications from our server unless a parent allows them, and the parent confirms with a code texted to their own phone.</li>`
    : `<li><strong>No notifications for under-13s.</strong> A child under 13 gets no push notifications from our server.</li>`;
  return `<main id="main">
<section class="hero" aria-labelledby="top">
<div class="wrap hero-grid">
<div>
<p class="chip">${SUBTITLE}</p>
<h1 id="top">Game night, <span>one turn at a time.</span></h1>
<p class="lede">Pounce is a card game for couples and families. Play Cat Tower on one phone or from anywhere, and take your turn when you have a minute. The game waits for everyone else.</p>
${install}
</div>
<div class="hero-art">
<div class="phone">
<video class="clip" width="${c.width}" height="${c.height}" poster="${c.poster}" autoplay muted loop playsinline controls preload="metadata" disablepictureinpicture controlslist="nodownload nofullscreen noremoteplayback" aria-label="Gameplay clip, ${c.seconds} seconds, no sound: a turn at the Cat Tower card table.">
<source src="${c.src}" type="video/mp4" media="(prefers-reduced-motion: no-preference)">
</video>
<picture><source type="image/webp" srcset="${c.poster}"><img class="still" src="${c.posterJpg}" alt="The Cat Tower card table on your turn, with three players' cats along the top and your cards fanned along the bottom." width="${c.width}" height="${c.height}"></picture>
</div>
${art(MEDIA.art.leap, "hero-cat").replace(' loading="lazy"', "")}
</div>
</div>
</section>

<section class="band" aria-labelledby="look">
<div class="wrap">
<h2 id="look">See the game</h2>
<p class="sub">Cat Tower on iPhone. It plays the same on iPad.</p>
</div>
<div class="strip" role="region" aria-label="Screenshots of Pounce" tabindex="0">
<ul>
${shots()}
</ul>
</div>
</section>

<section class="band" aria-labelledby="how">
<div class="wrap">
<h2 id="how">How a game works</h2>
<p class="sub">A game of Cat Tower runs over a day or a week, a turn at a time.</p>
<ol class="steps">
<li class="panel"><h3>Start a table</h3><p>Tap Create, then invite people with a link or a QR code, or pass one phone around. Nobody needs an account to play.</p></li>
<li class="panel"><h3>Take your turn</h3><p>Draw a card, lay down the sets and runs your level asks for, and discard. Yarn is wild. A Cucumber makes the next cat skip a turn.</p></li>
<li class="panel"><h3>Climb the tower</h3><p>Collect the right cards to clear a level, and your cat climbs to the next shelf. There are ten levels.</p></li>
<li class="panel"><h3>Come back when you can</h3><p>The game waits for everyone. A reminder tells you when it's your turn, and the winner takes the crown.</p></li>
</ol>
</div>
</section>

<section class="band" aria-labelledby="ways">
<div class="wrap">
<h2 id="ways">Play it your way</h2>
<p class="sub">Two to six players at one table, together or apart.</p>
<div class="ways">
<div class="panel way"><div class="art pink">${art(MEDIA.art.tuxedo)}${art(MEDIA.art.white)}</div><div class="txt"><h3>With your partner</h3><p>Keep a game going all week. Pounce keeps your streak, and a widget puts it on your Home Screen.</p></div></div>
<div class="panel way"><div class="art teal trio">${art(MEDIA.art.calico)}${art(MEDIA.art.cheer)}${art(MEDIA.art.celebrate)}</div><div class="txt"><h3>With the whole family</h3><p>Deal in the kids and the grandparents. Short a player? Seat a House Cat bot.</p></div></div>
<div class="panel way"><div class="art orange">${art(MEDIA.art.yarn)}${art(MEDIA.art.leap)}</div><div class="txt"><h3>On one phone or from anywhere</h3><p>Send a link across the country, pass one phone around the couch, or do both in the same game.</p></div></div>
<div class="panel way"><div class="art sky">${art(MEDIA.art.bell)}</div><div class="txt"><h3>At your own pace</h3><p>A reminder tells you when it's your turn. The live table on your Lock Screen shows whose move it is.</p></div></div>
</div>
</div>
</section>

<section class="band" aria-labelledby="kids">
<div class="wrap">
<div class="panel kids">
<div>
${art(MEDIA.art.asleep, "cat")}
<h2 id="kids">Made with kids in mind</h2>
<p>Pounce is made for adults playing with their families, not for children on their own. Here is what that means in the app.</p>
<p class="more"><a href="/privacy">Read the privacy policy</a><a href="/privacy#coppa">Notice for parents</a></p>
</div>
<ul class="checks">
<li><strong>No chat. No public profiles.</strong> Only the people at your table see your name and your cat.</li>
<li><strong>No ads. No tracking.</strong> No analytics and no third-party SDKs. We never sell your data.</li>
<li><strong>No account needed.</strong> Signing in is never required to play.</li>
<li><strong>Simpler for under-13s.</strong> A child under 13 picks a name from Pounce's list of cat names and can't type one. No sign-in, and no invite links sent out.</li>
${alerts}
<li><strong>Report, block, delete.</strong> Report or block a player from their card at your table. Delete your data in the app at any time.</li>
</ul>
</div>
</div>
</section>

<section class="band" aria-labelledby="first">
<div class="wrap">
<div class="panel first">
${art(MEDIA.art.tile)}
<div>
<h2 id="first">Cat Tower comes first</h2>
<p>Cat Tower is the first game in Pounce, with more to come. It's a rummy-style card game where your cats climb a ten-shelf tower.</p>
</div>
</div>
</div>
</section>

<section class="band" aria-labelledby="get">
<div class="wrap">
<div class="last">
${art(MEDIA.art.condo, "cat")}
<h2 id="get">${last.title}</h2>
<p class="sub">${last.line}</p>
${install}
</div>
</div>
</section>
</main>`;
}

/**
 * The home page. `install` picks the install action (see `installState`), `origin` is this
 * request's own (for the canonical link and the social image), and `consent` says whether a
 * parent can allow turn alerts for a child, as the privacy policy does.
 */
export function homePage(install: Install = {}, origin = "https://play.conleychaos.com", consent = true): Response {
  const state = installState(install);
  const html = shell({
    title: `${NAME} | ${SUBTITLE}`,
    head: head(state, origin),
    style: STYLE,
    current: "home",
    credit: true,
    body: body(state, consent),
  });
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": HOME_CSP },
  });
}
