import { describe, expect, test } from "vitest";

import { appSiteAssociation, appStoreId, deadLinkPage, ogImage, pouncePage, sharePage } from "./links";

const ORIGIN = "https://play.conleychaos.com";

const TESTFLIGHT = "https://testflight.apple.com/join/abc123";
const APP_STORE = "https://apps.apple.com/app/id1234567890";
const NONE = {};
const TF = { testflightUrl: TESTFLIGHT };
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

describe("appSiteAssociation", () => {
  test("serves the exact association JSON", async () => {
    const res = appSiteAssociation();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/json");
    expect(res.headers.get("cache-control")).toBe("public, max-age=300");
    expect(await res.json()).toEqual({
      applinks: {
        details: [{ appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }] }],
      },
    });
  });
});

describe("sharePage", () => {
  test("a valid code renders an html page with the code", async () => {
    const res = sharePage("BCDFG", NONE, ORIGIN);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("public, max-age=300");
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    const html = await res.text();
    expect(html).toContain("BCDFG");
    expect(html).toContain("Join the game");
    expect(html).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">');
    expect(html).toContain("<svg");
    expect(html).not.toContain("<script");
    expect(html).not.toMatch(/(?:src|href)="https?:/);
  });

  test("share page carries Open Graph tags pointing at the origin's image", async () => {
    const html = await sharePage("BCDFG", NONE, ORIGIN).text();
    expect(html).toContain('<meta property="og:title" content="Cat Tower">');
    expect(html).toContain('<meta property="og:image" content="https://play.conleychaos.com/og/room.jpg">');
    expect(html).toContain('<meta property="og:image:width" content="1200">');
    expect(html).toContain('<meta property="og:image:height" content="630">');
    expect(html).toContain('<meta name="twitter:card" content="summary_large_image">');
    expect(html).toContain('<meta property="og:description" content="BCDFG">');
    expect(html).toContain('<meta property="og:type" content="website">');
    expect(html).toContain('<meta property="og:url" content="https://play.conleychaos.com/j/BCDFG">');
  });

  test("the origin is HTML-escaped in the Open Graph tags", async () => {
    const html = await sharePage("BCDFG", NONE, 'https://x.test"><script>').text();
    expect(html).toContain('content="https://x.test&quot;&gt;&lt;script&gt;/og/room.jpg"');
    expect(html).not.toContain("<script");
  });

  test("the Get the app link appears only when a TestFlight URL is set", async () => {
    const without = await sharePage("BCDFG", NONE, ORIGIN).text();
    expect(without).not.toContain("Get the app");
    expect(without).not.toContain("<a ");

    const withLink = await sharePage("BCDFG", TF, ORIGIN).text();
    expect(withLink).toContain(`<a href="${TESTFLIGHT}">Get the app</a>`);
  });

  test("a TestFlight URL that is not https is omitted", async () => {
    for (const url of ["http://testflight.apple.com/join/x", "javascript:alert(1)", "", " https://x.test"]) {
      const html = await sharePage("BCDFG", { testflightUrl: url }, ORIGIN).text();
      expect(html, url).not.toContain("Get the app");
    }
  });

  test("the TestFlight URL is HTML-escaped", async () => {
    const html = await sharePage("BCDFG", { testflightUrl: 'https://x.test/?a=1&b="2"><script>' }, ORIGIN).text();
    expect(html).toContain('href="https://x.test/?a=1&amp;b=&quot;2&quot;&gt;&lt;script&gt;"');
    expect(html).not.toContain("<script");
  });

  test("an invalid code is the friendly 404 page and is never echoed", async () => {
    for (const code of ["bad!", "<script>", "BCDF", "BCDFGH", "bcdfg", "AEIOU", "BCDF0", ""]) {
      const res = sharePage(code, TF, ORIGIN);
      expect(res.status, code).toBe(404);
      expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
      expect(res.headers.get("cache-control")).toBe("no-store");
      const html = await res.text();
      expect(html).toContain("This invite has expired");
      if (code) expect(html).not.toContain(code);
    }
  });

  test("says how to come back after installing, with the code", async () => {
    const html = await sharePage("BCDFG", TF, ORIGIN).text();
    expect(html).toContain("No app yet? Install Pounce, then tap this link again.");
    expect(html).toContain("enter the code BCDFG");
  });
});

describe("with pounce links (§12.4)", () => {
  test("the association adds /p/*", async () => {
    expect(await appSiteAssociation(true).json()).toEqual({
      applinks: {
        details: [{ appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }, { "/": "/p/*" }] }],
      },
    });
  });

  test("the pounce page shows the sender's name and the bell card, with no caching and no referrer", async () => {
    const token = "A".repeat(22);
    const res = pouncePage({ name: "Mia <3", cat: 2 }, token, TF, ORIGIN);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(res.headers.get("x-robots-tag")).toBe("noindex");
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    const html = await res.text();
    expect(html).toContain("Mia &lt;3 wants to play");
    expect(html).not.toContain("Mia <3");
    expect(html).toContain(`<meta property="og:title" content="Mia &lt;3 wants to play">`);
    expect(html).toContain(`<meta property="og:url" content="${ORIGIN}/p/${token}">`);
    expect(html).toContain(`<meta property="og:image" content="${ORIGIN}/og/pounce.jpg">`);
    expect(html).toContain(`href="${TESTFLIGHT}"`);
    expect(html).not.toContain("<script");
    expect(html).not.toMatch(/\p{Extended_Pictographic}/u);
  });

  test("an unknown, used or expired link is a friendly 404 that says it expired and nothing else", async () => {
    const token = "A".repeat(22);
    const res = pouncePage(null, token, TF, ORIGIN);
    expect(res.status).toBe(404);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("x-robots-tag")).toBe("noindex");
    const html = await res.text();
    expect(html).toContain("<h1>This invite has expired</h1>");
    expect(html).toContain("Ask the person who sent it for a new one.");
    expect(html).toContain(`href="${TESTFLIGHT}"`);
    expect(html).not.toContain(token);
    expect(html).not.toContain("<script");
  });

  test("the pounce page says to install and tap the link again", async () => {
    const html = await pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), NONE, ORIGIN).text();
    expect(html).toContain("No app yet? Install it, then tap this link again.");
    expect(html).not.toContain("<a ");
  });
});

