/**
 * The landing page at `/`: what Pounce is (family games), where it plays (the iPhone and iPad
 * app, any web browser, and a TV), and how to start. Static HTML, no scripts; images and the clip
 * come from this Worker's own /static files (scripts/build-site-media.mjs), and every screenshot
 * is a real one.
 *
 * The copy follows the App Store listing (docs/whats-new). The kids and privacy claims go only as
 * far as the privacy policy (privacy.ts) does: change them together. The TV section says only what
 * works today: the browser TV at /play/tv, with a phone (in the browser or the 1.2 app) showing
 * just its own hand. The Apple TV app isn't on the App Store yet, so the page doesn't name it.
 *
 * With the Daily Dish (`DAILY` on) the page also shows the four daily puzzles, in the app since
 * 1.2 and in the browser. With Birdwatch or Toy Tumble in `GAMES` it shows that game too, and
 * Purrtrait while its tables can be dealt (`GAMES` and `TV`). They are in the browser only until an
 * App Store version has them (`GAME_SINCE` in links.ts), so the page says "coming to the iPhone
 * app" (Toy Tumble and Purrtrait: "in 1.4") and the App Store app's own description and structured
 * data leave them out. Purrtrait starts on a TV, so its card shows the browser TV page and sends
 * people there.
 */
import { CACHE, css, escapeHtml, shell } from "./layout";
import { appStoreId, https, PURRTRAIT_SINCE, TUMBLE_SINCE } from "./links";
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
export const TITLE = `${NAME} | Cat Tower and Tuna Tiles`;
/** The title with Birdwatch on. */
export const BIRDWATCH_TITLE = `${NAME} | Cat Tower, Tuna Tiles and Birdwatch`;
/** The title with Birdwatch and Toy Tumble on, as in production. */
export const TUMBLE_TITLE = `${NAME} | Cat Tower, Tuna Tiles, Birdwatch and Toy Tumble`;
export const DESCRIPTION =
  "Family game night, every night. Play Cat Tower and Tuna Tiles together on the couch, on the TV or from far away. Free on iPhone, iPad and in any web browser.";
/** The description with the Daily Dish on, for the page and the app (the Dish is in the app since 1.2). */
export const DAILY_DESCRIPTION =
  "Family game night, every night. Play Cat Tower and Tuna Tiles together, and four new puzzles every day. Free on iPhone, iPad and in any web browser.";
/**
 * The page's description with Birdwatch on, and with the Daily Dish too (as in production). Birdwatch
 * is only in the browser, so it is named apart from what the app has. The app's own description
 * never names it until an App Store version has it.
 */
export const BIRDWATCH_DESCRIPTION =
  "Family game night, every night. Cat Tower, Tuna Tiles and four new puzzles a day on iPhone, iPad and the web, and now Birdwatch in your browser. All free.";
/** The page's description with Birdwatch on and the Daily Dish off. */
export const BIRDWATCH_ONLY_DESCRIPTION =
  "Family game night, every night. Cat Tower and Tuna Tiles on iPhone, iPad and the web, and now Birdwatch, a team card game, in your browser. All free.";
/**
 * The page's description with Birdwatch, Toy Tumble and the Daily Dish on, as in production. Both
 * newer games are only in the browser, so they are named apart from what the app has.
 */
export const TUMBLE_DESCRIPTION =
  "Family game night, every night. Cat Tower, Tuna Tiles and daily puzzles on iPhone, iPad and the web, and now Birdwatch and Toy Tumble in your browser. All free.";

/** The games only the browser has, by name, from the flags that are on. */
export const browserGames = (birdwatch: boolean, tumble: boolean, purrtrait = false): string[] => [
  ...(birdwatch ? ["Birdwatch"] : []),
  ...(tumble ? ["Toy Tumble"] : []),
  ...(purrtrait ? ["Purrtrait"] : []),
];

/** "A", "A and B", "A, B and C". */
export const and = (names: readonly string[]): string => (names.length < 2 ? (names[0] ?? "") : `${names.slice(0, -1).join(", ")} and ${names.at(-1) ?? ""}`);

/**
 * The page's description with Birdwatch, Toy Tumble, Purrtrait and the Daily Dish on, as in
 * production. The three newer games are only in the browser, so they are named apart from what the
 * app has.
 */
export const PURRTRAIT_DESCRIPTION =
  "Family game night, every night. Cat Tower, Tuna Tiles and daily puzzles on iPhone, iPad and the web. Birdwatch, Toy Tumble and Purrtrait in your browser. Free.";

