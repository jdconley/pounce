/**
 * The privacy policy and the COPPA direct notice (spec §14, §14.1), served at
 * /privacy and linked from the app's gear sheet. A draft for JD to review; it
 * is not legal advice. Keep it in step with docs/privacy/retention-policy.md.
 */

const CACHE = "public, max-age=300";
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

const STYLE = `body{margin:0;background:#2a0f5c;color:#fff;font-family:system-ui,sans-serif;line-height:1.55}main{max-width:720px;margin:0 auto;padding:28px 20px 56px}h1{font-size:2rem;margin:0 0 4px;color:#ff8a00}h2{font-size:1.25rem;margin:32px 0 8px;color:#00d1c1}p,li{font-size:1rem}ul{padding-left:22px}.updated{color:#9be22e;font-weight:600;margin:0 0 20px}a{color:#2eb8ff}section{background:#3a1a75;border:3px solid #1b0b3a;border-radius:18px;padding:4px 18px 14px;margin-top:24px}`;

const HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pounce privacy</title>
<style>${STYLE}</style>
</head>
<body>
<main>
<h1>Pounce privacy policy</h1>
<p class="updated">Last updated 4 November 2026</p>
<p>Pounce is a card game for couples and families, made by Conley Chaos LLC ("we"). This page says what the app and its server keep, why, for how long, and how to make it go away. Pounce has no ads, no analytics, no tracking and no third-party SDKs, and it never sells or shares your data.</p>

<h2>What we keep</h2>
<ul>
<li><strong>A device id</strong> made by our server the first time the app runs, so your phone can rejoin its tables.</li>
<li><strong>Your name and cat</strong> as you choose them in the app, shown to the people at your tables. The same for anyone else you add to your phone for pass-and-play.</li>
<li><strong>Games:</strong> your seats, turns, tables, the tables you archived, which tips you have seen, and your settings.</li>
<li><strong>Your device's time zone</strong>, so a day ends at your midnight. We never collect your location.</li>
<li><strong>An age band</strong> (under 13, 13 to 17, or 18 and over). The app works it out on your device; we never see or keep a birth date.</li>
<li><strong>A push token</strong>, if you allow notifications, so we can tell you when it's your turn.</li>
<li><strong>Sign in with Apple</strong>, if you use it: a one-way hash of the id Apple gives us, and, when our revocation key is set up, Apple's refresh token, kept only so we can revoke it when you delete your account. We ask Apple for no email and no name.</li>
<li><strong>Streaks</strong> (coming soon): the days you and another player both played, kept for 120 days, plus lifetime counts and rewards, and a count of the times of day you usually start playing.</li>
</ul>
<p>We never collect contacts, location, ad identifiers, phone numbers or messages. Invites go through the share sheet; Pounce never reads your contacts.</p>

<h2>Who sees what</h2>
<ul>
<li>The people at a table see the names and cats seated there.</li>
<li>The other person in a streak sees that streak, never a record of who missed a day.</li>
<li>Nobody else sees your settings, your play times or your history. Our server logs carry no names, player ids or tokens.</li>
<li>Our server runs on Cloudflare. Notifications go through Apple. Neither may use your data for anything else.</li>
</ul>

<h2>How long we keep it</h2>
<ul>
<li>Daily streak history: 120 days.</li>
<li>A guest player (not signed in) that no device has opened for 90 days: deleted.</li>
<li>A guest player merged into an account: a forwarding record for 30 days.</li>
<li>Invite links: 24 hours. Requests to play: 7 days.</li>
<li>Everything else: until you delete your account, or until it expires as above.</li>
</ul>

<h2>Your choices</h2>
<ul>
<li>Signing in is never required. Without it, your data stays tied to your device.</li>
<li>You can delete your account in the app: the gear, then your account, then the trash can. That deletes your player and everything about it on our server, and revokes Sign in with Apple when we hold a token. You can also stop Apple sign-in for Pounce in iOS Settings, under your name, then Sign in with Apple.</li>
<li>You can turn notifications off in iOS Settings at any time.</li>
<li>To see or delete anything else we hold, write to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</li>
</ul>

<section id="coppa">
<h2>Notice for parents (children under 13)</h2>
<p>Pounce is made for adults playing with their families, not for children on their own. It asks every new player's age in a neutral way, using Apple's Declared Age Range when it can, and never blocks a child from playing. For a player under 13, without a parent's consent, Pounce collects only what the game needs to run (support for internal operations, as the Children's Online Privacy Protection Act allows):</p>
<ul>
<li>a device id and the child's seats and turns;</li>
<li>a name picked from Pounce's list of generated cat names (Mochi, Biscuit, Pickle and the like); a child cannot type a name;</li>
<li>game progress such as streaks and rewards.</li>
</ul>
<p>For a player under 13 there are no push notifications from our server, no sign-in, no invite links sent out, and no record of play times. The only reminders are ones the phone schedules for itself, and they start off.</p>
<p>A parent may ask to review or delete a child's information, or to stop any further collection, by writing to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>. Deleting the app's data from the child's device, or not opening the app for 90 days, also deletes the child's player on our server.</p>
<p>Operator: Conley Chaos LLC, <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</p>
</section>

<h2>Changes</h2>
<p>If this policy changes in a way that matters, the app will say so before the change applies to you.</p>
</main>
</body>
</html>
`;

/** The privacy policy page; public, static, no scripts. */
export function privacyPage(): Response {
  return new Response(HTML, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP },
  });
}
