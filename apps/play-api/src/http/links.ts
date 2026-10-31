import { ROOM_CODE } from "../room/codes";

const CACHE = "public, max-age=300";
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";

const ASSOCIATION = JSON.stringify({
  applinks: {
    details: [{ appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }] }],
  },
});

const CAT = `<svg class="cat" viewBox="0 0 120 110" role="img" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M18 6 44 30q16-6 32 0L102 6q8 22 4 48 8 10 8 24 0 28-54 28T6 78q0-14 8-24Q10 28 18 6Z"/><circle cx="43" cy="62" r="6" fill="#fff"/><circle cx="77" cy="62" r="6" fill="#fff"/></svg>`;

const STYLE = `body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff7ec;color:#2b2118;font-family:system-ui,sans-serif;text-align:center}main{padding:24px}.cat{width:120px;height:auto;color:#2b2118}h1{margin:16px 0 8px;font-size:1.25rem;font-weight:600}.code{font-size:3.5rem;font-weight:800;letter-spacing:.15em;margin:0 0 24px;font-family:ui-monospace,monospace}a{display:inline-block;padding:12px 24px;border-radius:999px;background:#2b2118;color:#fff7ec;text-decoration:none;font-weight:600}@media (prefers-color-scheme:dark){body{background:#1c1612;color:#fff7ec}.cat{color:#fff7ec}a{background:#fff7ec;color:#1c1612}}`;

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (ch) => ESCAPES[ch] as string);
}

/** Apple fetches this to bind `/j/*` links on our domain to the app. */
export function appSiteAssociation(): Response {
  return new Response(ASSOCIATION, {
    headers: { "content-type": "application/json", "cache-control": CACHE },
  });
}

/** The landing page for a shared room link, for people without the app. */
export function sharePage(code: string, testflightUrl: string | undefined): Response {
  if (!ROOM_CODE.test(code)) {
    return new Response("Not found", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  const link = testflightUrl?.startsWith("https://")
    ? `<a href="${escapeHtml(testflightUrl)}">Get the app</a>`
    : "";
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(code)}</title>
<style>${STYLE}</style>
</head>
<body>
<main>
${CAT}
<h1>Join the game</h1>
<p class="code">${escapeHtml(code)}</p>
${link}
</main>
</body>
</html>
`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": CACHE,
      "content-security-policy": CSP,
    },
  });
}
