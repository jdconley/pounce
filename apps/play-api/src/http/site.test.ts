import { describe, expect, test } from "vitest";

import { homePage, supportPage } from "./site";

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

describe("homePage", () => {
  test("names the app and links to support and privacy, with no install link by default", async () => {
    const res = homePage();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    const html = await res.text();
    expect(html).toContain("Pounce: Family Games");
    expect(html).toContain('href="/support"');
    expect(html).toContain('href="/privacy"');
    expect(html).not.toContain("Get the app");
    expect(await homePage("").text()).not.toContain("Get the app");
  });

  test("shows an escaped install link when the App Store url is set", async () => {
    const html = await homePage('https://apps.apple.com/app/id1?a=1&b="2"').text();
    expect(html).toContain('<a href="https://apps.apple.com/app/id1?a=1&amp;b=&quot;2&quot;">Get the app</a>');
  });
});
