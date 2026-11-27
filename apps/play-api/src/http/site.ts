/**
 * The public site besides the landing page (home.ts): the help page at `/support` (the App
 * Store's Support URL), the short install address `/get`, and robots.txt, the sitemap and llms.txt.
 * Keep the support steps in step with docs/app-review-notes.md.
 */
import { and, browserGames } from "./home";
import { CACHE, CSP, docPage } from "./layout";
import { https, PURRTRAIT_SINCE, TUMBLE_SINCE } from "./links";

import type { Install } from "./links";

export { homePage } from "./home";

const HEADERS = { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP };
const CONTACT = "privacy@conleychaos.com";

/** The help page with the browser-only games that are on named in its lists. Its marked parts are cut by `part`. */
const supportHtml = (newer: readonly string[]): string =>
  docPage({
    title: "Pounce: Family Games support",
    head: `<meta name="description" content="Help for Pounce: Family Games. Start a table and add players, play the House Cat bot, learn ${and(["Cat Tower", "Tuna Tiles", ...newer])}<!--daily-->, play the Daily Dish<!--/daily-->, play in a browser or on a TV, set reminders, allow turn alerts for a child, report or block a player, and delete your data.">\n`,
    current: "support",
    body: `<h1>Pounce: Family Games help</h1>
<p>Pounce has family games: Cat Tower and Tuna Tiles${newer.length ? `, and ${and(newer)} in the browser` : ""}. Play them in the iPhone and iPad app, or in any web browser at <a href="/play/">play.conleychaos.com/play</a>. Everyone sits at the same tables. If something isn't covered here, write to us at the bottom of the page.</p>

<section>
<h2>Start a table and add players</h2>
<ul>
<li>On Home, tap Play on a game.</li>
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

<!--birdwatch--><section>
<h2>How to play Birdwatch</h2>
<p>Cards, for four to six players in teams. Play it in your browser at <a href="/play/">play.conleychaos.com/play</a>. It's coming to the iPhone app.</p>
<ul>
<li>Pick the rules in the lobby. Official leaves out the 1s. In Tucker and Friesen, 1s are the highest card of their suit. In Friesen, the Bird follows suit like any other trump.</li>
<li>With four players, two teams of two sit across from each other. With six, three teams of two. With five, the bid winner calls a card, and whoever holds it is their secret partner for the hand. Everyone finds out when that card is played.</li>
<li>Bid on how many points your side will take, or pass. The highest bid wins the hand.</li>
<li>The bid winner takes the feeder's extra cards, puts back the same number, and names trump.</li>
<li>Follow the suit that was led if you can. The highest trump takes the trick, or else the highest card of the suit led. The Bird is the top trump.</li>
<li>Points come from the 5s, 10s and 14s, the Bird, and in Tucker and Friesen the 1s. Make your bid and your side scores its points. Miss it and your side loses the bid.</li>
<li>Official games go to 300, Tucker and Friesen to 500. House Cats fill empty seats, and take over for anyone who leaves.</li>
</ul>
</section>

<!--/birdwatch--><!--tumble--><section>
<h2>How to play Toy Tumble</h2>
<p>Falling toys, for two to six players, all at the same time. Each player plays on their own phone or computer, and a TV can show every box. Play it in your browser at <a href="/play/">play.conleychaos.com/play</a>. It's coming to the iPhone app in ${TUMBLE_SINCE}.</p>
<ul>
<li>Toys fall into your box one at a time. Drag to move one, tap to turn it, and flick down to drop it. On a keyboard, use the arrow keys and the space bar.</li>
<li>Fill a row from side to side and it clears. Clear two or more at once to send hairballs to everyone else.</li>
<li>Hairballs wait beside your box for two seconds before they land. Clear rows in time to block them.</li>
<li>Each row you clear puts a trick in your box. Clear the row it sits on to pocket it. Tap a trick, then a box, to use it on anyone, yourself included.</li>
<li>Some tricks hurt, like Hairball, Paw Swipe and Catnip. Some save you, like Scoop, Settle, Nap and Bath. Swap trades boxes with someone. A box near the top gets Swap, Bath and Scoop more often.</li>
<li>When your toys reach the top, you're out for the round. The last box left wins it. Win three rounds to take the game.</li>
<li>The host can seat House Cats at Easy or Quick. Each person needs their own device.</li>
</ul>
</section>

<!--/tumble--><!--purrtrait--><section>
<h2>How to play Purrtrait</h2>
<p>Draw and guess, for two to ten players in one room. It needs a TV or a big screen everyone can see. Start it on the TV page at <a href="/play/tv">play.conleychaos.com/play/tv</a>. It's coming to the iPhone and Apple TV app in ${PURRTRAIT_SINCE}.</p>
<ul>
<li>On the big screen, open the TV page and pick Purrtrait. Each player scans the code on the TV with their own phone, or taps Join and types the code under it. The code changes every 30 seconds, so join from the room.</li>
<li>Pick a timer in the lobby: 45, 60 or 90 seconds a turn. House Cats don't play it. Tap Start once two people are in.</li>
<li>On your turn, your phone shows two words. Pick one: the Easy word scores 1 point, the Tricky word 2.</li>
<li>Draw it on your phone. The TV shows your lines as you draw, with a hint such as Animal or Food. No letters or numbers, and no talking.</li>
<li>Everyone else calls out guesses. Tap Got it, then the player who said it first, and you both score. The turn also ends when the time runs out or you tap Give up.</li>
<li>Everyone draws twice. The highest score wins.</li>
<li>Drawings show only on the TV and are gone when the turn ends. The host can remove a player from the table.</li>
</ul>
</section>

<!--/purrtrait--><!--daily--><section>
<h2>The Daily Dish</h2>
<p>Four new puzzles every day, the same for the whole family. In the iPhone and iPad app they're on Home. In a browser, go to <a href="/play/daily">play.conleychaos.com/play/daily</a>, or tap Open the Dish on Home there.</p>
<ul>
<li>Sniff: find the five-letter word in six tries. Each guess shows which letters are in the word, and which are in the right spot.</li>
<li>Nine Lives: fill the grid so every row, column and box has 1 to 9 once.</li>
<li>Cat Nap: put one cat in each row, column and patch. No two cats touch, not even at a corner.</li>
<li>Box Fort: drag each set of pieces onto the rug. A full row or column clears and scores. It ends when nothing fits.</li>
<li>One try a day at each puzzle. The clock keeps running if you leave. A hint in Nine Lives or Cat Nap adds 30 seconds.</li>
<li>Today's board shows how you and the people you have a streak with did. Tap On TV to put it on a TV showing <a href="/play/tv">play.conleychaos.com/play/tv</a>.</li>
<li>New puzzles come out at 4 in the morning where you are. Monday's are the easiest.</li>
</ul>
</section>

<!--/daily--><section>
<h2>Play in a web browser</h2>
<p>Go to <a href="/play/">play.conleychaos.com/play</a> on an Android phone, a laptop or a tablet. It plays Cat Tower and Tuna Tiles at the same tables as the iPhone app${newer.length ? `, and ${and(newer)} too` : ""}. To keep it like an app, use your browser's Install or Add to Home Screen option, or Install Pounce in its Settings where your browser offers it. Turn on Turn alerts in Settings to hear when it's your move.</p>
</section>

<section>
<h2>Put the table on a TV</h2>
<ul>
<li>On the big screen, open <a href="/play/tv">play.conleychaos.com/play/tv</a>. A laptop plugged into the TV, a smart TV's browser or a cast browser tab all work.</li>
<li>Pick a game on the TV. Everyone scans the code on the TV with their phone to join, and any phone can press Start.</li>
<li>Already at a table? Tap Show on TV, then scan the code on the TV's start screen or type it. That table moves to the TV.</li>
<li>Your phone shows just your own cards, in the app or the browser. Tap Table to see the whole board, and Cards to go back.</li>
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

/** Keeps a marked part of the help page (`<!--tag-->...<!--/tag-->`) without its marks, or drops it. */
const part = (html: string, tag: string, on: boolean): string =>
  on ? html.replace(new RegExp(`<!--/?${tag}-->`, "g"), "") : html.replace(new RegExp(`<!--${tag}-->[\\s\\S]*?<!--/${tag}-->`, "g"), "");

const BOTH = [false, true] as const;

/**
 * With the Daily Dish (`DAILY` on) the help page explains it; off, nothing of it, as the privacy
 * policy does. Birdwatch and Toy Tumble likewise follow `GAMES`, and Purrtrait whether its tables
 * can be dealt (`GAMES` and `TV`).
 */
const SUPPORT: Record<string, string> = Object.fromEntries(
  BOTH.flatMap((daily) =>
    BOTH.flatMap((birdwatch) =>
      BOTH.flatMap((tumble) =>
        BOTH.map((purrtrait) => {
          let html = supportHtml(browserGames(birdwatch, tumble, purrtrait));
          for (const [tag, on] of [["daily", daily], ["birdwatch", birdwatch], ["tumble", tumble], ["purrtrait", purrtrait]] as const) html = part(html, tag, on);
          return [`${daily}/${birdwatch}/${tumble}/${purrtrait}`, html];
        }),
      ),
    ),
  ),
);

/** The help page; public, static, no scripts. */
export function supportPage(daily = false, birdwatch = false, tumble = false, purrtrait = false): Response {
  return new Response(SUPPORT[`${daily}/${birdwatch}/${tumble}/${purrtrait}`], { headers: HEADERS });
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
export function llmsTxt(origin: string, consent = true, daily = false, birdwatch = false, tumble = false, purrtrait = false): Response {
  const dish = daily
    ? `\n\nThe Daily Dish is four new puzzles every day, the same for the whole family: Sniff (find a five-letter word in six tries), Nine Lives (a number grid), Cat Nap (one cat in each row, column and patch, no two touching) and Box Fort (drag block pieces onto a rug and clear lines). A family board shows how everyone you play with did today, and a TV can show it. The server checks every move and works out every result. The puzzles play in the iPhone and iPad app and in the browser at ${origin}/play/daily.`
    : "";
  const kinds = [
    "Cat Tower, a rummy-style card game for two to six players where your cats climb a ten-shelf tower",
    "Tuna Tiles, tile rummy for two to four players where yarn is wild",
    ...(birdwatch ? ["Birdwatch, a trick-taking card game for four to six players in teams, with bidding, trump and a top card called the Bird"] : []),
    ...(tumble ? ["Toy Tumble, a real-time game for two to six players where everyone plays at once: toys fall into each player's box, clearing rows sends hairballs to everyone else, tricks hit a player or save you, and a TV shows every box"] : []),
    ...(purrtrait
      ? ["Purrtrait, a draw-and-guess game for two to ten players in one room: one player draws a word on their phone, the TV shows the drawing as it is drawn, and everyone else guesses out loud"]
      : []),
  ];
  const count = ["two", "three", "four", "five"][kinds.length - 2] ?? "two";
  const list = kinds.length === 2 ? `${kinds[0]}, and ${kinds[1]}` : `${kinds.slice(0, -1).join("; ")}; and ${kinds.at(-1) ?? ""}`;
  const where = [
    ...(birdwatch ? ["Birdwatch plays in the browser today and is coming to the iPhone app."] : []),
    ...(tumble ? [`Toy Tumble plays in the browser and on the web TV page today, and is coming to the iPhone app in ${TUMBLE_SINCE}.`] : []),
    ...(purrtrait
      ? [
          `Purrtrait needs a TV or a big screen in the same room: it starts on the web TV page at ${origin}/play/tv, and players join from the code on the TV with a phone's browser. It is coming to the iPhone and Apple TV app in ${PURRTRAIT_SINCE}. Drawings go only to that TV and are never saved.`,
        ]
      : []),
  ];
  const games =
    birdwatch || tumble || purrtrait
      ? `It has ${count} games: ${list}. Cat Tower and Tuna Tiles play in the iPhone and iPad app and in any web browser, and players on each sit at the same tables. ${where.join(" ")}`
      : `It has ${count} games: ${list}. It plays in the iPhone and iPad app and in any web browser, and players on each sit at the same tables.`;
  const alerts = consent ? "a parent decides whether they get notifications" : "they get no push notifications from our server";
  const text = `# Pounce: Family Games

> Pounce is a free family games app made by Conley Chaos LLC. ${games}

Play live together, or take turns over days. The game waits for everyone. Add players in the same room with a QR code, from far away with a link, or by passing one phone. A House Cat bot can hold a seat. To put the table on a TV, open ${origin}/play/tv on any big screen with a browser. Each phone, in the app or the browser, then shows just its own hand. On iPhone, Pounce has turn reminders, a Live Activity and a streak widget.${dish}

Pounce is free. It has no chat, no ads, no tracking and no third-party analytics, and nobody needs an account to play. Children under 13 get a simpler, limited version, and ${alerts}.

## Pages

- [Home](${origin}/): what Pounce is, screenshots, and how to start
- [Play in your browser](${origin}/play/): the web player, for Android phones, computers and tablets
${daily ? `- [The Daily Dish](${origin}/play/daily): today's four puzzles and the family board, in the browser\n` : ""}- [Support](${origin}/support): how to start a table, add players, play each game, play in a browser or on a TV, set reminders, report or block a player, and delete your data
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
