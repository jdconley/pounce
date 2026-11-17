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
  head: '<meta name="description" content="Help for Pounce: Family Games. Start a table and add players, play the House Cat bot, learn Cat Tower and Tuna Tiles, play in a browser or on a TV, set reminders, allow turn alerts for a child, report or block a player, and delete your data.">\n',
  current: "support",
  body: `<h1>Pounce: Family Games help</h1>
<p>Pounce has two family games, Cat Tower and Tuna Tiles. Play them in the iPhone and iPad app, or in any web browser at <a href="/play/">play.conleychaos.com/play</a>. Everyone sits at the same tables. If something isn't covered here, write to us at the bottom of the page.</p>

<section>
<h2>Start a table and add players</h2>
<ul>
<li>On Home, tap Play on Cat Tower or Tuna Tiles.</li>
<li>In the lobby, tap Add a player. Same room shows a QR code to scan. Far away sends a link. This phone lets someone play on your phone, passing it between turns. In a browser it says This device.</li>
<li>Nobody needs an account to play. A link opens your table in Pounce. Without the app, its page offers Play in your browser, or the App Store. After installing, open Pounce and tap Paste to sit at the same table.</li>
<li>Tap Start when everyone is seated. Play live together, or take a turn when you have a minute. The game waits for you.</li>
</ul>
</section>

<section>
<h2>Play against the House Cat bot</h2>
<ul>
<li>Fastest: on Home, tap Practice. A game against the House Cat starts right away.</li>
<li>At any new table, a House Cat holds a seat so you can start at once. To add more, tap Add a player, then House Cat.</li>
<li>Tap Start. The bot plays its own turns, so one device is enough.</li>
</ul>
</section>

<section>
<h2>How to play Cat Tower</h2>
<p>Cards, for two to six players. The app has a How to play video too.</p>
<ul>
<li>Climb all ten levels of the tower. Each level asks for its own sets and runs.</li>
<li>Start your turn by drawing a card. Yarn is wild and fills any gap.</li>
<li>When you have your level, lay it down. Then you can add cards to any group on the table.</li>
<li>End your turn with one discard. A Cucumber makes the next cat skip a turn.</li>
<li>When someone runs out of cards, the round ends. Cards left in your hand cost points. Made your level? Your cat climbs a shelf.</li>
<li>Finish level 10 first to win.</li>
</ul>
</section>

<section>
<h2>How to play Tuna Tiles</h2>
<p>Tiles, for two to four players. The app has a How to play video too.</p>
<ul>
<li>Empty your stash onto the rug. The first player to do it wins.</li>
<li>Lay tiles in matches (one number, different toys) or rows (one toy, counting up).</li>
<li>Your first play must add up to 30. After that, add to any set on the rug.</li>
<li>Move anything on the rug, as long as every set is good when you tap Play.</li>
<li>Nothing to play? Tap Draw.</li>
<li>Yarn is wild. You can swap the real toy in for a yarn on the rug, then use that yarn in another set.</li>
</ul>
</section>

<section>
<h2>Play in a web browser</h2>
<p>Go to <a href="/play/">play.conleychaos.com/play</a> on an Android phone, a laptop or a tablet. It plays both games at the same tables as the iPhone app. To keep it like an app, use your browser's Install or Add to Home Screen option, or Install Pounce in its Settings where your browser offers it. Turn on Turn alerts in Settings to hear when it's your move.</p>
</section>

<section>
<h2>Put the table on a TV</h2>
<ul>
<li>On the big screen, open <a href="/play/tv">play.conleychaos.com/play/tv</a>. A laptop plugged into the TV, a smart TV's browser or a cast browser tab all work.</li>
<li>Pick a game on the TV. Everyone scans the code on the TV with their phone to join, and any phone can press Start.</li>
<li>Already at a table in your browser? Scan the code on the TV's start screen to put that table on the TV.</li>
<li>In a phone's browser, you see just your own cards. Tap Table to see the whole board, and Cards to go back. The iPhone app shows the whole table.</li>
</ul>
</section>

<section>
<h2>Turn reminders</h2>
<p>On iPhone and iPad, Pounce can nudge you when it is your move, and send one last reminder before bed. Allow notifications when the app asks, then choose what you want under Reminders in Settings (the gear on Home). Reminders pick their own time of day. You can turn them off in the app, or in iOS Settings under Notifications, at any time.</p>
</section>

<section>
<h2>Turn alerts for a child</h2>
<p>A child under 13 plays without notifications from our server. A parent can allow turn alerts on the child's own device. You need the child's device, your own device signed in with Apple, and a phone that can receive a text.</p>
<ul>
<li>On the child's device, open Settings. It shows a six-digit code, with "Show this code to a grown-up".</li>
<li>On your device, open Settings, then Kids' alerts under Family. Tap Add a child and type the six digits.</li>
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
<p>Open Settings (the gear on Home) and tap Delete my data, or the trash can if you are signed in. In a browser, open Settings and tap Delete my data. This deletes your player from our server with its games, streaks, connections, requests to play, invite links and settings. When you are signed in with Apple it covers your account on every device. For a child's device, it also deletes the parent's consent record and phone number. Details are in the <a href="/privacy">privacy policy</a>.</p>
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

> Pounce is a free family games app made by Conley Chaos LLC. It has two games: Cat Tower, a rummy-style card game for two to six players where your cats climb a ten-shelf tower, and Tuna Tiles, tile rummy for two to four players where yarn is wild. It plays in the iPhone and iPad app and in any web browser, and players on each sit at the same tables.

Play live together, or take turns over days. The game waits for everyone. Add players in the same room with a QR code, from far away with a link, or by passing one phone. A House Cat bot can hold a seat. To put the table on a TV, open ${origin}/play/tv on any big screen with a browser. A phone in the browser then shows just its own hand. On iPhone, Pounce has turn reminders, a Live Activity and a streak widget.

Pounce is free. It has no chat, no ads, no tracking and no third-party analytics, and nobody needs an account to play. Children under 13 get a simpler, limited version, and ${alerts}.

## Pages

- [Home](${origin}/): what Pounce is, screenshots, and how to start
- [Play in your browser](${origin}/play/): the web player, for Android phones, computers and tablets
- [Support](${origin}/support): how to start a table, add players, play each game, play in a browser or on a TV, set reminders, report or block a player, and delete your data
- [Privacy policy](${origin}/privacy): what the app and its server keep, for how long, and the notice for parents
- [Get the app](${origin}/get): goes to the App Store listing, or to the TestFlight beta before the App Store release
`;
  return new Response(text, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": CACHE } });
}

const escapeXml = (text: string): string => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** The public pages: the landing page, the web player, support and the privacy policy. */
export function sitemapXml(origin: string): Response {
  const urls = ["/", "/play/", "/support", "/privacy"].map((path) => `<url><loc>${escapeXml(origin)}${path}</loc></url>`).join("\n");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`, {
    headers: { "content-type": "application/xml; charset=utf-8", "cache-control": CACHE },
  });
}
