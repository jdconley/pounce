import { describe, expect, test } from "vitest";

import { getRedirect, homePage, llmsTxt, robotsTxt, sitemapXml, supportPage } from "./site";

const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

describe("supportPage", () => {
  test("is a static, script-free page", async () => {
    const res = supportPage();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    const html = await res.text();
    expect(html).not.toContain("<script");
    expect(html).toContain('<meta name="viewport"');
  });

  test("covers each topic, the privacy contact and the privacy link", async () => {
    const html = await supportPage().text();
    for (const s of ["Create", "House Cat", "Reminders", "Add a child", "Report", "Block", "Delete my data", 'href="/privacy"', 'href="mailto:privacy@conleychaos.com"']) {
      expect(html, s).toContain(s);
    }
    expect(html).not.toMatch(/kitten/i);
  });
});

describe("homePage (the landing page; home.test.ts covers it)", () => {
  test("names the app and links to support and privacy, with no install link by default", async () => {
    const res = homePage();
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("Pounce: Family Games");
    expect(html).toContain('href="/support"');
    expect(html).toContain('href="/privacy"');
    expect(html).not.toContain("Get the app");
    expect(html).toContain("Coming soon to the App Store");
  });
});

describe("getRedirect (/get)", () => {
  const ORIGIN = "https://play.conleychaos.com";
  const APP_STORE = "https://apps.apple.com/app/id6829560061";
  const TESTFLIGHT = "https://testflight.apple.com/join/abc123";

  test("goes to the App Store, else TestFlight, else home, and is never cached", () => {
    for (const [install, to] of [
      [{ appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT }, APP_STORE],
      [{ appStoreUrl: APP_STORE }, APP_STORE],
      [{ appStoreUrl: "", testflightUrl: TESTFLIGHT }, TESTFLIGHT],
      [{ testflightUrl: TESTFLIGHT }, TESTFLIGHT],
      [{}, `${ORIGIN}/`],
      [{ appStoreUrl: "", testflightUrl: "" }, `${ORIGIN}/`],
    ] as const) {
      const res = getRedirect(install, ORIGIN);
      expect(res.status, to).toBe(302);
      expect(res.headers.get("location")).toBe(to);
      expect(res.headers.get("cache-control")).toBe("no-store");
    }
  });

  test("never redirects to a link that isn't https", () => {
    for (const bad of ["http://apps.apple.com/app/id1", "javascript:alert(1)", "//evil.test", " https://x.test"]) {
      expect(getRedirect({ appStoreUrl: bad, testflightUrl: bad }, ORIGIN).headers.get("location"), bad).toBe(`${ORIGIN}/`);
    }
  });
});

describe("robots.txt and the sitemap", () => {
  test("robots.txt allows the pages, keeps crawlers off the API and names the sitemap", async () => {
    const res = robotsTxt("https://play.conleychaos.com");
    expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(await res.text()).toBe("User-agent: *\nAllow: /\nDisallow: /v1/\n\nSitemap: https://play.conleychaos.com/sitemap.xml\n");
  });

  test("the sitemap lists the three public pages", async () => {
    const res = sitemapXml("https://play.conleychaos.com");
    expect(res.headers.get("content-type")).toBe("application/xml; charset=utf-8");
    const xml = await res.text();
    expect(xml.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    expect([...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1])).toEqual([
      "https://play.conleychaos.com/",
      "https://play.conleychaos.com/support",
      "https://play.conleychaos.com/privacy",
    ]);
    expect(await sitemapXml("https://x.test/?a&b<c>").text()).toContain("<loc>https://x.test/?a&amp;b&lt;c&gt;/</loc>");
  });

  test("llms.txt is a short Markdown summary that links the pages and makes no claim the site doesn't", async () => {
    const res = llmsTxt("https://play.conleychaos.com");
    expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    const text = await res.text();
    expect(text.startsWith("# Pounce: Family Games\n")).toBe(true);
    for (const s of ["Cat Tower", "no chat, no ads, no analytics and no tracking", "(https://play.conleychaos.com/support)", "(https://play.conleychaos.com/privacy)", "(https://play.conleychaos.com/get)"]) {
      expect(text, s).toContain(s);
    }
    expect(text).not.toMatch(/\p{Extended_Pictographic}/u);
    // Like the privacy policy, it mentions a parent's choice only when parent consent is on.
    expect(text).toContain("a parent decides whether they get notifications");
    const off = await llmsTxt("https://play.conleychaos.com", false).text();
    expect(off).toContain("they get no push notifications from our server");
    expect(off).not.toContain("a parent decides");
  });
});
