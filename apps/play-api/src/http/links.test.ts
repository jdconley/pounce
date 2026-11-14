import { createHash } from "node:crypto";

import { describe, expect, test } from "vitest";

import { appSiteAssociation, appStoreId, deadLinkPage, INVITE_CSP, INVITE_SCRIPT, INVITE_SCRIPT_HASH, ogImage, pouncePage, sharePage } from "./links";
import { MEDIA } from "./site-media";

import type { InvitePeek } from "../safety/safety";

const ORIGIN = "https://play.conleychaos.com";

const TESTFLIGHT = "https://testflight.apple.com/join/abc123";
const APP_STORE = "https://apps.apple.com/app/id1234567890";
const NONE = {};
const TF = { testflightUrl: TESTFLIGHT };
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";
const GRANDMA: InvitePeek = { table: "The Midnight Laser Dots", game: "tiles", host: { name: "Grandma", cat: 3 } };
const TOWER: InvitePeek = { table: "Kitchen", game: "cat-tower", host: { name: "Mia", cat: 1 } };
const KITTEN: InvitePeek = { table: null, game: "tiles", host: null };

const meta = (html: string, property: string): string | undefined =>
  new RegExp(`<meta (?:property|name)="${property}" content="([^"]*)">`).exec(html)?.[1];

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

describe("the invite script", () => {
  test("its hash is the one the pages allow, and nothing else runs", () => {
    const hash = `sha256-${createHash("sha256").update(INVITE_SCRIPT).digest("base64")}`;
    expect(INVITE_SCRIPT_HASH).toBe(hash);
    expect(INVITE_CSP).toContain(`script-src '${hash}'`);
    expect(INVITE_CSP).not.toContain("unsafe-eval");
    expect(INVITE_CSP).not.toMatch(/script-src[^;]*unsafe-inline/);
    expect(INVITE_CSP).toContain("default-src 'none'");
  });

  test("copies the button's invite, then goes where the button goes; without a clipboard it is a plain link", () => {
    expect(INVITE_SCRIPT).toContain('getElementById("get")');
    expect(INVITE_SCRIPT).toContain("writeText(b.getAttribute(\"data-invite\"))");
    expect(INVITE_SCRIPT).toContain("location.href=b.href");
    expect(INVITE_SCRIPT).toContain("if(!c||!c.writeText)return;");
    // Failing to copy still goes to the store.
    expect(INVITE_SCRIPT).toMatch(/\.then\(function\(\)\{[^}]*\},go\)/);
  });
});

describe("sharePage: a table that says who invited", () => {
  test("names the person, the game and the table, with the code as the fallback", async () => {
    const res = sharePage("BCDFG", TF, ORIGIN, GRANDMA);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("x-robots-tag")).toBe("noindex");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(res.headers.get("content-security-policy")).toBe(INVITE_CSP);
    const html = await res.text();
    expect(html).toContain("<title>Grandma saved you a seat</title>");
    expect(html).toContain("<h1>Grandma saved you a seat</h1>");
    expect(html).toContain('<p class="game tiles">Tuna Tiles</p>');
    expect(html).toContain('<p class="table">The Midnight Laser Dots</p>');
    expect(html).toContain('<div class="code"><span>Table code</span><strong>BCDFG</strong></div>');
    expect(html).toContain(`<img class="host" src="${MEDIA.invite.cats[3]}"`);
    expect(html).toContain(`<script>${INVITE_SCRIPT}</script>`);
    expect(html).not.toMatch(/(?:src|href)="http:/);
    expect(html).not.toMatch(/\p{Extended_Pictographic}/u);
  });

  test("the one button copies the page's link and opens the store, and says what to do next", async () => {
    const html = await sharePage("BCDFG", TF, ORIGIN, GRANDMA).text();
    expect(html).toContain(
      `<a class="go" id="get" href="${TESTFLIGHT}" data-invite="${ORIGIN}/j/BCDFG" data-copied="Invite copied">Get Pounce</a>\n<p class="next">Then open Pounce and tap Paste.</p>`,
    );
    expect(html.match(/<a /g)).toHaveLength(1);
  });

  test("Messages' preview names the person and the game, on the game's art", async () => {
    const html = await sharePage("BCDFG", NONE, ORIGIN, GRANDMA).text();
    expect(meta(html, "og:title")).toBe("Grandma saved you a seat");
    expect(meta(html, "og:description")).toBe("Tuna Tiles · The Midnight Laser Dots");
    expect(meta(html, "og:site_name")).toBe("Pounce");
    expect(meta(html, "og:url")).toBe(`${ORIGIN}/j/BCDFG`);
    expect(meta(html, "og:image")).toBe(`${ORIGIN}${MEDIA.invite.previews.tiles}`);
    expect(meta(html, "og:image:width")).toBe("1200");
    expect(meta(html, "og:image:height")).toBe("630");
    expect(meta(html, "twitter:card")).toBe("summary_large_image");
    const tower = await sharePage("BCDFG", NONE, ORIGIN, TOWER).text();
    expect(meta(tower, "og:description")).toBe("Cat Tower · Kitchen");
    expect(meta(tower, "og:image")).toBe(`${ORIGIN}${MEDIA.invite.previews["cat-tower"]}`);
    expect(tower).toContain('<p class="game cat-tower">Cat Tower</p>');
  });

  test("names, table names and the origin are escaped everywhere", async () => {
    const peek: InvitePeek = { table: '<b>"x"</b>', game: "tiles", host: { name: "Mia <3", cat: 2 } };
    const html = await sharePage("BCDFG", TF, 'https://x.test"><script>', peek).text();
    expect(html).toContain("Mia &lt;3 saved you a seat");
    expect(html).toContain("&lt;b&gt;&quot;x&quot;&lt;/b&gt;");
    expect(html).not.toContain("Mia <3");
    expect(html).not.toContain("<b>");
    expect(html).toContain('content="https://x.test&quot;&gt;&lt;script&gt;/j/BCDFG"');
    expect(html.match(/<script>/g)).toHaveLength(1);
  });

  test("a game other than Cat Tower says to update an older app; Cat Tower doesn't", async () => {
    expect(await sharePage("BCDFG", TF, ORIGIN, GRANDMA).text()).toContain('<p class="note">Have Pounce? Update it first.</p>');
    expect(await sharePage("BCDFG", TF, ORIGIN, TOWER, true).text()).not.toContain("Update it first");
  });

  test("a kitten's table names nobody and keeps its name, but says the game", async () => {
    const html = await sharePage("BCDFG", TF, ORIGIN, KITTEN).text();
    expect(html).toContain("<h1>Come play Pounce</h1>");
    expect(html).toContain('<p class="game tiles">Tuna Tiles</p>');
    expect(html).not.toContain('class="table"');
    expect(html).not.toContain('class="host"');
    expect(meta(html, "og:description")).toBe("Tuna Tiles");
    expect(meta(html, "og:image")).toBe(`${ORIGIN}${MEDIA.invite.previews.tiles}`);
  });
});

