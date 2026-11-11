import { CACHE, CSP, docPage } from "../http/layout";

import type { Outgoing } from "../notify/types";

/**
 * The parent's notice page and the confirmation push (consent design §2
 * layer 2, D1 and D6; plan decisions 31, 50–53). The direct notice is a draft
 * for JD to review (D4); it is not legal advice. Twilio Verify sends only its
 * own code message, so nothing about the child ever goes by text.
 */

function page(title: string, body: string): Response {
  // The app shows this page inside the consent sheet, so it has no site header or footer.
  const html = docPage({ title, body, head: '<meta name="robots" content="noindex">\n', embedded: true });
  return new Response(html, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": CACHE, "content-security-policy": CSP },
  });
}

const NOTICE = `<h1>Notice to parents: notifications for a child</h1>
<p class="updated">Last updated 5 November 2026</p>
<p>Pounce is a card game for couples and families, made by Conley Chaos LLC, <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>. A child under 13 can play Pounce on their own device without notifications. With your consent, the child's device can also be told when it's their move, and when someone you approve asks them to play.</p>

<h2>Why we have your mobile number</h2>
<p>You gave us your mobile number in the Pounce app, signed in to your own account, so that we can check it's yours: Twilio Verify, our verification provider, texts it a six-digit code, and you type the code into Pounce. We use the number for nothing else. If the code isn't entered within 30 minutes of the last code we sent, we delete the number. If it is, we keep the number only while your consent lasts and delete it as soon as consent ends. Twilio keeps the number while the code lasts (10 minutes), and in its own records for about 30 days after that under its privacy policy; it may not use it for anything else.</p>
<p>A day or so after you agree, between 10:00 and 20:00 where you are, Pounce sends a notification on your own device saying what you allowed and how to take it back, with a Revoke button. If none of your devices can get that notification within a day, consent ends, so please allow notifications for Pounce on your device.</p>

<h2>What we collect from the child with your consent</h2>
<ul>
<li><strong>A push token</strong> for the child's device, which Apple issues so that we can send it notifications.</li>
<li><strong>Who may reach the child:</strong> the people the child plays with that you approve (or that you approve through Apple's Screen Time, if you use its Communication Limits). Notifications come only from them: "your move" at a table where everyone else is approved, and requests to play.</li>
</ul>
<p>We collect this only with your consent, and use it only to send those notifications. Without your consent the child can still play, and we send the child's device nothing.</p>
<p>We don't show any of it to anyone else, and we never sell or share it. Notifications pass through Apple, and the code to your phone passes through Twilio Verify; neither may use them for anything else. The child's name in Pounce is picked from a list of made-up cat names, nothing is public, and only people the child already plays with can see it. No text we send names the child.</p>

<h2>How to say yes</h2>
<p>Type the six-digit code from our text into Pounce. You can also ignore the text: then nothing changes, and your number is deleted after 30 minutes.</p>

<h2>How to take it back</h2>
<ul>
<li>In the Pounce app: the gear, then the kittens, then the bell for that child.</li>
<li>Press and hold our notification, then Revoke.</li>
<li>If you approved Pounce for the child through Apple, withdrawing it there ends this consent too.</li>
</ul>
<p>Taking it back stops every notification to the child's device at once and deletes its push token and your number. The child keeps playing. You can also ask us to review or delete the child's information, or to stop collecting it, by writing to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</p>

<p>Our full privacy policy, including what Pounce keeps for every player: <a href="/privacy">play.conleychaos.com/privacy</a>.</p>`;

/** `/privacy/kitten-notice`: the direct notice (16 CFR 312.4(c)); static, no scripts. */
export function noticePage(): Response {
  return page("Pounce notice to parents", NOTICE);
}

/**
 * The plus (D6): a day or so after consent, an alert on the consenting
 * parent's own devices, in place of text plus's second text. Its category
 * carries a Revoke button; a tap opens the Kittens panel on this kitten. The
 * title is the kitten's generated cat name, as the panel shows it; the body is
 * legal text, like the notice.
 */
export function plusPush(kid: string, name: string): Outgoing {
  return {
    kind: "consent",
    title: name,
    body: "You allowed notifications on this child's Pounce. To take it back, press and hold for Revoke, or tap to open Kittens.",
    thread: "consent",
    collapse: `consent:${kid}`,
    data: { kitten: kid },
  };
}
