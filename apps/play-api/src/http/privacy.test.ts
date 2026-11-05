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
    // The app's word for a child stays out of the policy's prose (the notice's URL has it).
    expect(html.replace("/privacy/kitten-notice", "")).not.toMatch(/kitten/i);
  });

  test("without CONSENT the policy is as before: no consent section, no phone numbers at all", async () => {
    const html = await privacyPage(false).text();
    expect(html).not.toContain("kitten-notice");
    expect(html).not.toContain("Twilio");
    expect(html).toContain("ad identifiers, phone numbers or messages");
    expect(html).not.toContain("<!--");
    expect(await privacyPage(true).text()).not.toContain("<!--");
  });

  test("says what parental consent adds, and how it ends", async () => {
    const html = await privacyPage().text();
    for (const s of ["six-digit code", "Twilio Verify", "push token", "mobile number", "own device", "Revoke", "turns 13", 'href="/privacy/kitten-notice"']) {
      expect(html).toContain(s);
    }
    // Verify sends only its code: no link to confirm by, and nothing to reply STOP to.
    expect(html).not.toContain("STOP");
    expect(html).not.toContain("second text");
  });
});
