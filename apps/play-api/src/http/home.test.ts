import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { DAILY_DESCRIPTION, DESCRIPTION, HOME_CSP, homePage, installState } from "./home";
import { APPLE_CREDIT } from "./layout";
import { MEDIA } from "./site-media";

const ORIGIN = "https://play.conleychaos.com";
const APP_STORE = "https://apps.apple.com/app/id6829560061";
const TESTFLIGHT = "https://testflight.apple.com/join/abc123";

const html = (install = {}, consent = true) => homePage(install, ORIGIN, consent).text();
/** The page's structured data: the graph of the app and the web player. */
const graph = (page: string) =>
  (JSON.parse(/<script type="application\/ld\+json">(.*?)<\/script>/.exec(page)?.[1] ?? "null") as { "@context": string; "@graph": Record<string, unknown>[] });
/** The iPhone and iPad app's node in the structured data. */
const ld = (page: string) => graph(page)["@graph"].find((node) => node["@type"] === "MobileApplication") ?? {};
/** The web player's node in the structured data. */
const web = (page: string) => graph(page)["@graph"].find((node) => node["@type"] === "WebApplication") ?? {};
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

  test("says what Pounce is and shows the real games, in every install state", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const page = await html(install);
      expect(page).toContain("<title>Pounce: Family Games | Cat Tower and Tuna Tiles</title>");
      expect(page).toMatch(/<h1 id="top">Family game night, <span>every night\.<\/span><\/h1>/);
      expect(page.match(/<h1/g)).toHaveLength(1);
      expect(page).toContain("Two games for the whole family. Gather round the TV, pass one phone, or play from far away.");
      for (const s of ["Two games", "Put the table on the TV", "One table, any device", "Add players your way", "Play now or over days", "Made with kids in mind"]) {
        expect(page, s).toContain(s);
      }
      // Both games, with their player counts.
      expect(page).toContain("<h3>Cat Tower</h3><p class=\"meta\">Cards. 2 to 6 players.</p>");
      expect(page).toContain("<h3>Tuna Tiles</h3><p class=\"meta\">Tiles. 2 to 4 players.</p>");
      // Six real screenshots (the TV twice, a phone at the TV, a laptop, each game on iPhone) and the clip, with a poster.
      expect(page.match(/<img src="\/static\/[a-z-]+-\d+\.[0-9a-f]{10}\.jpg" srcset=/g)).toHaveLength(6);
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
    expect(page).toContain("@media (prefers-reduced-motion:reduce){.handset .clip{display:none}.handset .still{display:block}}");
    expect(page).toMatch(/<img class="still" src="[^"]+\.jpg" alt="[^"]{20,}"/);
  });

  test("coming soon (today): says so, with no install link, no QR code, no banner and no store link in the data", async () => {
    for (const install of [{}, { appStoreUrl: "", testflightUrl: "" }, { appStoreUrl: "not a url" }]) {
      const page = await html(install);
      expect(page.match(/<p class="soon">Coming soon to the App Store<\/p>/g)).toHaveLength(2);
      // The only links in the body go to the web player and the privacy policy: nothing that looks like a button goes nowhere.
      expect(main(page).match(/<a [^>]*>/g)).toEqual([
        '<a class="btn web" href="/play/">',
        '<a class="url" href="/play/tv">',
        '<a class="url" href="/play/">',
        '<a class="btn web" href="/play/">',
        '<a href="/privacy">',
        '<a href="/privacy#coppa">',
        '<a class="btn web" href="/play/">',
      ]);
      expect(page).toContain('<p class="fine">Free. Play in your browser today.</p>');
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
    expect(page).toContain("Play here in your browser, or scan this with your iPhone to join the beta.");
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
    // One short line: free, the app on iPhone and iPad, the browser on everything else.
    expect(page.match(/<p class="fine">Free\. Get the app on iPhone and iPad, or play in the browser on anything else\.<\/p>/g)).toHaveLength(2);
    expect(page).not.toContain("Free, for iPhone and iPad.");
  });

  test("Play in your browser: the web player beside the app at the top and the bottom, and in its own section, in every install state", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const page = await html(install);
      expect(page.match(/<a class="btn web" href="\/play\/">Play in your browser<\/a>/g), JSON.stringify(install)).toHaveLength(3);
      expect(page).toContain("iPhone, Android and computer players sit at the same table.");
      expect(page).toContain('<a class="url" href="/play/">play.conleychaos.com<wbr>/play</a>');
    }
  });

  test("on a computer, the QR card offers the browser as well as the iPhone app", async () => {
    const page = await html({ appStoreUrl: APP_STORE });
    expect(page.match(/<strong>On a computer\?<\/strong> Play here in your browser, or scan this with your iPhone to get the app\.<\/p>/g)).toHaveLength(2);
  });

  test("the TV: the web player's TV address, and only what a phone in the browser does today", async () => {
    const page = await html({ appStoreUrl: APP_STORE });
    expect(page).toContain('<a class="url" href="/play/tv">play.conleychaos.com<wbr>/play/tv</a>');
    expect(page).toContain("In a phone's browser, you see just your own cards. Tap Table for the whole board.");
    // Nothing about an Apple TV app or a cards-only iPhone app yet: neither is out.
    expect(page).not.toMatch(/Apple TV|tvOS|AirPlay/);
    expect(page).not.toMatch(/iPhone[^.<]*just your (own )?(cards|hand)/);
  });

  test("nothing stale: no Cat Tower-only story, no iPhone-only line, no old tagline", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const page = await html(install);
      for (const old of ["Cat Tower comes first", "more to come", "A game of Cat Tower runs", "Card game for couples and kids", "Free, for iPhone and iPad", "Cat Tower on iPhone. It plays the same on iPad."]) {
        expect(page, old).not.toContain(old);
      }
      expect(page).not.toMatch(/one turn at a time|a turn at a time/i);
      expect(page).not.toMatch(/[\u2013\u2014]/);
    }
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
      `<meta name="description" content="${DESCRIPTION}">`,
      '<meta property="og:title" content="Pounce: Family Games | Cat Tower and Tuna Tiles">',
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
    expect(DESCRIPTION).toMatch(/^Family game night, every night\. /);
    expect(DESCRIPTION).toContain("Cat Tower and Tuna Tiles");
    expect(DESCRIPTION.length).toBeLessThanOrEqual(160);
    expect(graph(page)["@context"]).toBe("https://schema.org");
    expect(ld(page)).toMatchObject({
      "@type": "MobileApplication",
      name: "Pounce: Family Games",
      description: DESCRIPTION,
      url: `${ORIGIN}/`,
      image,
      operatingSystem: "iOS, iPadOS",
      applicationCategory: "GameApplication",
      author: { "@type": "Organization", name: "Conley Chaos LLC", url: "https://conleychaos.com" },
    });
    // The web player is free in every install state.
    expect(web(page)).toMatchObject({
      "@type": "WebApplication",
      url: `${ORIGIN}/play/`,
      operatingSystem: "Any",
      applicationCategory: "GameApplication",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
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

  test("landmarks and a skip link", async () => {
    const page = await html();
    expect(page).toContain('<a class="skip" href="#main">Skip to content</a>');
    expect(page).toContain('<main id="main">');
    expect(page).toContain('<nav aria-label="Site">');
    expect(page).toContain('<footer class="foot">');
    for (const id of ["top", "games", "tv", "anywhere", "ways", "pace", "kids", "get"]) {
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
      "No third-party analytics or SDKs. We never sell your data.",
      "Signing in is never required to play.",
      "picks a name from Pounce's list of cat names and can't type one",
      "A parent decides on notifications.",
      "A child under 13 gets none from our server unless a parent allows them",
      "The people at your tables see your name and your cat, and so does anyone who opens an invite link you send.",
      "Report or block a player from their card at your table.",
      "made for adults playing with their families, not for children on their own",
      'href="/privacy#coppa"',
    ]) {
      expect(withConsent, s).toContain(s);
    }
    const without = await html({}, false);
    expect(without).toContain("<strong>No push notifications for under-13s.</strong> A child under 13 gets none from our server.");
    expect(without).toContain("The only reminders are ones the phone schedules for itself, and they start off.");
    expect(without).not.toContain("A parent decides");
    // Nothing here says a name is seen "only" by anyone: invites and notifications show it too.
    expect(withConsent).not.toMatch(/[Oo]nly the people/);
    // No invented praise or numbers.
    expect(withConsent).not.toMatch(/\bstars?\b|rated|reviews|downloads|award|featured/i);
  });

  test("the Daily Dish shows only with DAILY on, as in the browser and coming to the app", async () => {
    for (const install of [{}, { testflightUrl: TESTFLIGHT }, { appStoreUrl: APP_STORE }]) {
      const off = await html(install);
      expect(off).not.toMatch(/Daily Dish|daily puzzle|Sniff|Nine Lives|Cat Nap|Box Fort|\/play\/daily/);
      const on = await homePage(install, ORIGIN, true, true).text();
      expect(on).toContain('<h2 id="dish">The Daily Dish</h2>');
      for (const name of ["Sniff", "Nine Lives", "Cat Nap", "Box Fort"]) expect(on, name).toContain(`<h3>${name}</h3>`);
      expect(on).toContain('<a class="btn web" href="/play/daily">Play today\'s puzzles</a>');
      expect(on).toContain("In the browser now. Coming to the app.");
      expect(on).toContain("Two games for the whole family, and four new puzzles every day.");
      // Who sees a result: the privacy policy's words.
      expect(on).toContain("Only the people you have a streak with see how you did, and a TV you linked to your board.");
      // The page's description names the puzzles; the App Store app's own entry doesn't claim them.
      expect(on).toContain(`<meta name="description" content="${DAILY_DESCRIPTION}">`);
      expect(on).toContain(`<meta property="og:description" content="${DAILY_DESCRIPTION}">`);
      expect(ld(on).description).toBe(DESCRIPTION);
      expect(web(on).description).toContain("/play/daily");
      expect(web(off).description).not.toContain("daily");
      // No other game's name, and no emoji.
      expect(on).not.toMatch(/\b(wordle|block blast|zoodoku|sudoku|new york times|nyt)\b/i);
      expect(main(on)).not.toMatch(/\p{Extended_Pictographic}/u);
    }
  });
});
