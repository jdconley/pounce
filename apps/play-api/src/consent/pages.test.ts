import { describe, expect, test } from "vitest";

import { apnsBody, category } from "../notify/payload";

import { noticePage, plusPush } from "./pages";

const headers = (res: Response) => ({
  type: res.headers.get("content-type"),
  cache: res.headers.get("cache-control"),
  csp: res.headers.get("content-security-policy"),
});

describe("the direct notice (16 CFR 312.4(c))", () => {
  test("a static, script-free page", async () => {
    const res = noticePage();
    expect(res.status).toBe(200);
    expect(headers(res)).toEqual({
      type: "text/html; charset=utf-8",
      cache: "public, max-age=300",
      csp: "default-src 'none'; style-src 'unsafe-inline'; img-src data:",
    });
    const html = await res.text();
    expect(html).not.toContain("<script");
    expect(html).not.toContain("<form");
    expect(html).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">');
  });

  test("says who we are, why we have the number, what we'd collect, that it isn't shared, how to consent and revoke, and links the policy", async () => {
    const html = await noticePage().text();
    for (const s of [
      "Conley Chaos LLC",
      "privacy@conleychaos.com",
      "mobile number",
      "six-digit code",
      "within 30 minutes of the last code",
      "notification on your own device",
      "Revoke",
      "push token",
      "people the child plays with",
      "never sell or share",
      "Twilio Verify",
      "Communication Limits",
      'href="/privacy"',
    ]) {
      expect(html).toContain(s);
    }
    // No link of ours goes by text, so there is nothing to reply STOP to.
    expect(html).not.toContain("STOP");
    expect(html).not.toContain("link in our text");
  });
});

describe("the confirmation push (the plus, D6)", () => {
  test("names the kitten, carries its public id and the Revoke category, and opens the Kittens panel", () => {
    const o = plusPush("k_demoMochiAAAAAAAAAAAAAA", "Mochi");
    expect(o).toMatchObject({ kind: "consent", title: "Mochi", thread: "consent", collapse: "consent:k_demoMochiAAAAAAAAAAAAAA", data: { kitten: "k_demoMochiAAAAAAAAAAAAAA" } });
    expect(o.code).toBeUndefined();
    expect(o.body).toContain("You allowed notifications");
    expect(o.body).toContain("Revoke");
    expect(category(o.kind)).toBe("CONSENT");
    const body = apnsBody(o, "active", 0);
    expect(body).toMatchObject({ kind: "consent", kitten: "k_demoMochiAAAAAAAAAAAAAA", aps: { category: "CONSENT", "interruption-level": "active", sound: "default" } });
  });
});
