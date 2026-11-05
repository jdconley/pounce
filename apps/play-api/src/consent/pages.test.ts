import { describe, expect, test } from "vitest";

import { firstText, noticePage, outcomePage, secondText, tokenPage } from "./pages";

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
      csp: "default-src 'none'; style-src 'unsafe-inline'; img-src data:; form-action 'self'",
    });
    const html = await res.text();
    expect(html).not.toContain("<script");
    expect(html).toContain('<meta name="viewport" content="width=device-width, initial-scale=1">');
  });

  test("says who we are, why we have the number, what we'd collect, that it isn't shared, how to consent and revoke, and links the policy", async () => {
    const html = await noticePage().text();
    for (const s of [
      "Conley Chaos LLC",
      "privacy@conleychaos.com",
      "mobile number",
      "within 7 days",
      "push token",
      "people the child plays with",
      "never sell or share",
      "Twilio",
      "Reply STOP",
      "Communication Limits",
      'href="/privacy"',
    ]) {
      expect(html).toContain(s);
    }
  });
});

describe("the confirm and revoke pages", () => {
  test("confirm posts to its own URL, and escapes the name", async () => {
    const res = tokenPage("confirm", { name: `<b>"Mochi"</b>` }, "tok_abc");
    expect(headers(res).cache).toBe("no-store");
    const html = await res.text();
    expect(html).toContain('<form method="post" action="/consent/tok_abc">');
    expect(html).toContain("&lt;b&gt;&quot;Mochi&quot;&lt;/b&gt;");
    expect(html).not.toContain("<b>");
    expect(html).toContain('href="/privacy/kitten-notice"');
  });

  test("revoke has its own wording and button", async () => {
    const html = await tokenPage("revoke", { name: "Mochi's" }, "a/b").text();
    expect(html).toContain("Turn off notifications for Mochi&#39;s?");
    expect(html).toContain('action="/consent/a%2Fb"');
    expect(html).toContain('class="revoke"');
  });

  test("outcomes; a used link is a 404 that changes nothing", async () => {
    expect(await outcomePage("confirmed").text()).toContain("Notifications are on");
    expect(await outcomePage("revoked").text()).toContain("deleted your number");
    const gone = outcomePage("gone");
    expect(gone.status).toBe(404);
    expect(await gone.text()).toContain("Nothing changed");
  });
});

describe("the texts", () => {
  test("carry the link and STOP, and nothing about the child", () => {
    const one = firstText("https://play.conleychaos.com/consent/t1");
    expect(one).toContain("https://play.conleychaos.com/consent/t1");
    expect(one).toContain("STOP");
    const two = secondText("https://play.conleychaos.com/consent/t2");
    expect(two).toContain("you allowed notifications");
    expect(two).toContain("revoke");
    expect(two).toContain("STOP");
    // Short enough for two SMS segments with a link.
    expect(one.length).toBeLessThan(300);
    expect(two.length).toBeLessThan(200);
  });
});