/** What the page says it is, from the flags that are on. */
export function pageDescription(daily: boolean, birdwatch: boolean, tumble = false, purrtrait = false): string {
  if (purrtrait) {
    const app = daily ? "Cat Tower, Tuna Tiles and daily puzzles" : "Cat Tower and Tuna Tiles";
    return `Family game night, every night. ${app} on iPhone, iPad and the web. ${and(browserGames(birdwatch, tumble, true))} in your browser. Free.`;
  }
  if (!tumble) {
    if (birdwatch) return daily ? BIRDWATCH_DESCRIPTION : BIRDWATCH_ONLY_DESCRIPTION;
    return daily ? DAILY_DESCRIPTION : DESCRIPTION;
  }
  if (birdwatch && daily) return TUMBLE_DESCRIPTION;
  // Room to say what it is only beside the two older games alone.
  const named = birdwatch ? "Birdwatch and Toy Tumble" : daily ? "Toy Tumble" : "Toy Tumble, a falling-toys battle,";
  const app = daily ? "Cat Tower, Tuna Tiles and four new puzzles a day" : "Cat Tower and Tuna Tiles";
  return `Family game night, every night. ${app} on iPhone, iPad and the web, and now ${named} in your browser. All free.`;
}

/** The page's title, from the games that are on. */
export function pageTitle(birdwatch: boolean, tumble = false, purrtrait = false): string {
  return `${NAME} | ${and(["Cat Tower", "Tuna Tiles", ...browserGames(birdwatch, tumble, purrtrait)])}`;
}

/** The web player. Its page is `/play/`; `/play` only redirects there. */
const PLAY = "/play/";
/** The web player's TV screen, as people type it. */
const TV = "/play/tv";
/** The web player's Daily Dish. */
const DISH = "/play/daily";

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

type Screen = (typeof MEDIA.screens)[keyof typeof MEDIA.screens];

const srcset = (files: readonly { readonly src: string; readonly w: number }[]): string => files.map((f) => `${f.src} ${f.w}w`).join(", ");

/** A real screenshot: WebP with a JPEG fallback, picked by `sizes`, and what it shows as its alt text. */
const screen = (s: Screen, sizes: string, alt: string, eager = false): string =>
  `<picture><source type="image/webp" srcset="${srcset(s.webp)}" sizes="${sizes}"><img src="${s.jpg[0].src}" srcset="${srcset(s.jpg)}" sizes="${sizes}" alt="${alt}" width="${s.width}" height="${s.height}"${eager ? "" : ' loading="lazy"'} decoding="async"></picture>`;

/** What each screenshot shows, for people who can't see it. */
const ALT = {
  tv: "A TV showing a Cat Tower table with six players, their cats around the edge and the deck in the middle.",
  tvHome: "The TV's start screen: a code to scan with your phone, beside posters for Cat Tower, Tuna Tiles, Birdwatch, Purrtrait, Toy Tumble and Tonight's board.",
  cards: "A phone in the browser at a TV table, showing just its own cards, with a Cards and Table switch at the top.",
  laptop: "Cat Tower in a web browser on a laptop: the deck on the rug, the tower's levels down the side and a hand of cat cards.",
  catTower: "Cat Tower on iPhone: three players' cats along the top, the tower's shelves down the side and a hand of cards.",
  tiles: "Tuna Tiles on iPhone: rows of numbered tiles laid out on the rug, with your own tiles along the bottom.",
  birdwatch: "Birdwatch in a phone's browser: four cats around the window, a card played on the sill, the team scores and a hand of cards.",
  tumble: "Toy Tumble in a phone's browser: your toy box with toys stacked at the bottom and one falling, the next toy on the cat's paw, and five other players' boxes down the side.",
  purrtrait: "Purrtrait on a TV: a cat's face being drawn on the easel, the players' scores down one side, and the drawer's name, the timer and the hint Animal on the other.",
} as const;

/** The QR code for `/get`, for people reading on a computer; shown only on wide screens with a mouse. */
const qr = (line: string): string => {
  const q = MEDIA.qr;
  const quiet = 3;
  const side = q.size + quiet * 2;
  return `<div class="qr"><svg viewBox="${-quiet} ${-quiet} ${side} ${side}" width="112" height="112" role="img" aria-label="QR code for play.conleychaos.com/get" shape-rendering="crispEdges"><rect x="${-quiet}" y="${-quiet}" width="${side}" height="${side}" fill="#fff"/><path fill="#1B0B3A" d="${q.path}"/></svg><p><strong>On a computer?</strong> ${line}</p></div>`;
};

/** The way in for everyone without an iPhone or iPad: the web player. */
const BROWSER = `<a class="btn web" href="${PLAY}">Play in your browser</a>`;

/** The install action, the same at the top and the bottom of the page. */
function installBlock(state: InstallState): string {
  if (state.kind === "store") {
    const b = MEDIA.badge;
    return `<div class="get">
<a class="badge" href="${escapeHtml(state.url)}"><img src="${b.src}" alt="Download on the App Store" width="${b.width}" height="${b.height}"></a>
${BROWSER}
${qr("Play here in your browser, or scan this with your iPhone to get the app.")}
</div>
<p class="fine">Free. Get the app on iPhone and iPad, or play in the browser on anything else.</p>`;
  }
  if (state.kind === "beta") {
    return `<div class="get">
<a class="btn" href="${escapeHtml(state.url)}">Join the beta on TestFlight</a>
${BROWSER}
${qr("Play here in your browser, or scan this with your iPhone to join the beta.")}
</div>
<p class="fine"><strong>Free beta</strong> through Apple's TestFlight app, for iPhone and iPad. The App Store release is coming.</p>`;
  }
  return `<div class="get">
<p class="soon">Coming soon to the App Store</p>
${BROWSER}
</div>
<p class="fine">Free. Play in your browser today.</p>`;
}