describe("sharePage: a table it can't speak of", () => {
  test("hidden (the address is locked out, or the look failed): the same page for every code, naming nobody", async () => {
    const a = await sharePage("BCDFG", TF, ORIGIN, "hidden").text();
    const b = await sharePage("GFDCB", TF, ORIGIN, "hidden").text();
    expect(a.replaceAll("BCDFG", "GFDCB")).toBe(b);
    expect(a).toContain("<h1>Come play Pounce</h1>");
    expect(a).not.toContain('class="game');
    expect(meta(a, "og:title")).toBe("Come play Pounce");
    expect(meta(a, "og:description")).toBe("Table BCDFG");
    expect(meta(a, "og:image")).toBe(`${ORIGIN}${MEDIA.og.src}`);
    expect(a).toContain("<strong>BCDFG</strong>");
    expect(await sharePage("BCDFG", TF, ORIGIN).text()).toBe(a);
  });

  test("hidden while a newer game is on: the update note, on every code alike", async () => {
    expect(await sharePage("BCDFG", TF, ORIGIN, "hidden", true).text()).toContain("Have Pounce? Update it first.");
    expect(await sharePage("BCDFG", TF, ORIGIN, "hidden", false).text()).not.toContain("Update it first");
  });

  test("gone (no such table, or its game is over) is the expired page", async () => {
    const res = sharePage("BCDFG", TF, ORIGIN, "gone");
    expect(res.status).toBe(404);
    const html = await res.text();
    expect(html).toContain("<h1>This invite has expired</h1>");
    expect(html).not.toContain("BCDFG");
  });

  test("an invalid code is the friendly 404 page and is never echoed", async () => {
    for (const code of ["bad!", "<script>", "BCDF", "BCDFGH", "bcdfg", "AEIOU", "BCDF0", ""]) {
      const res = sharePage(code, TF, ORIGIN, GRANDMA);
      expect(res.status, code).toBe(404);
      expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
      expect(res.headers.get("cache-control")).toBe("no-store");
      expect(res.headers.get("content-security-policy")).toBe(CSP);
      const html = await res.text();
      expect(html).toContain("This invite has expired");
      expect(html).not.toContain("<script");
      if (code) expect(html).not.toContain(code);
    }
  });

  test("without a store link there is no button, only the code", async () => {
    const html = await sharePage("BCDFG", NONE, ORIGIN, GRANDMA).text();
    expect(html).not.toContain("<a ");
    expect(html).not.toContain("tap Paste");
    expect(html).toContain("<strong>BCDFG</strong>");
  });

  test("a store link that is not https is left out", async () => {
    for (const url of ["http://testflight.apple.com/join/x", "javascript:alert(1)", "", " https://x.test"]) {
      const html = await sharePage("BCDFG", { testflightUrl: url }, ORIGIN, GRANDMA).text();
      expect(html, url).not.toContain("Get Pounce");
    }
  });

  test("the store link is escaped", async () => {
    const html = await sharePage("BCDFG", { testflightUrl: 'https://x.test/?a=1&b="2"><script>' }, ORIGIN).text();
    expect(html).toContain('href="https://x.test/?a=1&amp;b=&quot;2&quot;&gt;&lt;script&gt;"');
    expect(html.match(/<script>/g)).toHaveLength(1);
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

  test("the pounce page names the sender and the game, with no caching and no referrer", async () => {
    const token = "A".repeat(22);
    const res = pouncePage({ name: "Mia <3", cat: 2 }, token, TF, ORIGIN);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(res.headers.get("x-robots-tag")).toBe("noindex");
    expect(res.headers.get("content-security-policy")).toBe(INVITE_CSP);
    const html = await res.text();
    expect(html).toContain("<h1>Mia &lt;3 wants to play</h1>");
    expect(html).not.toContain("Mia <3");
    expect(html).toContain('<p class="game cat-tower">Cat Tower</p>');
    expect(html).toContain(`<img class="host" src="${MEDIA.invite.cats[2]}"`);
    expect(meta(html, "og:title")).toBe("Mia &lt;3 wants to play");
    expect(meta(html, "og:description")).toBe("Cat Tower");
    expect(meta(html, "og:url")).toBe(`${ORIGIN}/p/${token}`);
    expect(meta(html, "og:image")).toBe(`${ORIGIN}${MEDIA.invite.previews["cat-tower"]}`);
    expect(html).toContain(`id="get" href="${TESTFLIGHT}" data-invite="${ORIGIN}/p/${token}"`);
    expect(html).toContain("Then open Pounce and tap Paste.");
    expect(html).not.toContain('class="code"');
    expect(html).not.toMatch(/\p{Extended_Pictographic}/u);
  });

  test("a pounce for another game names that game", async () => {
    const html = await pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), TF, ORIGIN, "tiles").text();
    expect(html).toContain('<p class="game tiles">Tuna Tiles</p>');
    expect(meta(html, "og:image")).toBe(`${ORIGIN}${MEDIA.invite.previews.tiles}`);
  });

  test("an unknown, used or expired link is a friendly 404 that says it expired and nothing else", async () => {
    const token = "A".repeat(22);
    const res = pouncePage(null, token, TF, ORIGIN);
    expect(res.status).toBe(404);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("x-robots-tag")).toBe("noindex");
    const html = await res.text();
    expect(html).toContain("<h1>This invite has expired</h1>");
    expect(html).toContain("Ask for a new link.");
    expect(html).toContain(`<a class="go" href="${TESTFLIGHT}">Get Pounce</a>`);
    expect(html).not.toContain(token);
    expect(html).not.toContain("<script");
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

  test("with APP_STORE_URL: the banner carries the page's own link, and the button goes to the App Store", async () => {
    const install = { appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT };
    const room = await sharePage("BCDFG", install, ORIGIN, GRANDMA).text();
    expect(room).toContain(`<meta name="apple-itunes-app" content="app-id=1234567890, app-argument=${ORIGIN}/j/BCDFG">`);
    expect(room).toContain(`<a class="go" id="get" href="${APP_STORE}"`);
    expect(room).not.toContain(TESTFLIGHT);
    expect(room).not.toContain("beta");
    const token = "B".repeat(22);
    const p = await pouncePage({ name: "Mia", cat: 2 }, token, install, ORIGIN).text();
    expect(p).toContain(`app-argument=${ORIGIN}/p/${token}">`);
    expect(await deadLinkPage(install).text()).toContain(`<a class="go" href="${APP_STORE}">Get Pounce</a>`);
  });

  test("without it (as now, until the App Store id is known): no banner", async () => {
    for (const install of [NONE, TF, { appStoreUrl: "" }]) {
      const html = await sharePage("BCDFG", install, ORIGIN, GRANDMA).text();
      expect(html).not.toContain("apple-itunes-app");
    }
  });
});

describe("the beta note under the button", () => {
  const NOTE = '<p class="note">Pounce is in beta. This opens TestFlight.</p>';

  test("a TestFlight link says it is a beta, on the room, pounce and expired pages", async () => {
    for (const res of [sharePage("BCDFG", TF, ORIGIN, GRANDMA), pouncePage({ name: "Mia", cat: 2 }, "A".repeat(22), TF, ORIGIN), deadLinkPage(TF)]) {
      expect(await res.text()).toContain(NOTE);
    }
  });

  test("an App Store link, or no link, has no such note", async () => {
    for (const install of [NONE, { appStoreUrl: APP_STORE, testflightUrl: TESTFLIGHT }]) {
      expect(await sharePage("BCDFG", install, ORIGIN, GRANDMA).text()).not.toContain("beta");
      expect(await deadLinkPage(install).text()).not.toContain("beta");
    }
  });
});

describe("the invite art", () => {
  test("every cat has a face, and every game a preview", () => {
    expect(MEDIA.invite.cats).toHaveLength(8);
    for (const cat of MEDIA.invite.cats) expect(cat).toMatch(/^\/static\/inviter-\d\.[a-f0-9]{10}\.webp$/);
    for (const game of ["cat-tower", "tiles"] as const) {
      expect(MEDIA.invite.previews[game]).toMatch(new RegExp(`^/static/invite-${game}\\.[a-f0-9]{10}\\.jpg$`));
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
