import { describe, expect, test } from "vitest";

import { appSiteAssociation, ogImage, pouncePage, sharePage } from "./links";

const ORIGIN = "https://play.conleychaos.com";

const TESTFLIGHT = "https://testflight.apple.com/join/abc123";
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
    const res = sharePage("BCDFG", undefined, ORIGIN);
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
    const html = await sharePage("BCDFG", undefined, ORIGIN).text();
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
    const html = await sharePage("BCDFG", undefined, 'https://x.test"><script>').text();
    expect(html).toContain('content="https://x.test&quot;&gt;&lt;script&gt;/og/room.jpg"');
    expect(html).not.toContain("<script");
  });

  test("the Get the app link appears only when a TestFlight URL is set", async () => {
    const without = await sharePage("BCDFG", undefined, ORIGIN).text();
    expect(without).not.toContain("Get the app");
    expect(without).not.toContain("<a ");

    const withLink = await sharePage("BCDFG", TESTFLIGHT, ORIGIN).text();
    expect(withLink).toContain(`<a href="${TESTFLIGHT}">Get the app</a>`);
  });

  test("a TestFlight URL that is not https is omitted", async () => {
    for (const url of ["http://testflight.apple.com/join/x", "javascript:alert(1)", "", " https://x.test"]) {
      const html = await sharePage("BCDFG", url, ORIGIN).text();
      expect(html, url).not.toContain("Get the app");
    }
  });

  test("the TestFlight URL is HTML-escaped", async () => {
    const html = await sharePage("BCDFG", 'https://x.test/?a=1&b="2"><script>', ORIGIN).text();
    expect(html).toContain('href="https://x.test/?a=1&amp;b=&quot;2&quot;&gt;&lt;script&gt;"');
    expect(html).not.toContain("<script");
  });

  test("an invalid code is a plain-text 404 and is never echoed", async () => {
    for (const code of ["bad!", "<script>", "BCDF", "BCDFGH", "bcdfg", "AEIOU", "BCDF0", ""]) {
      const res = sharePage(code, TESTFLIGHT, ORIGIN);
      expect(res.status, code).toBe(404);
      expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
      expect(await res.text()).not.toContain(code || "\u0000");
    }
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
    const res = pouncePage({ name: "Mia <3", cat: 2 }, token, TESTFLIGHT, ORIGIN);
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

  test("an unknown or used link is a plain 404 that says nothing", async () => {
    const res = pouncePage(null, "A".repeat(22), TESTFLIGHT, ORIGIN);
    expect(res.status).toBe(404);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.text()).toBe("Not found");
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
