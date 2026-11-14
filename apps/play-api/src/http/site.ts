/**
 * The public site besides the landing page (home.ts): the help page at `/support` (the App
 * Store's Support URL), the short install address `/get`, and robots.txt, the sitemap and llms.txt.
 * Keep the support steps in step with docs/app-review-notes.md.
 */
import { CACHE, CSP, docPage } from "./layout";
import { https } from "./links";

import type { Install } from "./links";

export { homePage } from "./home";

const HEADERS = { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP };
const CONTACT = "privacy@conleychaos.com";

const SUPPORT = docPage({
  title: "Pounce: Family Games support",
  head: '<meta name="description" content="Help for Pounce: Family Games. Start a game and invite people, play against the House Cat bot, set turn reminders, allow turn alerts for a child, report or block a player, and delete your data.">\n',
  current: "support",
  body: `<h1>Pounce: Family Games help</h1>
<p>Pounce is a card game for couples and families. Here is how things work. If something isn't covered, write to us at the bottom of the page.</p>

<section>
<h2>Start a game and invite someone</h2>
<ul>
<li>On Home, tap Create to start a table.</li>
<li>Invite people with the share sheet or a QR code. They open the link, and Pounce takes them to your table. Nobody needs an account to play.</li>
<li>Tap the start button when everyone is seated. You each play a turn whenever you have a minute; the game waits for you.</li>
</ul>
</section>

<section>
<h2>Play alone against the House Cat bot</h2>
<ul>
<li>On Home, tap Create.</li>
<li>In the lobby, tap an empty seat and choose Add a bot. A House Cat bot sits there. Add more bots the same way if you like.</li>
<li>Tap the start button. The bot plays its own turns, and you only need one device.</li>
</ul>
</section>

<section>
<h2>Turn reminders</h2>
<p>Pounce can nudge you when it is your move, and send one last reminder before bed. Allow notifications when the app asks, then choose what you want under Reminders in Settings (the gear on Home). Reminders pick their own time of day. You can turn them off in the app, or in iOS Settings under Notifications, at any time.</p>
</section>

<section>
<h2>Turn alerts for a child</h2>
<p>A child under 13 plays without notifications from our server. A parent can allow turn alerts on the child's own device. You need the child's device, your own device signed in with Apple, and a phone that can receive a text.</p>
<ul>
<li>On the child's device, open Settings. It shows a six-digit code, with "Show this code to a grown-up".</li>
<li>On your device, open Settings, tap Add a child, then tap Add a child again and type the six digits.</li>
<li>Tap Next step, read the notice about what we collect, and enter your mobile number.</li>
<li>A text brings a six-digit code. Type it into Pounce, and turn alerts are on for that child.</li>
<li>A day or two later your own devices get a confirmation notification with a Revoke button.</li>
</ul>
<p>You can turn alerts off or remove the child at any time from the same panel. Your number is used only for this and is deleted when consent ends. See the <a href="/privacy#coppa">notice for parents</a>.</p>
</section>

<section>
<h2>Report or block a player</h2>
<ul>
<li>Open the player's card at your table.</li>
<li>To report, tap Report and pick a reason: Rude name, Bothering me, or Something else. We look at every report.</li>
<li>To block, tap Block and confirm. They can't join tables you start, and their pounces and nudges won't reach you. Tap Unblock on the same card to undo it.</li>
</ul>
</section>

<section>
<h2>Delete your account</h2>
<p>Open Settings (the gear on Home) and tap Delete my data, or the trash can if you are signed in. This deletes your player from our server with its games, streaks, connections, requests to play, invite links and settings. When you are signed in with Apple it covers your account on every device. For a child's device, it also deletes the parent's consent record and phone number. Details are in the <a href="/privacy">privacy policy</a>.</p>
</section>

<section>
<h2>Contact us</h2>
<p>Write to <a href="mailto:${CONTACT}">${CONTACT}</a>. Pounce is made by Conley Chaos LLC.</p>
</section>`,
});

/** The help page; public, static, no scripts. */
export function supportPage(): Response {
  return new Response(SUPPORT, { headers: HEADERS });
}

/**
 * `/get`: the one install address other sites and the landing page's QR code point at. It goes
 * to the App Store when `APP_STORE_URL` is set, else to the TestFlight beta, else back home.
 * Never cached, so a change to either setting takes effect at once.
 */
export function getRedirect(install: Install, origin: string): Response {
  const location = https(install.appStoreUrl) ?? https(install.testflightUrl) ?? `${origin}/`;
  return new Response(null, { status: 302, headers: { location, "cache-control": "no-store" } });
}

/** robots.txt: the pages are public; the API is not for crawlers. Invite links stay fetchable so their previews work. */
export function robotsTxt(origin: string): Response {
  return new Response(`User-agent: *\nAllow: /\nDisallow: /v1/\n\nSitemap: ${origin}/sitemap.xml\n`, {
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": CACHE },
  });
}

/**
 * llms.txt (llmstxt.org): a plain summary for assistants asked what Pounce is. It says only what
 * the landing page and the privacy policy say.
 */
export function llmsTxt(origin: string, consent = true): Response {
  const alerts = consent ? "a parent decides whether they get notifications" : "they get no push notifications from our server";
  const text = `# Pounce: Family Games

> Pounce is a card game app for couples and families, for iPhone and iPad, made by Conley Chaos LLC. Its first game is Cat Tower, a rummy-style, turn-based card game for two to six players: take your turn when you have a minute, and the game waits for everyone else.

Pounce is free. It has no chat, no ads, no tracking and no third-party analytics, and nobody needs an account to play. Children under 13 get a simpler, limited version, and ${alerts}.

## Pages

- [Home](${origin}/): what Pounce is, screenshots, and how to install it
- [Support](${origin}/support): how to start a game, invite people, set reminders, report or block a player, and delete your data
- [Privacy policy](${origin}/privacy): what the app and its server keep, for how long, and the notice for parents
- [Get the app](${origin}/get): goes to the App Store listing, or to the TestFlight beta before the App Store release
`;
  return new Response(text, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": CACHE } });
}

const escapeXml = (text: string): string => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** The three public pages. */
export function sitemapXml(origin: string): Response {
  const urls = ["/", "/support", "/privacy"].map((path) => `<url><loc>${escapeXml(origin)}${path}</loc></url>`).join("\n");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`, {
    headers: { "content-type": "application/xml; charset=utf-8", "cache-control": CACHE },
  });
}
