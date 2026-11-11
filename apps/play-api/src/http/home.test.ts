import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { HOME_CSP, homePage, installState } from "./home";
import { APPLE_CREDIT } from "./layout";
import { MEDIA } from "./site-media";

const ORIGIN = "https://play.conleychaos.com";
const APP_STORE = "https://apps.apple.com/app/id6829560061";
const TESTFLIGHT = "https://testflight.apple.com/join/abc123";

const html = (install = {}, consent = true) => homePage(install, ORIGIN, consent).text();
/** The page's structured data. */
const ld = (page: string) => JSON.parse(/<script type="application\/ld\+json">(.*?)<\/script>/.exec(page)?.[1] ?? "null") as Record<string, unknown>;
/** Everything between `<main` and `</main>`: the page without its header and footer. */
const main = (page: string) => page.slice(page.indexOf("<main"), page.indexOf("</main>"));

describe("installState", () => {
  test("the App Store wins, then TestFlight, then coming soon; only https links count", () => {
    expect(installState({ appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT })).toEqual({ kind: "store", url: APP_STORE });
    expect(installState({ appStoreUrl: "", testflightUrl: TESTFLIGHT })).toEqual({ kind: "beta", url: TESTFLIGHT });
    expect(installState({ testflightUrl: TESTFLIGHT })).toEqual({ kind: "beta", url: TESTFLIGHT });
    for (const none of [{}, { appStoreUrl: "" }, { appStoreUrl: "http://apps.apple.com/app/id1", testflightUrl: "javascript:alert(1)" }]) {
      expect(installState(none)).toEqual({ kind: "soon" });
    }
  });
});

