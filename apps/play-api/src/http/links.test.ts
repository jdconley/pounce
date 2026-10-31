import { describe, expect, test } from "vitest";

import { appSiteAssociation, sharePage } from "./links";

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
    const res = sharePage("BCDFG", undefined);
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

  test("the Get the app link appears only when a TestFlight URL is set", async () => {
    const without = await sharePage("BCDFG", undefined).text();
    expect(without).not.toContain("Get the app");
    expect(without).not.toContain("<a ");

    const withLink = await sharePage("BCDFG", TESTFLIGHT).text();
    expect(withLink).toContain(`<a href="${TESTFLIGHT}">Get the app</a>`);
  });

  test("a TestFlight URL that is not https is omitted", async () => {
    for (const url of ["http://testflight.apple.com/join/x", "javascript:alert(1)", "", " https://x.test"]) {
      const html = await sharePage("BCDFG", url).text();
      expect(html, url).not.toContain("Get the app");
    }
  });

  test("the TestFlight URL is HTML-escaped", async () => {
    const html = await sharePage("BCDFG", 'https://x.test/?a=1&b="2"><script>').text();
    expect(html).toContain('href="https://x.test/?a=1&amp;b=&quot;2&quot;&gt;&lt;script&gt;"');
    expect(html).not.toContain("<script");
  });

  test("an invalid code is a plain-text 404 and is never echoed", async () => {
    for (const code of ["bad!", "<script>", "BCDF", "BCDFGH", "bcdfg", "AEIOU", "BCDF0", ""]) {
      const res = sharePage(code, TESTFLIGHT);
      expect(res.status, code).toBe(404);
      expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
      expect(await res.text()).not.toContain(code || "\u0000");
    }
  });
});
