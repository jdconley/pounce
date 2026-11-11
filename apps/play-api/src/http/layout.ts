/**
 * The public site's shared look: the app's "Loud Toy" palette (apps/play-ios Palette.swift),
 * rounded black type, ink outlines, one header and one footer. Every page is static HTML with
 * its styles inline: no scripts, no web fonts, nothing from another host.
 */
import { MEDIA } from "./site-media";

export const CACHE = "public, max-age=300";
/** Pages that load nothing at all: the logo and favicon are inlined as data: images. */
export const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

const ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const escapeHtml = (text: string): string => text.replace(/[&<>"']/g, (ch) => ESCAPES[ch] as string);

/** One declaration or rule per line in the source; served without the line breaks. */
export const css = (text: string): string => text.replace(/\s*\n\s*/g, "");

/**
 * Light mode is the app's violet by day, dark mode its night. Text on the page background is
 * white in both; panels are white with ink text by day and deep violet with white text at night.
 * Every text and background pair below is at least 4.5:1 (layout.test.ts checks them).
 */
export const TOKENS = {
  light: {
    bg: "#6A22E0",
    deep: "#4A14B0",
    panel: "#FFFFFF",
    text: "#1B0B3A",
    muted: "#4B3C73",
    link: "#5B1FD1",
    inset: "#F1E8FF",
    h1: "#5B1FD1",
    h2: "#B4005C",
    note: "#00707F",
  },
  dark: {
    bg: "#2A0F5C",
    deep: "#1B0B3A",
    panel: "#3A1A75",
    text: "#FFFFFF",
    muted: "#DDD1FF",
    link: "#8AD8FF",
    inset: "#4A2590",
    h1: "#FF8A00",
    h2: "#00D1C1",
    note: "#9BE22E",
  },
} as const;

type Theme = { readonly [K in keyof (typeof TOKENS)["light"]]: string };

const vars = (t: Theme): string =>
  `--bg:${t.bg};--deep:${t.deep};--panel:${t.panel};--text:${t.text};--muted:${t.muted};--link:${t.link};--inset:${t.inset};--h1:${t.h1};--h2:${t.h2};--note:${t.note}`;

const OUTLINE = "-2px -2px 0 var(--ink),2px -2px 0 var(--ink),-2px 2px 0 var(--ink),2px 2px 0 var(--ink),0 -2px 0 var(--ink),0 2px 0 var(--ink),-2px 0 0 var(--ink),2px 0 0 var(--ink)";

export const BASE = css(`
:root{--focus:#FFD21F;--ink:#1B0B3A;--violet:#7B2FFF;--magenta:#FF2E9A;--teal:#00D1C1;--orange:#FF8A00;--sky:#2EB8FF;--lime:#9BE22E;--sun:#FFD21F;--round:ui-rounded,"SF Pro Rounded","Arial Rounded MT Bold",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;${vars(TOKENS.light)}}
@media (prefers-color-scheme:dark){:root{${vars(TOKENS.dark)}}}
:root.night{${vars(TOKENS.dark)}}
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%;scroll-behavior:smooth}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
body{margin:0;min-height:100vh;display:flex;flex-direction:column;background:var(--bg);color:#fff;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:1.0625rem;line-height:1.55}
main{flex:1}
img,svg,video{max-width:100%}
a{color:inherit}
a:focus-visible,[tabindex]:focus-visible,video:focus-visible{outline:3px solid var(--focus);outline-offset:3px}
.doc,.panel,.card{--focus:var(--link)}
h1,h2,h3{font-family:var(--round);font-weight:900;line-height:1.1;letter-spacing:-.01em;text-wrap:balance}
.wrap{max-width:1140px;margin:0 auto;padding:0 20px}
.skip{position:absolute;left:12px;top:-60px;z-index:5;padding:10px 16px;border-radius:12px;background:var(--sun);color:var(--ink);font-weight:800}
.skip:focus{top:12px}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;width:100%;max-width:1140px;margin:0 auto;padding:14px 20px}
.brand{display:inline-flex;align-items:center;gap:10px;color:#fff;text-decoration:none;font-family:var(--round);font-weight:900;font-size:clamp(1.3rem,6.4vw,1.6rem);letter-spacing:-.01em;text-shadow:${OUTLINE},0 4px 0 var(--ink)}
.brand img{width:44px;height:44px;border-radius:12px;border:3px solid var(--ink);box-shadow:0 3px 0 var(--ink)}
.top nav{display:flex;gap:4px}
.top nav a{padding:8px 11px;border-radius:999px;color:#fff;font-family:var(--round);font-weight:800;text-decoration:none}
.top nav a:hover,.top nav a[aria-current]{background:var(--deep)}
.foot{margin-top:56px;padding:32px 0 40px;background:var(--deep);border-top:3px solid var(--ink);color:#fff;font-size:.95rem}
.foot .wrap{display:grid;gap:18px}
.foot strong{font-family:var(--round);font-weight:900;font-size:1.15rem}
.foot ul{display:flex;flex-wrap:wrap;gap:6px 22px;margin:0;padding:0;list-style:none;font-weight:700}
.foot p{margin:0}
.foot small{display:block;max-width:60em;color:#E4DAFF;font-size:.8rem;line-height:1.5}
`);

const DOC = css(`
.doc{width:calc(100% - 24px);max-width:780px;margin:10px auto 0;padding:26px 22px 34px;background:var(--panel);color:var(--text);border:3px solid var(--ink);border-radius:26px;box-shadow:0 8px 0 var(--ink)}
.doc h1{font-size:2.1rem;margin:0 0 6px;color:var(--h1)}
.doc h2{font-size:1.3rem;margin:32px 0 8px;color:var(--h2)}
.doc p,.doc li{font-size:1rem}
.doc ul{padding-left:22px}
.doc li{margin:4px 0}
.doc .updated{color:var(--note);font-weight:700;margin:0 0 20px}
.doc a{color:var(--link);font-weight:600;overflow-wrap:anywhere}
.doc section{background:var(--inset);border:3px solid var(--ink);border-radius:18px;padding:4px 18px 14px;margin-top:24px}
.doc section h2{margin-top:16px}
@media (min-width:700px){.doc{padding:36px 44px 44px}.doc h1{font-size:2.5rem}}
.night .doc{width:100%;max-width:720px;margin:0 auto;padding:28px 20px 56px;border:0;border-radius:0;background:none;box-shadow:none}
`);

const LOGO = `<img src="${MEDIA.logo}" alt="" width="44" height="44">`;
/** The trademark credit Apple's badge guidelines ask for wherever the badge appears. */
export const APPLE_CREDIT =
  "Apple, the Apple logo, iPhone and iPad are trademarks of Apple Inc., registered in the U.S. and other countries and regions. App Store is a service mark of Apple Inc.";

type Current = "home" | "support" | "privacy" | undefined;

const header = (links: boolean, current: Current): string => {
  if (!links) return `<header class="top"><span class="brand">${LOGO}Pounce</span></header>`;
  const item = (href: string, label: string, here: boolean) => `<a href="${href}"${here ? ' aria-current="page"' : ""}>${label}</a>`;
  return `<a class="skip" href="#main">Skip to content</a>
<header class="top"><a class="brand" href="/"${current === "home" ? ' aria-current="page"' : ""}>${LOGO}Pounce</a><nav aria-label="Site">${item("/support", "Support", current === "support")}${item("/privacy", "Privacy", current === "privacy")}</nav></header>`;
};

const footer = (links: boolean, credit: boolean): string =>
  links
    ? `<footer class="foot"><div class="wrap">
<p><strong>Pounce: Family Games</strong><br>Card game for couples and kids.</p>
<ul><li><a href="/support">Support</a></li><li><a href="/privacy">Privacy policy</a></li><li><a href="https://conleychaos.com">Conley Chaos LLC</a></li></ul>
<p>&copy; 2026 Conley Chaos LLC</p>${credit ? `\n<small>${APPLE_CREDIT}</small>` : ""}
</div></footer>`
    : `<footer class="foot"><div class="wrap"><p><strong>Pounce: Family Games</strong><br>&copy; 2026 Conley Chaos LLC</p></div></footer>`;

export type Shell = {
  title: string;
  /** Extra `<head>` lines, each ending in a newline. */
  head?: string;
  /** Page styles, after the shared ones. */
  style?: string;
  /** Everything inside `<body>` between the header and the footer, `<main>` included. */
  body: string;
  /** False on the invite pages, which carry no links but the install one. */
  links?: boolean;
  current?: Current;
  /** The Apple trademark credit, on pages that show Apple's badge. */
  credit?: boolean;
  /**
   * A page the app shows inside its own sheet (the notice to parents): no header or footer, so
   * there is nothing to tap that leads away, and the app's night colours whatever the device's
   * appearance, as the sheet around it has.
   */
  embedded?: boolean;
};

/** A whole page in the shared look. */
export function shell(opts: Shell): string {
  const links = opts.links ?? true;
  const chrome = !opts.embedded;
  return `<!doctype html>
<html lang="en"${chrome ? "" : ' class="night"'}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="${TOKENS.light.bg}" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="${TOKENS.dark.bg}" media="(prefers-color-scheme: dark)">
<title>${opts.title}</title>
<link rel="icon" href="${MEDIA.favicon}">
${opts.head ?? ""}<style>${BASE}${opts.style ?? ""}</style>
</head>
<body>
${chrome ? `${header(links, opts.current)}\n` : ""}${opts.body}${chrome ? `\n${footer(links, opts.credit ?? false)}` : ""}
</body>
</html>
`;
}

/** A text page (support, privacy, the notice to parents): one readable panel. */
export function docPage(opts: { title: string; body: string; head?: string; current?: Current; embedded?: boolean }): string {
  return shell({
    title: opts.title,
    ...(opts.head === undefined ? {} : { head: opts.head }),
    ...(opts.embedded ? { embedded: true } : {}),
    style: DOC,
    current: opts.current,
    body: `<main id="main">
<div class="doc">
${opts.body}
</div>
</main>`,
  });
}