const STYLE = css(`
h2{margin:0 0 12px;font-size:clamp(1.9rem,5.2vw,2.7rem);text-shadow:-2px -2px 0 var(--ink),2px -2px 0 var(--ink),-2px 2px 0 var(--ink),2px 2px 0 var(--ink),0 -2px 0 var(--ink),0 2px 0 var(--ink),-2px 0 0 var(--ink),2px 0 0 var(--ink),0 5px 0 var(--ink)}
h3{margin:0 0 6px;font-size:1.3rem}
.band{padding:40px 0 8px}
.sub{max-width:38em;margin:0 0 24px;font-size:1.12rem}
.panel{background:var(--panel);color:var(--text);border:3px solid var(--ink);border-radius:24px;box-shadow:0 7px 0 var(--ink)}
.panel p{margin:0;color:var(--muted)}
.panel a{color:var(--link)}
.hero{overflow:hidden;padding:14px 0 36px}
.hero-grid{display:grid;gap:34px;align-items:center}
.chip{display:inline-block;margin:0 0 16px;padding:6px 15px;border:3px solid var(--ink);border-radius:999px;background:var(--teal);box-shadow:0 3px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:.98rem;font-weight:900}
h1{margin:0 0 18px;font-size:clamp(2.4rem,10.5vw,4.5rem);line-height:1.02;text-shadow:-3px -3px 0 var(--ink),3px -3px 0 var(--ink),-3px 3px 0 var(--ink),3px 3px 0 var(--ink),0 -3px 0 var(--ink),0 3px 0 var(--ink),-3px 0 0 var(--ink),3px 0 0 var(--ink),0 8px 0 var(--ink)}
h1 span{display:block;color:var(--sun);text-wrap:balance}
.lede{max-width:33em;margin:0 0 22px;font-size:1.18rem}
.get{display:flex;flex-wrap:wrap;align-items:center;gap:14px 18px}
.badge{display:inline-block;border-radius:10px;line-height:0}
.badge img{display:block;width:auto;height:56px}
.badge:hover,.btn:hover{filter:brightness(1.08)}
.btn{display:inline-block;padding:12px 22px;border:3px solid var(--ink);border-radius:999px;background:linear-gradient(#FFC21A,#FF8A00);box-shadow:0 5px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.1rem;font-weight:900;line-height:1.2;text-decoration:none}
.btn.web{background:linear-gradient(#6AF5EA,#00B3A6)}
.btn:active{transform:translateY(3px);box-shadow:0 2px 0 var(--ink)}
.soon{margin:0;padding:12px 20px;border:3px solid var(--ink);border-radius:18px;background:var(--deep);color:#fff;font-family:var(--round);font-size:1.1rem;font-weight:900}
@media (min-width:420px){.btn,.soon{padding:13px 26px;font-size:1.2rem}}
.qr{display:none;align-items:center;gap:14px;max-width:370px;padding:8px 18px 8px 8px;border:3px solid var(--ink);border-radius:18px;background:#fff;box-shadow:0 5px 0 var(--ink);color:var(--ink);font-size:.95rem;line-height:1.3}
.qr svg{flex:none;display:block;border-radius:8px}
.qr p{margin:0}
.qr strong{display:block;font-family:var(--round);font-weight:900;font-size:1.05rem}
@media (min-width:900px) and (hover:hover) and (pointer:fine){.qr{display:flex}}
.fine{max-width:36em;margin:16px 0 0;color:#F0E9FF;font-size:.95rem}
.scene{position:relative;width:100%;max-width:560px;margin:0 auto;aspect-ratio:100/84}
.scene::before{content:"";position:absolute;left:50%;top:45%;width:130%;aspect-ratio:1;transform:translate(-50%,-50%);border-radius:50%;background:repeating-conic-gradient(rgba(255,255,255,.14) 0 9deg,transparent 9deg 18deg);-webkit-mask-image:radial-gradient(closest-side,#000 30%,transparent);mask-image:radial-gradient(closest-side,#000 30%,transparent);pointer-events:none}
.tv{position:absolute;left:0;top:0;width:90%;border:clamp(5px,1.6vw,9px) solid var(--ink);border-radius:clamp(10px,2.4vw,16px);background:var(--ink);box-shadow:0 8px 0 rgba(27,11,58,.45)}
.tv img{display:block;width:100%;height:auto;border-radius:4px}
.tv::after{content:"";position:absolute;left:50%;top:100%;width:24%;height:clamp(8px,2.4vw,16px);transform:translateX(-50%);border-radius:0 0 10px 10px;background:var(--ink)}
.handset{position:absolute;z-index:1;right:0;bottom:0;width:31%;overflow:hidden;border:clamp(4px,1.3vw,8px) solid var(--ink);border-radius:clamp(16px,4.6vw,34px);background:var(--ink);box-shadow:0 10px 0 rgba(27,11,58,.45);transform:rotate(3deg)}
.handset img,.handset video{display:block;width:100%;height:auto}
.hero .handset{aspect-ratio:${MEDIA.clip.width}/${MEDIA.clip.height}}
.hero .handset video,.hero .handset img{height:100%;object-fit:cover}
.handset .still{display:none}
@media (prefers-reduced-motion:reduce){.handset .clip{display:none}.handset .still{display:block}}
.handset video:focus-visible{outline-offset:-5px}
@supports selector(:has(a)){.handset:has(video:focus-visible){outline:3px solid var(--focus);outline-offset:4px}.handset video:focus-visible{outline:none}}
.scene .pal{position:absolute;z-index:1;left:4%;bottom:0;width:27%;height:auto}
.games{display:grid;gap:20px}
.game{display:grid;align-content:start;overflow:hidden}
.game .art{display:flex;justify-content:center;align-items:center;padding:22px 20px;border-bottom:3px solid var(--ink)}
.game .art img{display:block;width:160px;height:auto;border:4px solid var(--ink);border-radius:24px;box-shadow:0 5px 0 var(--ink)}
.game .txt{padding:18px 20px 24px}
.game .txt p+p{margin-top:8px}
.panel p.where{color:var(--text);font-weight:700;text-wrap:pretty}
.panel p.where a{font-family:var(--round);font-weight:900}
.lime{background:var(--lime)}
.puzzles{display:grid;gap:16px;margin:0 0 24px;padding:0;list-style:none}
.puzzle{display:flex;flex-wrap:wrap;gap:14px;align-items:center;padding:16px 18px}
.puzzle>div:last-child{flex:1 1 9rem;min-width:0;overflow-wrap:break-word}
.puzzle .art{flex:none;display:flex;justify-content:center;align-items:flex-end;width:76px;height:76px;border:3px solid var(--ink);border-radius:18px;overflow:hidden}
.puzzle .art img{display:block;width:auto;height:68px}
.puzzle h3{margin:0 0 2px}
.dish-note{margin:16px 0 0;color:#F0E9FF;font-size:.95rem}
@media (min-width:720px){.puzzles{grid-template-columns:1fr 1fr}}
.panel p.meta{color:var(--text);font-family:var(--round);font-weight:900}
.pink{background:var(--magenta)}.teal{background:var(--teal)}.orange{background:var(--orange)}.sky{background:var(--sky)}.violet{background:var(--violet)}
.split{display:grid;gap:30px;align-items:center}
.clip{overflow:hidden;padding-bottom:16px}
.steps{display:grid;gap:14px;margin:0;padding:0;list-style:none;counter-reset:step}
.steps li{position:relative;padding:16px 18px 18px 72px;counter-increment:step}
.steps li::before{content:counter(step);position:absolute;left:16px;top:16px;display:grid;place-items:center;width:42px;height:42px;border:3px solid var(--ink);border-radius:50%;background:var(--sun);box-shadow:0 3px 0 var(--ink);color:var(--ink);font-family:var(--round);font-size:1.3rem;font-weight:900}
.steps h3{font-size:1.15rem}
.url{font-weight:800;overflow-wrap:anywhere}
.tvscene{aspect-ratio:100/62}
.tvscene .tv{width:80%}
.tvscene .handset{width:22%}
.laptop{width:100%;max-width:600px;margin:0 auto}
.laptop .lid{border:clamp(6px,1.8vw,12px) solid var(--ink);border-bottom-width:clamp(10px,2.6vw,18px);border-radius:16px 16px 0 0;background:var(--ink);box-shadow:0 8px 0 rgba(27,11,58,.45)}
.laptop img{display:block;width:100%;height:auto;border-radius:4px}
.laptop .base{height:clamp(10px,2.4vw,16px);margin:0 -3%;border:3px solid var(--ink);border-top:0;border-radius:0 0 18px 18px;background:#3A2470}
.devices{display:grid;gap:14px;margin:0 0 24px;padding:0;list-style:none}
.devices li{padding:16px 18px 18px}
.devices strong{display:block;margin:0 0 4px;font-family:var(--round);font-size:1.15rem;font-weight:900}
.ways{display:grid;gap:20px}
.way{overflow:hidden}
.way .art{display:flex;align-items:flex-end;justify-content:center;height:150px;padding-top:14px;border-bottom:3px solid var(--ink)}
.way .art picture{flex:none;margin:0 -10px}
.way .art img{display:block;width:auto;max-width:none;height:136px}
.way .trio picture{margin:0 -14px}
.way .trio img{height:116px}
.way .txt{padding:16px 20px 24px}
.pace{display:grid;gap:18px;align-items:center;padding:24px 22px 28px}
.pace h2,.kids h2{color:var(--h1);text-shadow:none}
.pace picture{display:block}
.pace img{display:block;width:min(100%,260px);height:auto}
.pace p{font-size:1.06rem}
.pace p+p{margin-top:10px}
.kids{display:grid;grid-template-columns:minmax(0,1fr);gap:24px;align-items:start;padding:26px 22px 30px}
.kids .cat{display:block;width:150px;height:auto;margin:0 0 6px -8px}
.kids p{margin:0 0 14px}
.kids .more{display:flex;flex-wrap:wrap;gap:8px 22px;margin:0;font-weight:700}
.checks{display:grid;grid-template-columns:minmax(0,1fr);gap:16px;margin:0;padding:0;list-style:none;color:var(--muted)}
.checks li{position:relative;padding-left:42px}
.checks li::before{content:"";position:absolute;left:0;top:0;width:28px;height:28px;border:3px solid var(--ink);border-radius:50%;background:var(--lime)}
.checks li::after{content:"";position:absolute;left:10px;top:6px;width:8px;height:13px;border:solid var(--ink);border-width:0 3px 3px 0;transform:rotate(45deg)}
.checks strong{display:block;color:var(--text);font-family:var(--round);font-size:1.12rem;font-weight:900}
.last{position:relative;overflow:hidden;padding:30px 22px 150px;border:3px solid var(--ink);border-radius:28px;background:linear-gradient(135deg,var(--violet),#C2188A);box-shadow:0 8px 0 var(--ink)}
.last h2,.last .sub,.last .get,.last .fine{position:relative;z-index:1}
.last .cat{position:absolute;right:-12px;bottom:-14px;width:150px;height:auto;opacity:.95}
@media (prefers-color-scheme:dark){.last{background:linear-gradient(135deg,#5B1FD1,#8A1466)}}
@media (min-width:480px) and (max-width:639px),(min-width:900px){.game{grid-template-columns:auto 1fr;align-content:stretch}.game .art{border-bottom:0;border-right:3px solid var(--ink)}.game .txt{align-self:center}}
@media (min-width:640px){.games,.ways,.devices{grid-template-columns:1fr 1fr}.game.wide{grid-column:1/-1;grid-template-columns:auto 1fr}.game.wide .art{border-bottom:0;border-right:3px solid var(--ink)}.game.wide .txt{align-self:center}.game.wide .txt p{max-width:40em}.pace{grid-template-columns:minmax(0,240px) 1fr;gap:32px;padding:28px 32px 32px}.last{padding:40px 250px 44px 40px}.last .cat{width:210px;right:24px}}
.game.tvgame .art img{width:min(100%,360px);border-width:5px;border-radius:14px}
@media (min-width:640px){.game.tvgame.wide .art img{width:clamp(220px,30vw,320px)}}
@media (min-width:480px) and (max-width:639px){.game.tvgame{grid-template-columns:1fr}.game.tvgame .art{border-right:0;border-bottom:3px solid var(--ink)}}
@media (min-width:900px){.game.tvgame:not(.wide){grid-template-columns:1fr;align-content:start}.game.tvgame:not(.wide) .art{border-right:0;border-bottom:3px solid var(--ink)}}
@media (min-width:720px){.hero-grid{grid-template-columns:1fr 1fr;gap:28px}h1{font-size:2.9rem}}
@media (min-width:900px){.hero{padding:26px 0 48px}.hero-grid{grid-template-columns:1.1fr .9fr;gap:40px}h1{font-size:clamp(2.9rem,5.1vw,3.9rem)}h1 span{white-space:nowrap}.split{grid-template-columns:1fr 1fr;gap:44px}.split.flip>:first-child{order:2}.devices{grid-template-columns:1fr}.kids{grid-template-columns:.9fr 1.1fr;gap:40px;padding:36px 40px 40px}.band{padding:56px 0 8px}}
@media (min-width:1000px){.ways{grid-template-columns:repeat(4,1fr)}}
`);