describe("homePage", () => {
  test("is a public, cacheable page that loads only from its own host", async () => {
    const res = homePage({}, ORIGIN);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("public, max-age=300");
    expect(res.headers.get("content-security-policy")).toBe(HOME_CSP);
    expect(HOME_CSP).toContain("default-src 'none'");
    // Nothing but this site: no other host, no wildcard, and no script source at all.
    expect(HOME_CSP).not.toMatch(/https?:|\*|script-src|unsafe-eval/);
    expect(HOME_CSP.match(/'self'/g)).toHaveLength(3);
  });

  test("says what Pounce is and shows the real game, in every install state", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const page = await html(install);
      expect(page).toContain("<title>Pounce: Family Games | Card game for couples and kids</title>");
      expect(page).toMatch(/<h1 id="top">Game night, <span>one turn at a time\.<\/span><\/h1>/);
      expect(page.match(/<h1/g)).toHaveLength(1);
      expect(page).toContain("Pounce is a card game for couples and families.");
      for (const s of ["How a game works", "Play it your way", "Made with kids in mind", "Cat Tower is the first game in Pounce, with more to come."]) {
        expect(page, s).toContain(s);
      }
      // Six store screenshots and the clip, with a poster.
      expect(page.match(/<li><picture>/g)).toHaveLength(6);
      expect(page).toContain(`<source src="${MEDIA.clip.src}" type="video/mp4" media="(prefers-reduced-motion: no-preference)">`);
      expect(page).toContain(`poster="${MEDIA.clip.poster}"`);
      expect(page).not.toMatch(/\p{Extended_Pictographic}/u);
    }
  });

  test("the clip is muted, inline, looping and pausable, and does not play for people who prefer reduced motion", async () => {
    const page = await html();
    const video = /<video[^>]*>/.exec(page)?.[0] ?? "";
    for (const attr of [" autoplay", " muted", " loop", " playsinline", " controls", ' preload="metadata"', " aria-label="]) {
      expect(video, attr).toContain(attr);
    }
    // Its one source applies only without the preference; with it, CSS swaps the video for a still.
    expect(page.match(/<source src=/g)).toHaveLength(1);
    expect(page).toContain("@media (prefers-reduced-motion:reduce){.phone .clip{display:none}.phone .still{display:block}}");
    expect(page).toMatch(/<img class="still" src="[^"]+\.jpg" alt="[^"]{20,}"/);
  });

  test("coming soon (today): says so, with no install link, no QR code, no banner and no store link in the data", async () => {
    for (const install of [{}, { appStoreUrl: "", testflightUrl: "" }, { appStoreUrl: "not a url" }]) {
      const page = await html(install);
      expect(page.match(/<p class="soon">Coming soon to the App Store<\/p>/g)).toHaveLength(2);
      // The only links in the body are the two to the privacy policy: nothing that looks like a button goes nowhere.
      expect(main(page).match(/<a [^>]*>/g)).toEqual(['<a href="/privacy">', '<a href="/privacy#coppa">']);
      expect(page).not.toContain('class="btn"');
      expect(page).not.toContain('class="badge"');
      expect(page).not.toContain('class="qr"');
      expect(page).not.toContain("apple-itunes-app");
      expect(page).not.toContain("apps.apple.com");
      expect(page).not.toContain("testflight");
      expect(ld(page)).not.toHaveProperty("installUrl");
      expect(ld(page)).not.toHaveProperty("offers");
    }
  });

  test("TestFlight only: a labelled beta button at the top and the bottom, and the QR code for a computer", async () => {
    const page = await html({ testflightUrl: TESTFLIGHT });
    expect(page.match(new RegExp(`<a class="btn" href="${TESTFLIGHT}">Join the beta on TestFlight</a>`, "g"))).toHaveLength(2);
    // One short line: it is free, it is a beta, it runs through TestFlight, and the App Store release is coming.
    expect(page.match(/<p class="fine"><strong>Free beta<\/strong> through Apple's TestFlight app, for iPhone and iPad\. The App Store release is coming\.<\/p>/g)).toHaveLength(2);
    expect(page).toContain('<h2 id="get">Join the beta</h2>');
    expect(page.match(/<div class="qr">/g)).toHaveLength(2);
    expect(page).not.toContain('class="badge"');
    expect(page).not.toContain("Download on the App Store");
    expect(page).not.toContain("apple-itunes-app");
    expect(page).not.toContain('class="soon"');
    expect(ld(page)).not.toHaveProperty("installUrl");
  });

  test("App Store: Apple's badge at the top and the bottom, the Smart App Banner, the QR code and the trademark credit", async () => {
    const page = await html({ appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT });
    const badge = `<a class="badge" href="${APP_STORE}"><img src="${MEDIA.badge.src}" alt="Download on the App Store" width="120" height="40"></a>`;
    expect(page.split(badge)).toHaveLength(3);
    expect(page).toContain('<meta name="apple-itunes-app" content="app-id=6829560061">');
    expect(page.match(/<div class="qr">/g)).toHaveLength(2);
    expect(page).toContain(APPLE_CREDIT);
    expect(page).not.toContain(TESTFLIGHT);
    expect(page).not.toContain("beta");
    expect(page).not.toContain('class="soon"');
    expect(ld(page)).toMatchObject({ installUrl: APP_STORE, offers: { "@type": "Offer", price: "0", priceCurrency: "USD" } });
  });

  test("the install link is HTML-escaped", async () => {
    const page = await html({ appStoreUrl: 'https://apps.apple.com/app/id1234567?a=1&b="2"><script>' });
    expect(page).toContain('href="https://apps.apple.com/app/id1234567?a=1&amp;b=&quot;2&quot;&gt;&lt;script&gt;"');
    expect(page).not.toContain('"2"><script>');
    expect(ld(page).installUrl).toBe('https://apps.apple.com/app/id1234567?a=1&b="2"><script>');
  });

  test("the QR code is drawn on the server and opens /get on this site", async () => {
    const page = await html({ appStoreUrl: APP_STORE });
    expect(MEDIA.qr.url).toBe(`${ORIGIN}/get`);
    expect(page).toContain(`<path fill="#1B0B3A" d="${MEDIA.qr.path}"/>`);
    expect(page).toContain('aria-label="QR code for play.conleychaos.com/get"');
    // Shown only where someone is likely on a computer: a wide screen with a mouse.
    expect(page).toContain(".qr{display:none;");
    expect(page).toContain("@media (min-width:900px) and (hover:hover) and (pointer:fine){.qr{display:flex}}");
  });

  test("metadata: description, canonical, icons, Open Graph and Twitter cards with the social image", async () => {
    const page = await html();
    const image = `${ORIGIN}${MEDIA.og.src}`;
    for (const tag of [
      '<meta name="description" content="Game night, one turn at a time. Play Cat Tower with your partner, your kids or the whole family, on one phone or from anywhere.">',
      `<link rel="canonical" href="${ORIGIN}/">`,
      '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
      `<link rel="icon" type="image/png" sizes="192x192" href="${MEDIA.icon192}">`,
      '<meta property="og:type" content="website">',
      `<meta property="og:url" content="${ORIGIN}/">`,
      `<meta property="og:image" content="${image}">`,
      '<meta property="og:image:width" content="1200">',
      '<meta property="og:image:height" content="630">',
      '<meta name="twitter:card" content="summary_large_image">',
      `<meta name="twitter:image" content="${image}">`,
    ]) {
      expect(page, tag).toContain(tag);
    }
    expect(ld(page)).toMatchObject({
      "@context": "https://schema.org",
      "@type": "MobileApplication",
      name: "Pounce: Family Games",
      url: `${ORIGIN}/`,
      image,
      operatingSystem: "iOS",
      applicationCategory: "GameApplication",
      author: { "@type": "Organization", name: "Conley Chaos LLC", url: "https://conleychaos.com" },
    });
  });

  test("the origin is escaped in the head and can't close the structured data", async () => {
    const page = await homePage({}, 'https://x.test"></script><script>alert(1)//').text();
    expect(page).toContain('<link rel="canonical" href="https://x.test&quot;&gt;&lt;/script&gt;&lt;script&gt;alert(1)///">');
    expect(page.match(/<script/g)).toHaveLength(1);
    expect(page.match(/<\/script>/g)).toHaveLength(1);
  });

  test("the only script element is the structured data; there are no forms and no inline handlers", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const page = await html(install);
      expect(page.match(/<script[^>]*>/g)).toEqual(['<script type="application/ld+json">']);
      expect(page).not.toContain("<form");
      expect(page).not.toContain("<iframe");
      expect(page).not.toMatch(/\son[a-z]+=/);
      expect(page).not.toContain("javascript:");
    }
  });

  test("every image has alt text and a size, and every file it names is in ./public", async () => {
    const page = await html({ appStoreUrl: APP_STORE });
    const imgs = page.match(/<img[^>]*>/g) ?? [];
    expect(imgs.length).toBeGreaterThan(15);
    for (const img of imgs) {
      expect(img, img).toMatch(/ alt="[^"]*"/);
      expect(img, img).toMatch(/ width="\d+" height="\d+"/);
    }
    // The six screenshots, the still and the two badges say what they show; decoration is alt="".
    expect(imgs.filter((img) => !img.includes('alt=""')).length).toBe(9);
    const files = new Set([...page.matchAll(/["' ,](\/(?:static|media)\/[A-Za-z0-9.-]+)/g)].map((m) => m[1] as string));
    files.add("/apple-touch-icon.png").add("/favicon.ico");
    expect(files.size).toBeGreaterThan(30);
    for (const file of files) {
      expect(existsSync(fileURLToPath(new URL(`../../public${file}`, import.meta.url))), file).toBe(true);
    }
  });

  test("landmarks, a skip link, and a keyboard-reachable screenshot strip", async () => {
    const page = await html();
    expect(page).toContain('<a class="skip" href="#main">Skip to content</a>');
    expect(page).toContain('<main id="main">');
    expect(page).toContain('<nav aria-label="Site">');
    expect(page).toContain('<footer class="foot">');
    expect(page).toContain('<div class="strip" role="region" aria-label="Screenshots of Pounce" tabindex="0">');
    for (const id of ["top", "look", "how", "ways", "kids", "first", "get"]) {
      expect(page, id).toContain(`aria-labelledby="${id}"`);
      expect(page, id).toMatch(new RegExp(`<h[12] id="${id}">`));
    }
  });

  test("the footer links support, the privacy policy and Conley Chaos, with the copyright line", async () => {
    const page = await html();
    const foot = page.slice(page.indexOf('<footer class="foot">'));
    for (const s of ['<a href="/support">Support</a>', '<a href="/privacy">Privacy policy</a>', '<a href="https://conleychaos.com">Conley Chaos LLC</a>', "&copy; 2026 Conley Chaos LLC"]) {
      expect(foot, s).toContain(s);
    }
  });

  test("the kids and privacy claims follow the privacy policy, with and without parent consent", async () => {
    const withConsent = await html({}, true);
    for (const s of [
      "No chat. No public profiles.",
      "No ads. No tracking.",
      "No analytics and no third-party SDKs. We never sell your data.",
      "Signing in is never required to play.",
      "picks a name from Pounce's list of cat names and can't type one",
      "A parent decides on turn alerts.",
      "gets no notifications from our server unless a parent allows them",
      "Report or block a player from their card at your table.",
      "made for adults playing with their families, not for children on their own",
      'href="/privacy#coppa"',
    ]) {
      expect(withConsent, s).toContain(s);
    }
    const without = await html({}, false);
    expect(without).toContain("A child under 13 gets no push notifications from our server.");
    expect(without).not.toContain("A parent decides on turn alerts.");
    // No invented praise or numbers.
    expect(withConsent).not.toMatch(/\bstars?\b|rated|reviews|downloads|award|featured/i);
  });
});
