/**
 * The privacy policy and the COPPA direct notice (spec §14, §14.1), served at
 * /privacy and linked from the app's gear sheet. A draft for JD to review; it
 * is not legal advice. Keep it in step with docs/privacy/retention-policy.md and
 * docs/privacy/app-store-label.md.
 */

import { CACHE, CSP, docPage } from "./layout";

const BODY = `<h1>Pounce privacy policy</h1>
<p class="updated">Last updated 13 November 2026</p>
<p>Pounce is a game app for couples and families, made by Conley Chaos LLC ("we"). This page says what the app and its server keep, why, who else handles it, for how long, and how to delete it. Pounce has no ads, no tracking, no third-party analytics and no third-party SDKs. We never sell your data and never share it for advertising. The only companies that handle it are the service providers named below, and only to run Pounce.</p>

<h2>What we keep</h2>
<ul>
<li><strong>A device id</strong> made by our server the first time the app runs, so your phone can rejoin its tables.</li>
<li><strong>Your name and cat</strong> as you choose them in the app, shown to the people at your tables and in the notifications they get. The same for anyone else you add to your phone for pass-and-play, and the names you give your tables.</li>
<li><strong>Games:</strong> your seats, turns, tables, the tables you archived, which tips you have seen, and your settings.</li>
<li><strong>Your device's time zone</strong>, so a day ends at your midnight. We never collect your location.</li>
<li><strong>An age band</strong> (under 13, 13 to 17, or 18 and over). The app works it out on your device; we never see or keep a birth date.</li>
<li><strong>Push tokens</strong>, if you allow notifications, so we can tell you when it's your move, update the widget and show a game on the Lock Screen.</li>
<li><strong>Streaks:</strong> the days you and another player both played, the days you played, lifetime counts and rewards, and, for players 13 and over, a count of the times of day you usually play, so reminders come at a good time.</li>
<li><strong>Requests to play</strong> you send or answer, and the invite links you make.</li>
<li><strong>How new players get started:</strong> for each device, the first time it reached each step of getting started (the age check, picking a name, Home, a first table, a first move, a first finished game, an invite sent or opened, the notifications question), which days it was used, the app version, the phone's language and region (like en-US), and whether an invite brought it. It is kept under a scrambled form of the device id, with no names, players, accounts or tables. We use it only to see where new players get stuck, on our own server. We also count how many times a day invite pages are opened, with nothing about who opened them.</li>
<li><strong>Sign in with Apple</strong>, if you use it: a one-way hash of the id Apple gives us, and, when our revocation key is set up, Apple's refresh token, kept only so we can revoke it when you delete your account. We ask Apple for no email and no name.</li>
</ul>
<!--consent--><p>We never collect contacts, location, photos, ad identifiers or messages, and no phone numbers except a parent's, given to us to consent for a child (below). Invites go through the share sheet or a QR code; Pounce never reads your contacts.</p><!--/consent--><!--plain--><p>We never collect contacts, location, photos, ad identifiers, phone numbers or messages. Invites go through the share sheet or a QR code; Pounce never reads your contacts.</p><!--/plain-->

<h2>Who sees what</h2>
<ul>
<li>The people at a table see the names and cats seated there. Someone who opens an invite link you sent sees your name and cat.</li>
<li>The other person in a streak sees that streak, never a record of who missed a day.</li>
<li>Nobody else sees your settings, your play times or your history.</li>
</ul>

<h2>Service providers</h2>
<ul>
<li><strong>Cloudflare</strong> runs our server and stores everything above. It sees your IP address when the app connects; we use it only for a moment, to limit how fast new devices can sign up, and never store it.</li>
<li><strong>Apple</strong> delivers notifications (they carry names, cats and table names) and runs Sign in with Apple and the App Store.</li>
<!--consent--><li><strong>Twilio Verify</strong> texts a code to a parent's mobile number when a parent consents for a child (below). It gets only that number.</li>
<!--/consent--></ul>
<p>Our server logs carry no names, phone numbers, player ids or tokens; an error log can carry a table's code.</p>

<h2>How long we keep it</h2>
<ul>
<li>A table, with the names seated at it: until 7 days after its last move.</li>
<li>Shared streak days: 120 days. Your own streak days: 8 days. Lifetime counts and rewards: until you leave that streak or delete your data.</li>
<li>Requests to play and invite links: 7 days. A link stops working sooner once someone plays on it.</li>
<li>A player who isn't signed in and that no device has opened for 90 days: deleted.</li>
<li>A player merged into an account: a forwarding record for 30 days.</li>
<li>A push token: until Apple tells us it no longer works, or the app sends a new one.</li>
<li>Getting-started steps: a year after the device was last used. Invite page counts: a year.</li>
<li>Everything else: until you delete it, or until it expires as above.</li>
</ul>

<h2>Your choices</h2>
<ul>
<li>Signing in is never required. Without it, your data stays tied to your device.</li>
<li>You can delete your data in the app at any time, signed in or not: open the gear, then tap the trash can (signed in) or Delete my data. That deletes your player from our server with its games, streaks, connections, requests to play, invite links and settings, this device's getting-started steps, and, for a child's device, the parent's consent record and phone number. When you're signed in it is your account on every device, and it revokes Sign in with Apple when we hold a token; you can also stop Apple sign-in for Pounce in iOS Settings, under your name, then Sign in with Apple. Your name stays visible at tables you sat at until those tables are cleaned up, at most 7 days after their last move.</li>
<li>You can turn notifications off in iOS Settings at any time.</li>
<li>To see or delete anything else we hold, write to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</li>
</ul>

<section id="coppa">
<h2>Notice for parents (children under 13)</h2>
<p>Pounce is made for adults playing with their families, not for children on their own. It asks every new player's age in a neutral way, using Apple's Declared Age Range when it can, and never blocks a child from playing. For a player under 13, without a parent's consent, Pounce collects only what the game needs to run (support for internal operations, as the Children's Online Privacy Protection Act allows):</p>
<ul>
<li>a device id and the child's seats and turns;</li>
<li>a name picked from Pounce's list of generated cat names (Mochi, Biscuit, Pickle and the like); a child cannot type a name;</li>
<li>game progress such as streaks and rewards;</li>
<li>a time zone, so a day ends at the child's midnight;</li>
<li>the getting-started steps above, which say nothing about who the child is, used only to make the game easier to start.</li>
</ul>
<p>For a player under 13 there are no push notifications from our server, no sign-in, no invite links sent out, and no record of play times. The only reminders are ones the phone schedules for itself, and they start off.</p>
<!--consent--><h2>With a parent's consent</h2>
<p>A parent or guardian who is signed in to Pounce can allow notifications on a child's own device. The child's device shows a six-digit code; the parent enters it on their own device, reads our <a href="/privacy/kitten-notice">notice to parents</a>, and gives their mobile number. Twilio Verify, our verification provider, texts that number a six-digit code, and the parent types it into Pounce to confirm. A day or so later, Pounce sends a notification to the parent's own device saying what they allowed, with a Revoke button; if none of their devices can get it within a day, consent ends. With that consent we also keep:</p>
<ul>
<li>the child's device's push token, used only to tell it when it's the child's move at a table where everyone else is approved, and when an approved person asks the child to play;</li>
<li>which of the people the child plays with the parent approved (or that Apple's Screen Time Communication Limits approved);</li>
<li>the parent's mobile number, only while consent lasts, or 30 minutes if the code is never entered. Twilio Verify holds it while the code lasts (10 minutes) and in its own records for about 30 days after that; for a day we also keep a keyed hash of it, so that no number gets more than three codes a day;</li>
<li>Apple's app transaction id for the child's copy of Pounce, so that a parent withdrawing approval through Apple ends this consent too.</li>
</ul>
<p>The parent can take it back at any time: in the app, with the Revoke button on our notification, or through Apple. That stops every notification at once and deletes the push token and the number. It also ends when the child turns 13 or the child's player is deleted.</p>
<!--/consent--><p>A parent can delete a child's information at any time on the child's device: the gear, then Delete my data. A parent may also ask to review or delete it, or to stop any further collection, by writing to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>. A child's player that no device has opened for 90 days is deleted from our server automatically, for example after the app is removed from the child's device.</p>
<p>Operator: Conley Chaos LLC, <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</p>
</section>

<h2>Changes</h2>
<p>If this policy changes in a way that matters, the app will say so before the change applies to you.</p>`;

const HTML = docPage({
  title: "Pounce privacy",
  head: '<meta name="description" content="The Pounce privacy policy: what the app and its server keep, why, who else handles it, for how long, how to delete it, and the notice for parents of children under 13.">\n',
  body: BODY,
  current: "privacy",
});


/** With parent consent (`CONSENT` on) the policy says what it adds; off, the page is as before. */
const WITH_CONSENT = HTML.replace(/<!--plain-->[\s\S]*?<!--\/plain-->/g, "").replace(/<!--\/?consent-->/g, "");
const WITHOUT_CONSENT = HTML.replace(/<!--consent-->[\s\S]*?<!--\/consent-->/g, "").replace(/<!--\/?plain-->/g, "");

/** The privacy policy page; public, static, no scripts. */
export function privacyPage(consent = true): Response {
  return new Response(consent ? WITH_CONSENT : WITHOUT_CONSENT, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP },
  });
}