const json = (value: unknown): string => JSON.stringify(value).replace(/</g, "\\u003c");

function head(state: InstallState, origin: string, daily: boolean, birdwatch: boolean, tumble: boolean, purrtrait: boolean): string {
  const url = `${origin}/`;
  const image = `${origin}${MEDIA.og.src}`;
  const id = state.kind === "store" ? appStoreId(state.url) : null;
  const author = { "@type": "Organization", name: "Conley Chaos LLC", url: "https://conleychaos.com" };
  const free = { "@type": "Offer", price: "0", priceCurrency: "USD" };
  const description = pageDescription(daily, birdwatch, tumble, purrtrait);
  const title = pageTitle(birdwatch, tumble, purrtrait);
  // The browser's games: all of them. The App Store app shares tables for the games it has.
  const newer = browserGames(birdwatch, tumble, purrtrait);
  const webGames = and(["Cat Tower", "Tuna Tiles", ...newer]);
  const shared = newer.length ? "Cat Tower and Tuna Tiles tables are shared with the iPhone app" : "at the same tables as the iPhone app";
  const data = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "MobileApplication",
        "@id": `${url}#app`,
        name: NAME,
        // Only what the App Store's version has: the Dish since 1.2, never Birdwatch, Toy Tumble or Purrtrait before their release.
        description: daily ? DAILY_DESCRIPTION : DESCRIPTION,
        url,
        image,
        applicationCategory: "GameApplication",
        operatingSystem: "iOS, iPadOS",
        author,
        // The store link, and the price that goes with it, only once the app can be downloaded there.
        ...(state.kind === "store" ? { installUrl: state.url, offers: free } : {}),
      },
      {
        "@type": "WebApplication",
        "@id": `${url}#web`,
        name: "Pounce",
        description: `${webGames} in a web browser, ${shared}, with a TV screen at /play/tv${purrtrait ? " where Purrtrait starts" : ""}${daily ? ", and four new puzzles every day at /play/daily" : ""}.`,
        url: `${origin}${PLAY}`,
        image,
        applicationCategory: "GameApplication",
        operatingSystem: "Any",
        browserRequirements: "Requires JavaScript.",
        author,
        offers: free,
      },
    ],
  };
  return [
    `<meta name="description" content="${description}">`,
    `<link rel="canonical" href="${escapeHtml(url)}">`,
    `<link rel="icon" type="image/png" sizes="192x192" href="${MEDIA.icon192}">`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png">`,
    ...(id ? [`<meta name="apple-itunes-app" content="app-id=${id}">`] : []),
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Pounce">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${description}">`,
    `<meta property="og:url" content="${escapeHtml(url)}">`,
    `<meta property="og:image" content="${escapeHtml(image)}">`,
    `<meta property="og:image:width" content="${MEDIA.og.width}">`,
    `<meta property="og:image:height" content="${MEDIA.og.height}">`,
    `<meta property="og:image:alt" content="The Pounce app icon beside screenshots of Cat Tower and Tuna Tiles on iPhone.">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${description}">`,
    `<meta name="twitter:image" content="${escapeHtml(image)}">`,
    `<link rel="preload" as="image" href="${MEDIA.clip.poster}">`,
    `<script type="application/ld+json">${json(data)}</script>`,
    "",
  ].join("\n");
}

