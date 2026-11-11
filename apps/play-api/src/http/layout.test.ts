import qrcode from "qrcode-generator";
import { describe, expect, test } from "vitest";

import { noticePage } from "../consent/pages";

import { homePage } from "./home";
import { BASE, TOKENS, docPage, shell } from "./layout";
import { deadLinkPage, pouncePage, sharePage } from "./links";
import { privacyPage } from "./privacy";
import { supportPage } from "./site";
import { MEDIA } from "./site-media";

const ORIGIN = "https://play.conleychaos.com";
const APP_STORE = "https://apps.apple.com/app/id6829560061";
const TESTFLIGHT = "https://testflight.apple.com/join/abc123";

/** Every page the Worker serves, in each state that changes what it loads. */
const pages = (): [string, Response][] => [
  ["home, coming soon", homePage({}, ORIGIN)],
  ["home, beta", homePage({ testflightUrl: TESTFLIGHT }, ORIGIN)],
  ["home, App Store", homePage({ appStoreUrl: APP_STORE }, ORIGIN)],
  ["home, no consent", homePage({}, ORIGIN, false)],
  ["support", supportPage()],
  ["privacy", privacyPage(true)],
  ["privacy, no consent", privacyPage(false)],
  ["notice to parents", noticePage()],
  ["room invite", sharePage("BCDFG", { appStoreUrl: APP_STORE }, ORIGIN)],
  ["pounce invite", pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), { testflightUrl: TESTFLIGHT }, ORIGIN)],
  ["expired invite", deadLinkPage({})],
];

/** sRGB relative luminance and the WCAG contrast ratio of two #RRGGBB colours. */
const luminance = (hex: string): number => {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a: string, b: string): number => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
};

describe("no page loads anything from another host", () => {
  test("scripts, styles, fonts, images, video and icons all come from this site or are inlined", async () => {
    for (const [name, res] of pages()) {
      const html = await res.text();
      // Everything a browser fetches by itself: src, srcset, poster, and <link href>.
      const loads = [
        ...[...html.matchAll(/\s(?:src|poster)="([^"]*)"/g)].map((m) => m[1] as string),
        ...[...html.matchAll(/\ssrcset="([^"]*)"/g)].flatMap((m) => (m[1] as string).split(",").map((part) => part.trim().split(" ")[0] as string)),
        ...[...html.matchAll(/<link\b[^>]*>/g)].filter((m) => !/rel="canonical"/.test(m[0])).map((m) => /\shref="([^"]*)"/.exec(m[0])?.[1] ?? ""),
      ];
      // At least the favicon; every page with a header also has the logo.
      expect(loads.length, name).toBeGreaterThan(0);
      for (const url of loads) {
        expect(url, `${name}: ${url.slice(0, 60)}`).toMatch(/^(?:\/(?!\/)|data:image\/)/);
      }
      // No stylesheet, font or import by URL, and no CSS url() at all.
      expect(html, name).not.toMatch(/url\(|@import|@font-face|<link[^>]+rel="stylesheet"|<iframe|<object|<embed/i);
      // No script that runs: the landing page's structured data is the only script element anywhere.
      expect((html.match(/<script[^>]*>/g) ?? []).filter((tag) => tag !== '<script type="application/ld+json">'), name).toEqual([]);
      // The policy the browser enforces says the same.
      const csp = res.headers.get("content-security-policy") ?? "";
      expect(csp, name).toContain("default-src 'none'");
      expect(csp, name).not.toMatch(/https?:|\*/);
    }
  });

  test("links out go only to Conley Chaos, the App Store or TestFlight, and mail to us", async () => {
    for (const [name, res] of pages()) {
      const html = await res.text();
      const out = [...html.matchAll(/<a\b[^>]*\shref="([^"]*)"/g)].map((m) => m[1] as string).filter((href) => !href.startsWith("/") && !href.startsWith("#"));
      for (const href of out) {
        expect(href, name).toMatch(/^(?:https:\/\/conleychaos\.com$|https:\/\/apps\.apple\.com\/|https:\/\/testflight\.apple\.com\/|mailto:privacy@conleychaos\.com$)/);
      }
    }
  });
});

