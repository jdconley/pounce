import { describe, expect, test } from "vitest";

import { privacyPage } from "./privacy";

const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

describe("privacyPage", () => {
  test("serves the privacy policy as a static, script-free page", async () => {
    const res = privacyPage();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("public, max-age=300");
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    const html = await res.text();
    expect(html).not.toContain("<script");
    expect(html).not.toMatch(/(?:src)="https?:/);
    expect(html).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">');
  });

  test("names the operator, the contact and what is collected", async () => {
    const html = await privacyPage().text();
    expect(html).toContain("Conley Chaos LLC");
    expect(html).toContain("privacy@conleychaos.com");
    expect(html).toContain("Sign in with Apple");
    expect(html).toContain("time zone");
    expect(html).toContain("120 days");
    expect(html).toContain("90 days");
    expect(html).toContain("delete your account");
  });

  test("carries the COPPA direct notice for parents", async () => {
    const html = await privacyPage().text();
    expect(html).toContain('id="coppa"');
    expect(html).toContain("under 13");
    expect(html).toContain("parent");
    expect(html).toContain("no push notifications");
    expect(html).not.toMatch(/kitten/i);
  });
});