const LAST: Record<InstallState["kind"], { title: string; line: string }> = {
  store: { title: "Get Pounce", line: "Start a table tonight." },
  beta: { title: "Join the beta", line: "Pounce is in beta ahead of its App Store release. Start a table tonight." },
  soon: { title: "Almost here", line: "Pounce is on its way to the App Store. Start a table in your browser tonight." },
};

/**
 * The Daily Dish: the four puzzles, the family board, and where they play today. Each puzzle's
 * line says what to do, the way its own screen teaches it.
 */
function dishSection(): string {
  const a = MEDIA.art;
  const puzzle = (cat: Art, tint: string, name: string, kind: string, line: string) =>
    `<li class="panel puzzle"><div class="art ${tint}">${art(cat)}</div><div><h3>${name}</h3><p class="meta">${kind}</p><p>${line}</p></div></li>`;
  return `<section class="band" aria-labelledby="dish">
<div class="wrap">
<h2 id="dish">The Daily Dish</h2>
<p class="sub">Four new puzzles every day, the same for the whole family. Easy on Monday, harder by Saturday.</p>
<ul class="puzzles">
${puzzle(a.calico, "teal", "Sniff", "Words", "Find the five-letter word in six tries.")}
${puzzle(a.tuxedo, "pink", "Nine Lives", "Numbers", "Fill the grid. Every row, column and box gets 1 to 9 once.")}
${puzzle(a.asleep, "violet", "Cat Nap", "Logic", "One cat in each row, column and patch. No two cats touch.")}
${puzzle(a.leap, "orange", "Box Fort", "Blocks", "Drag pieces onto the rug. Fill a line to clear it.")}
</ul>
<p class="sub">A family board shows how everyone did today, and every puzzle counts toward your streaks.</p>
<a class="btn web" href="${DISH}">Play today's puzzles</a>
<p class="dish-note">In the iPhone and iPad app, and in your browser.</p>
</div>
</section>`;
}

