import { CACHE, CSP, STYLE } from "../http/privacy";

/**
 * The parent's pages and texts (consent design §2 layer 2, D1; plan decisions
 * 27, 31). The direct notice is a draft for JD to review (D4); it is not
 * legal advice. Texts carry no child's name or anything else about the child:
 * text plus is allowed only when the child's information is never disclosed.
 */

const PAGE_CSP = `${CSP}; form-action 'self'`;

function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function page(title: string, body: string, cache = "no-store", status = 200): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${escapeHtml(title)}</title>
<style>${STYLE}button{font:inherit;font-weight:700;font-size:1.15rem;color:#1b0b3a;background:#9be22e;border:3px solid #1b0b3a;border-radius:16px;padding:12px 26px;margin-top:8px}button.revoke{background:#ff4fa3;color:#fff}</style>
</head>
<body>
<main>
${body}
</main>
</body>
</html>
`;
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": cache, "content-security-policy": PAGE_CSP },
  });
}

const NOTICE = `<h1>Notice to parents: notifications for a child</h1>
<p class="updated">Last updated 5 November 2026</p>
<p>Pounce is a card game for couples and families, made by Conley Chaos LLC, <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>. A child under 13 can play Pounce on their own device without notifications. With your consent, the child's device can also be told when it's their move, and when someone you approve asks them to play.</p>

<h2>Why we have your mobile number</h2>
<p>You gave us your mobile number in the Pounce app, signed in to your own account, so that we can ask for your consent and confirm it. We use it only for that: two texts (this request, and a reminder a day or so after you agree that tells you how to take it back) and nothing else. If you don't confirm within 7 days, we delete the number. If you do, we keep it only while your consent lasts and delete it as soon as it ends.</p>

<h2>What we collect from the child with your consent</h2>
<ul>
<li><strong>A push token</strong> for the child's device, which Apple issues so that we can send it notifications.</li>
<li><strong>Who may reach the child:</strong> the people the child plays with that you approve (or that you approve through Apple's Screen Time, if you use its Communication Limits). Notifications come only from them: "your move" at a table where everyone else is approved, and requests to play.</li>
</ul>
<p>We collect this only with your consent, and use it only to send those notifications. Without your consent the child can still play, and we send the child's device nothing.</p>
<p>We don't show any of it to anyone else, and we never sell or share it. Notifications pass through Apple, and our texts to you pass through Twilio, our text message provider; neither may use them for anything else. The child's name in Pounce is picked from a list of made-up cat names, nothing is public, and only people the child already plays with can see it.</p>

<h2>How to say yes</h2>
<p>Open the link in our text and confirm. You can also ignore the text: then nothing changes, and your number is deleted after 7 days.</p>

<h2>How to take it back</h2>
<ul>
<li>In the Pounce app: the gear, then the kittens, then the bell for that child.</li>
<li>Reply STOP to either of our texts, or open the link in the second one.</li>
<li>If you approved Pounce for the child through Apple, withdrawing it there ends this consent too.</li>
</ul>
<p>Taking it back stops every notification to the child's device at once and deletes its push token and your number. The child keeps playing. You can also ask us to review or delete the child's information, or to stop collecting it, by writing to <a href="mailto:privacy@conleychaos.com">privacy@conleychaos.com</a>.</p>

<p>Our full privacy policy, including what Pounce keeps for every player: <a href="/privacy">play.conleychaos.com/privacy</a>.</p>`;

/** `/privacy/kitten-notice`: the direct notice (16 CFR 312.4(c)); static, no scripts. */
export function noticePage(): Response {
  return page("Pounce notice to parents", NOTICE, CACHE);
}

export type TokenKind = "confirm" | "revoke";

/** `GET /consent/{token}`: what the button will do, and the button. GET never changes anything (prefetchers). */
export function tokenPage(kind: TokenKind, child: { name: string }, token: string): Response {
  const name = escapeHtml(child.name);
  const action = `/consent/${encodeURIComponent(token)}`;
  if (kind === "confirm") {
    return page(
      "Allow notifications",
      `<h1>Allow notifications for ${name}?</h1>
<p>Please read the <a href="/privacy/kitten-notice">notice to parents</a> first. It says what we collect from the child, why, and how to take it back.</p>
<form method="post" action="${action}"><button type="submit">I'm the parent or guardian. Allow.</button></form>`,
    );
  }
  return page(
    "Turn off notifications",
    `<h1>Turn off notifications for ${name}?</h1>
<p>Notifications to the child's device stop at once, and we delete its push token and your number. The child keeps playing.</p>
<form method="post" action="${action}"><button class="revoke" type="submit">Turn them off</button></form>`,
  );
}

export type Outcome = "confirmed" | "revoked" | "gone";

/** The page after the button, or for a link that's used up or expired. */
export function outcomePage(outcome: Outcome): Response {
  if (outcome === "confirmed") {
    return page(
      "Allowed",
      `<h1>Thank you</h1>
<p>Notifications are on for the child's device. We'll text you once more in a day or so with a way to take it back. You can also turn them off in the Pounce app at any time, or reply STOP.</p>`,
    );
  }
  if (outcome === "revoked") {
    return page("Turned off", `<h1>Turned off</h1><p>Notifications to the child's device have stopped, and we've deleted your number.</p>`);
  }
  return page("Link used", `<h1>This link has been used or has expired</h1><p>Nothing changed. You can manage notifications in the Pounce app.</p>`, "no-store", 404);
}

/** Text 1: the notice link with the one-time confirm (D1). */
export const firstText = (link: string): string =>
  `Pounce: a parent or guardian asked to allow notifications for a child's Pounce game. Read what we keep and confirm: ${link} Reply STOP to cancel.`;

/** Text 2, a day or so after consent: "the plus" (D1). */
export const secondText = (link: string): string =>
  `Pounce: you allowed notifications for a child's Pounce game. To revoke, tap ${link} or reply STOP.`;