describe("the shared look", () => {
  test("every page has the header, the footer with the copyright line, a favicon and no emoji", async () => {
    for (const [name, res] of pages()) {
      const html = await res.text();
      expect(html, name).toContain(`<link rel="icon" href="${MEDIA.favicon}">`);
      expect(html, name).toContain(BASE);
      expect(html, name).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">');
      expect(html, name).not.toMatch(/\p{Extended_Pictographic}/u);
      // The notice to parents is shown inside the app's consent sheet: see the next test.
      if (name === "notice to parents") continue;
      expect(html, name).toContain('<header class="top">');
      expect(html, name).toContain(`<img src="${MEDIA.logo}" alt="" width="44" height="44">Pounce`);
      expect(html, name).toContain('<footer class="foot">');
      expect(html, name).toContain("&copy; 2026 Conley Chaos LLC");
      expect(html, name).toContain('<html lang="en">');
    }
  });

  test("the notice to parents, which the app shows in its consent sheet, has no header or footer and keeps the app's night colours", async () => {
    const html = await noticePage().text();
    expect(html).toContain('<html lang="en" class="night">');
    expect(html).toContain('<body>\n<main id="main">');
    expect(html).toContain("</main>\n</body>");
    expect(html).not.toContain("<header");
    expect(html).not.toContain("<footer");
    expect(html).not.toContain('class="skip"');
    // The only things to tap are the notice's own: our address, and the full policy.
    expect([...new Set([...html.matchAll(/<a\b[^>]*\shref="([^"]*)"/g)].map((m) => m[1]))]).toEqual(["mailto:privacy@conleychaos.com", "/privacy"]);
  });

  test("the text pages link home, support, privacy and Conley Chaos; the invite pages carry no links of their own", async () => {
    for (const res of [supportPage(), privacyPage(), homePage({}, ORIGIN)]) {
      const html = await res.text();
      for (const s of ['<a class="brand" href="/"', '<a href="/support"', '<a href="/privacy"', '<a href="https://conleychaos.com">Conley Chaos LLC</a>', '<a class="skip" href="#main">']) {
        expect(html, s).toContain(s);
      }
    }
    expect(await supportPage().text()).toContain('<a href="/support" aria-current="page">Support</a>');
    expect(await privacyPage().text()).toContain('<a href="/privacy" aria-current="page">Privacy</a>');
    for (const res of [sharePage("BCDFG", {}, ORIGIN), deadLinkPage({}), pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), {}, ORIGIN)]) {
      expect(await res.text()).not.toContain("<a ");
    }
  });

  test("shell and docPage put the page's own head and styles after the shared ones", () => {
    const html = shell({ title: "T", head: '<meta name="x" content="y">\n', style: ".z{color:red}", body: "<main>hi</main>" });
    expect(html).toContain("<title>T</title>");
    expect(html).toContain(`<meta name="x" content="y">\n<style>${BASE}.z{color:red}</style>`);
    expect(html).toContain("<main>hi</main>");
    expect(html).not.toContain("trademarks of Apple");
    expect(docPage({ title: "D", body: "<h1>D</h1>" })).toContain('<main id="main">\n<div class="doc">\n<h1>D</h1>\n</div>\n</main>');
  });

  test("colours meet WCAG AA (4.5:1) in light and dark", () => {
    const INK = "#1B0B3A";
    for (const [mode, t] of Object.entries(TOKENS)) {
      const pairs: [string, string, string][] = [
        ["white on the page", "#FFFFFF", t.bg],
        ["white on the footer", "#FFFFFF", t.deep],
        ["footer small print", "#E4DAFF", t.deep],
        ["hero small print", "#F0E9FF", t.bg],
        ["headline yellow on the page", "#FFD21F", t.bg],
        ["panel text", t.text, t.panel],
        ["panel muted text", t.muted, t.panel],
        ["panel link", t.link, t.panel],
        ["panel h1", t.h1, t.panel],
        ["panel h2", t.h2, t.panel],
        ["panel note", t.note, t.panel],
        ["inset text", t.text, t.inset],
        ["inset link", t.link, t.inset],
        ["inset h2", t.h2, t.inset],
      ];
      for (const [what, fg, bg] of pairs) {
        expect(contrast(fg, bg), `${mode}: ${what} (${fg} on ${bg})`).toBeGreaterThanOrEqual(4.5);
      }
    }
    // The keyboard focus ring (3:1 for a non-text mark): yellow on the page, the link colour on panels.
    for (const t of Object.values(TOKENS)) {
      for (const [ring, surface] of [["#FFD21F", t.bg], ["#FFD21F", t.deep], [t.link, t.panel], [t.link, t.inset]] as const) {
        expect(contrast(ring, surface), `${ring} on ${surface}`).toBeGreaterThanOrEqual(3);
      }
    }
    // Ink on the candy colours: buttons, chips, the step numbers and the check marks.
    for (const candy of ["#FFC21A", "#FF8A00", "#00D1C1", "#FFD21F", "#9BE22E"]) {
      expect(contrast(INK, candy), candy).toBeGreaterThanOrEqual(4.5);
    }
    // White on the last panel's gradient, at both ends, by day and by night.
    for (const end of ["#7B2FFF", "#C2188A", "#5B1FD1", "#8A1466"]) {
      expect(contrast("#FFFFFF", end), end).toBeGreaterThanOrEqual(4.5);
    }
  });
});

describe("the QR code", () => {
  test("is the code for /get, as a QR encoder draws it", () => {
    expect(MEDIA.qr.url).toBe("https://play.conleychaos.com/get");
    const qr = qrcode(0, "M");
    qr.addData(MEDIA.qr.url);
    qr.make();
    expect(MEDIA.qr.size).toBe(qr.getModuleCount());
    // Redraw the path's rectangles onto a grid and compare it module by module.
    const grid = Array.from({ length: MEDIA.qr.size }, () => new Array<boolean>(MEDIA.qr.size).fill(false));
    for (const m of MEDIA.qr.path.matchAll(/M(\d+) (\d+)h(\d+)v1h-\d+z/g)) {
      const [x, y, run] = [Number(m[1]), Number(m[2]), Number(m[3])];
      for (let i = 0; i < run; i++) (grid[y] as boolean[])[x + i] = true;
    }
    for (let y = 0; y < MEDIA.qr.size; y++) {
      for (let x = 0; x < MEDIA.qr.size; x++) {
        expect((grid[y] as boolean[])[x], `${x},${y}`).toBe(qr.isDark(y, x));
      }
    }
  });
});