/** Birdwatch's card, and where it plays today. `wide`: across the whole row, as the last of an odd number. */
function birdwatchCard(wide: boolean): string {
  return `<article class="panel game${wide ? " wide" : ""}"><div class="art lime">${screen(MEDIA.screens.birdwatch, "160px", ALT.birdwatch)}</div><div class="txt"><h3>Birdwatch</h3><p class="meta">Cards, in teams. 4 to 6 players.</p><p>Bid for the hand, take the feeder's extra cards, name trump and win tricks. The Bird is the top trump. With five players, call a card: whoever holds it is your secret partner. Play by Official, Tucker or Friesen rules.</p><p class="where"><a href="${PLAY}">Play it in your browser</a>. Coming to the iPhone app.</p></div></article>`;
}

/** Toy Tumble's card: the real-time game, and where it plays today. */
function tumbleCard(wide: boolean): string {
  return `<article class="panel game${wide ? " wide" : ""}"><div class="art orange">${screen(MEDIA.screens.tumble, "160px", ALT.tumble)}</div><div class="txt"><h3>Toy Tumble</h3><p class="meta">Falling toys, in real time. 2 to 6 players.</p><p>Everyone plays at once on their own phone, and the TV shows every box. Clear rows to send hairballs to everyone else, and pocket tricks to hit a player or save yourself. Win three rounds to take the game.</p><p class="where"><a href="${PLAY}">Play it in your browser</a>. Coming to the iPhone app in ${TUMBLE_SINCE}.</p></div></article>`;
}

