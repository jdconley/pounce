/**
 * The public site: the home page at `/` and the help page at `/support`
 * (the App Store's Support URL). Static, no scripts; styled like /privacy.
 * Keep the support steps in step with docs/app-review-notes.md.
 */
import { CACHE, CSP, STYLE } from "./privacy";

const HEADERS = { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP };
const CONTACT = "privacy@conleychaos.com";

const ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
const escapeHtml = (text: string): string => text.replace(/[&<>"']/g, (ch) => ESCAPES[ch] as string);

const page = (title: string, body: string): string => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>${STYLE}nav{margin-top:28px}nav a{margin-right:18px;font-weight:600}</style>
</head>
<body>
<main>
${body}
</main>
</body>
</html>
`;

const SUPPORT = page(
  "Pounce: Family Games support",
  `<h1>Pounce: Family Games help</h1>
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
</section>

<nav><a href="/">Home</a><a href="/privacy">Privacy policy</a></nav>`,
);

/** The help page; public, static, no scripts. */
export function supportPage(): Response {
  return new Response(SUPPORT, { headers: HEADERS });
}

/** The home page; shows an install link only when `appStoreUrl` is set. */
export function homePage(appStoreUrl?: string): Response {
  const install = appStoreUrl ? `<p><a href="${escapeHtml(appStoreUrl)}">Get the app</a></p>\n` : "";
  return new Response(
    page(
      "Pounce: Family Games",
      `<h1>Pounce: Family Games</h1>
<p>A card game for couples and families. Play a turn whenever you have a minute, and the game waits for you.</p>
${install}<nav><a href="/support">Support</a><a href="/privacy">Privacy policy</a></nav>`,
    ),
    { headers: HEADERS },
  );
}
