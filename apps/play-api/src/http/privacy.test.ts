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

describe("the Daily Dish in the privacy policy", () => {
  test("says nothing of daily puzzles while DAILY is off", async () => {
    for (const html of [await privacyPage().text(), await privacyPage(false).text(), await privacyPage(true, false).text()]) {
      expect(html).not.toMatch(/daily puzzle/i);
      expect(html).not.toContain("<!--");
    }
  });

  test("with DAILY on: what's kept, that only connections and a TV linked to your board see results, and 120 days", async () => {
    for (const consent of [true, false]) {
      const html = await privacyPage(consent, true).text();
      expect(html).toContain("<strong>Daily puzzles:</strong>");
      expect(html).toContain("go only to the people you have a streak with, and a TV you linked to your board");
      expect(html).toContain("Daily puzzle results: 120 days.");
      expect(html).toContain("and daily puzzle results;");
      expect(html).not.toContain("<!--");
    }
  });
});

describe("Purrtrait in the privacy policy (design §8.2)", () => {
  const text = (html: string) => html.replace(/<[^>]+>/g, "");
  const KEPT = "Drawings in Purrtrait go from the drawer's phone to the table's TV through our server, which keeps them only until the turn ends. They are never saved, shown on another phone, or shared.";
  const CHILD = "A child's drawings show only on the table's TV and are gone when the turn ends.";

  test("says nothing of drawings while Purrtrait tables can't be dealt", async () => {
    for (const html of [await privacyPage().text(), await privacyPage(false).text(), await privacyPage(true, true).text()]) {
      expect(html).not.toMatch(/purrtrait|\bdrawings?\b/i);
      expect(html).not.toContain("<!--");
    }
  });

  test("with Purrtrait on: what happens to a drawing, under what we keep and in the notice for parents", async () => {
    for (const consent of [true, false]) {
      for (const daily of [true, false]) {
        const html = await privacyPage(consent, daily, true).text();
        expect(html).not.toContain("<!--");
        const kept = html.slice(html.indexOf("<h2>What we keep</h2>"), html.indexOf('<h2 id="web">'));
        expect(text(kept)).toContain(KEPT);
        const coppa = html.slice(html.indexOf('<section id="coppa">'), html.indexOf("</section>"));
        expect(text(coppa)).toContain(CHILD);
        // Each said once, and nothing else changes.
        expect(text(html).split(KEPT)).toHaveLength(2);
        expect(text(html).split(CHILD)).toHaveLength(2);
        const off = await privacyPage(consent, daily, false).text();
        expect(html.replace(/<li><strong>Drawings in Purrtrait<\/strong>[^\n]*\n/, "").replace(`<p>${CHILD}</p>\n`, "")).toBe(off);
      }
    }
  });
});