/**
 * Purrtrait's card: the party game that starts on a TV, so its picture is the TV mid-drawing and its
 * link is the browser TV page.
 */
function purrtraitCard(wide: boolean): string {
  return `<article class="panel game tvgame${wide ? " wide" : ""}"><div class="art teal">${screen(MEDIA.screens.purrtrait, "(min-width: 640px) 320px, 80vw", ALT.purrtrait)}</div><div class="txt"><h3>Purrtrait</h3><p class="meta">Draw and guess, in one room. 2 to 10 players.</p><p>One player draws a word on their phone, and the TV shows it as it's drawn. Everyone else calls out guesses. Get it first and you both score. Needs a TV or a big screen in the room.</p><p class="where"><a href="${TV}">Start it on the TV page</a> in your browser. Coming to the iPhone and Apple TV app in ${PURRTRAIT_SINCE}.</p></div></article>`;
}

const COUNT = ["Two", "Three", "Four", "Five"] as const;

function body(state: InstallState, consent: boolean, daily: boolean, birdwatch: boolean, tumble: boolean, purrtrait: boolean): string {
  const c = MEDIA.clip;
  const cards = [...(birdwatch ? [birdwatchCard] : []), ...(tumble ? [tumbleCard] : []), ...(purrtrait ? [purrtraitCard] : [])];
  const count = 2 + cards.length;
  const games = COUNT[count - 2] ?? "Two";
  // An odd last card spans the row.
  const newer = cards.map((card, i) => card(count % 2 === 1 && i === cards.length - 1));
  const s = MEDIA.screens;
  const install = installBlock(state);
  const last = LAST[state.kind];
  const alerts = consent
    ? `<li><strong>A parent decides on notifications.</strong> A child under 13 gets none from our server unless a parent allows them, and the parent confirms with a code texted to their own phone.</li>`
    : `<li><strong>No push notifications for under-13s.</strong> A child under 13 gets none from our server. The only reminders are ones the phone schedules for itself, and they start off.</li>`;
  return `<main id="main">
<section class="hero" aria-labelledby="top">
<div class="wrap hero-grid">
<div>
<p class="chip">Free family games</p>
<h1 id="top">Family game night, <span>every night.</span></h1>
<p class="lede">${games} games for the whole family${daily ? ", and four new puzzles every day" : ""}. Gather round the TV, pass one phone, or play from far away.</p>
${install}
</div>
<div class="scene">
<div class="tv">${screen(s.tv, "(min-width: 900px) 460px, (min-width: 720px) 42vw, 86vw", ALT.tv, true)}</div>
${art(MEDIA.art.leap, "pal").replace(' loading="lazy"', "")}
<div class="handset">
<video class="clip" width="${c.width}" height="${c.height}" poster="${c.poster}" autoplay muted loop playsinline controls preload="metadata" disablepictureinpicture controlslist="nodownload nofullscreen noremoteplayback" aria-label="Gameplay clip, ${c.seconds} seconds, no sound: a turn at the Cat Tower card table on iPhone.">
<source src="${c.src}" type="video/mp4" media="(prefers-reduced-motion: no-preference)">
</video>
<picture><source type="image/webp" srcset="${c.poster}"><img class="still" src="${c.posterJpg}" alt="The Cat Tower card table on iPhone on your turn, with three players' cats along the top and your cards fanned along the bottom." width="${c.width}" height="${c.height}"></picture>
</div>
</div>
</div>
</section>

<section class="band" aria-labelledby="games">
<div class="wrap">
<h2 id="games">${games} games</h2>
<p class="sub">${count > 2 ? "Each one teaches itself with How to play." : "Each one has a How to play video in the app."}</p>
<div class="games">
<article class="panel game"><div class="art pink">${screen(s.catTower, "160px", ALT.catTower)}</div><div class="txt"><h3>Cat Tower</h3><p class="meta">Cards. 2 to 6 players.</p><p>Rummy up a ten-shelf tower. Collect sets and runs to clear each level, and your cat climbs a shelf. Yarn is wild. A Cucumber makes the next cat skip a turn.</p></div></article>
<article class="panel game"><div class="art sky">${screen(s.tiles, "160px", ALT.tiles)}</div><div class="txt"><h3>Tuna Tiles</h3><p class="meta">Tiles. 2 to 4 players.</p><p>Tile rummy. Lay matches and rows on the rug, and move any tile already there. Yarn is wild. Empty your stash first to win.</p></div></article>${newer.map((card) => `\n${card}`).join("")}
</div>
</div>
</section>
${daily ? `\n${dishSection()}\n` : ""}
<section class="band clip" aria-labelledby="tv">
<div class="wrap split">
<div>
<h2 id="tv">Put the table on the TV</h2>
<p class="sub">Everyone looks up at one big table.</p>
<ol class="steps">
<li class="panel"><h3>Open it on the big screen</h3><p>Go to <a class="url" href="${TV}">play.conleychaos.com<wbr>/play/tv</a> on a laptop plugged into the TV, a smart TV's browser, or a tab you cast.</p></li>
<li class="panel"><h3>Scan the code</h3><p>Scan the code on the TV with your phone, or type it in. Everyone else scans to join.</p></li>
<li class="panel"><h3>Hold just your hand</h3><p>Your phone shows just your own cards, in the app or the browser. Tap Table for the whole board.</p></li>
</ol>
</div>
<div class="scene tvscene">
<div class="tv">${screen(s.tvHome, "(min-width: 900px) 500px, 86vw", ALT.tvHome)}</div>
<div class="handset">${screen(s.cards, "(min-width: 900px) 130px, 22vw", ALT.cards)}</div>
</div>
</div>
</section>

<section class="band" aria-labelledby="anywhere">
<div class="wrap split flip">
<div>
<h2 id="anywhere">One table, any device</h2>
<p class="sub">iPhone, Android and computer players sit at the same table.</p>
<ul class="devices">
<li class="panel"><strong>iPhone and iPad</strong><p>Get the free app from the App Store.</p></li>
<li class="panel"><strong>Everything else</strong><p>Play at <a class="url" href="${PLAY}">play.conleychaos.com<wbr>/play</a> on Android, a laptop or a tablet. Install it like an app if you like.</p></li>
</ul>
${BROWSER}
</div>
<div class="laptop"><div class="lid">${screen(s.laptop, "(min-width: 900px) 520px, 90vw", ALT.laptop)}</div><div class="base"></div></div>
</div>
</section>

<section class="band" aria-labelledby="ways">
<div class="wrap">
<h2 id="ways">Add players your way</h2>
<p class="sub">Fill every seat. Mix all four in one game.</p>
<div class="ways">
<div class="panel way"><div class="art teal trio">${art(MEDIA.art.calico)}${art(MEDIA.art.cheer)}${art(MEDIA.art.celebrate)}</div><div class="txt"><h3>Same room</h3><p>They scan a QR code on your screen.</p></div></div>
<div class="panel way"><div class="art orange">${art(MEDIA.art.yarn)}${art(MEDIA.art.leap)}</div><div class="txt"><h3>Far away</h3><p>Send a link. It still works after they install Pounce.</p></div></div>
<div class="panel way"><div class="art pink">${art(MEDIA.art.tuxedo)}${art(MEDIA.art.white)}</div><div class="txt"><h3>This phone</h3><p>Pass the phone around the couch.</p></div></div>
<div class="panel way"><div class="art violet">${art(MEDIA.art.grey)}</div><div class="txt"><h3>House Cat</h3><p>A bot holds a seat, so you can start right away.</p></div></div>
</div>
</div>
</section>

<section class="band" aria-labelledby="pace">
<div class="wrap">
<div class="panel pace">
${art(MEDIA.art.bell)}
<div>
<h2 id="pace">Play now or over days</h2>
<p>Play live together, or take a turn when you have a minute. The game waits for everyone.</p>
<p>On iPhone, a reminder tells you when it's your turn. Your Lock Screen shows the live table, and a widget keeps your streak on your Home Screen.</p>
</div>
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
<li><strong>No chat. No public profiles.</strong> The people at your tables see your name and your cat, and so does anyone who opens an invite link you send.</li>${daily ? `\n<li><strong>Daily results stay in the family.</strong> Only the people you have a streak with see how you did, and a TV you linked to your board.</li>` : ""}
<li><strong>No ads. No tracking.</strong> No third-party analytics or SDKs. We never sell your data.</li>
<li><strong>No account needed.</strong> Signing in is never required to play.</li>
<li><strong>Simpler for under-13s.</strong> A child under 13 picks a name from Pounce's list of cat names and can't type one. No sign-in, and no invite links sent out.</li>
${alerts}
<li><strong>Report, block, delete.</strong> Report or block a player from their card at your table. Delete your data in the app at any time.</li>
</ul>
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
 * request's own (for the canonical link and the social image), `consent` says whether a
 * parent can allow turn alerts for a child, as the privacy policy does, `daily` whether the
 * Daily Dish is on (`DAILY`), as the privacy policy says it, and `birdwatch`, `tumble` and
 * `purrtrait` whether Birdwatch, Toy Tumble and Purrtrait tables can be dealt (`GAMES`, and `TV`
 * for Purrtrait).
 */
export function homePage(
  install: Install = {},
  origin = "https://play.conleychaos.com",
  consent = true,
  daily = false,
  birdwatch = false,
  tumble = false,
  purrtrait = false,
): Response {
  const state = installState(install);
  const html = shell({
    title: pageTitle(birdwatch, tumble, purrtrait),
    head: head(state, origin, daily, birdwatch, tumble, purrtrait),
    style: STYLE,
    current: "home",
    credit: true,
    body: body(state, consent, daily, birdwatch, tumble, purrtrait),
  });
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": HOME_CSP },
  });
}