describe("the App Store link and Smart App Banner", () => {
  test("appStoreId reads the number from an App Store URL", () => {
    expect(appStoreId(APP_STORE)).toBe("1234567890");
    expect(appStoreId("https://apps.apple.com/us/app/pounce/id1234567890?mt=8")).toBe("1234567890");
    for (const bad of [undefined, "", "http://apps.apple.com/app/id1234567890", "https://apps.apple.com/app/pounce", "https://x.test/id12"]) {
      expect(appStoreId(bad), String(bad)).toBeNull();
    }
  });

  test("with APP_STORE_URL: the banner carries the page's own link, and Get the app goes to the App Store", async () => {
    const install = { appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT };
    const room = await sharePage("BCDFG", install, ORIGIN).text();
    expect(room).toContain(`<meta name="apple-itunes-app" content="app-id=1234567890, app-argument=${ORIGIN}/j/BCDFG">`);
    expect(room).toContain(`<a href="${APP_STORE}">Get the app</a>`);
    expect(room).not.toContain(TESTFLIGHT);
    const token = "B".repeat(22);
    const p = await pouncePage({ name: "Mia", cat: 2 }, token, install, ORIGIN).text();
    expect(p).toContain(`app-argument=${ORIGIN}/p/${token}">`);
    expect(await deadLinkPage(install).text()).toContain(`<a href="${APP_STORE}">Get the app</a>`);
  });

  test("without it (as now, until the App Store id is known): no banner", async () => {
    for (const install of [NONE, TF, { appStoreUrl: "" }]) {
      const html = await sharePage("BCDFG", install, ORIGIN).text();
      expect(html).not.toContain("apple-itunes-app");
    }
  });
});

describe("the beta note under Get the app", () => {
  const NOTE = "Pounce is in beta. This opens TestFlight, Apple's app for trying apps early.";

  test("a TestFlight link says it is a beta, on the room, pounce and expired pages", async () => {
    for (const res of [sharePage("BCDFG", TF, ORIGIN), pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), TF, ORIGIN), deadLinkPage(TF)]) {
      expect(await res.text()).toContain(`<a href="${TESTFLIGHT}">Get the app</a>\n<p class="note">${NOTE}</p>`);
    }
  });

  test("an App Store link, or no link, has no such note", async () => {
    for (const install of [NONE, { appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT }]) {
      expect(await sharePage("BCDFG", install, ORIGIN).text()).not.toContain("beta");
      expect(await deadLinkPage(install).text()).not.toContain("beta");
    }
  });
});

describe("ogImage", () => {
  test("is a cacheable jpeg", async () => {
    const res = ogImage();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    expect(res.headers.get("cache-control")).toBe("public, max-age=86400");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([bytes[0], bytes[1]]).toEqual([0xff, 0xd8]);
    expect(bytes.length).toBeGreaterThan(10_000);
  });
});
