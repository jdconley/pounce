/**
 * Screenshots of Purrtrait at every size AGENTS.md and the spec (§11) ask for (a dev tool):
 *   BASE=http://127.0.0.1:8797 OUT=screenshots/purrtrait node scripts/purrtrait-shots.mjs
 * Needs a server with GAMES listing purrtrait (for first run and the TV's credential). Each screen
 * is a snapshot played to the page through its own socket, so every phase shows exactly; the TV's
 * drawing is ink sent the same way. One player is "Great Aunt Josephine", to test long names.
 * "Largest text" is the page's root font size at 200%, which every rem in the player follows.
 * BEFORE=1 takes only the screens that existed before Purrtrait (Home, the TV's home).
 */
import { mkdirSync } from "node:fs";

import { chromium, devices } from "@playwright/test";

const OUT = process.env.OUT ?? "screenshots/purrtrait";
const BASE = process.env.BASE ?? "http://127.0.0.1:8797";
const BEFORE = process.env.BEFORE === "1";
mkdirSync(OUT, { recursive: true });

const PHONES = [
  { name: "iphone-se", ...devices["iPhone SE (3rd gen)"] },
  { name: "iphone-pro-max", ...devices["iPhone 15 Pro Max"] },
  { name: "ipad-portrait", ...devices["iPad (gen 7)"] },
  { name: "ipad-landscape", ...devices["iPad (gen 7) landscape"] },
  { name: "iphone-se-largest-text", ...devices["iPhone SE (3rd gen)"], big: true },
].filter((s) => !process.env.SIZES || process.env.SIZES.split(",").includes(s.name));
const TVS = [
  { name: "tv-1080p", viewport: { width: 1920, height: 1080 } },
  { name: "tv-720p", viewport: { width: 1280, height: 720 } },
].filter((s) => !process.env.SIZES || process.env.SIZES.split(",").includes(s.name));

const NAMES = ["Mom", "Great Aunt Josephine", "Ava", "Leo", "Mochi", "Bea", "Cy", "Dot", "Eli", "Fay"];
const id = (i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`;

/** A Purrtrait room as a snapshot carries it. `yours`: this device's seats. */
function room({ players = 5, yours = [0], host = true, status = "playing", view = null, screen = true, near = null }) {
  return {
    code: "BCDFG",
    name: "Couch crew",
    status,
    youAreHost: host,
    seats: Array.from({ length: 10 }, (_, i) =>
      i < players
        ? { kind: "human", person: { id: id(i), name: NAMES[i], cat: i % 8 }, yours: yours.includes(i), presence: "awake" }
        : { kind: status === "lobby" && i === players ? "open" : "closed", yours: false, presence: null },
    ),
    game: null,
    gameId: "purrtrait",
    options: { timer: 60 },
    ...(view ? { purrtrait: view } : {}),
    ...(screen ? { screen: true } : {}),
    ...(near ? { near } : {}),
    link: { ping: 3000, acks: [] },
  };
}

function view(over = {}) {
  const seats = over.seats ?? 5;
  return {
    seats,
    timer: 60,
    rounds: 2,
    phase: "drawing",
    round: 1,
    drawer: 1,
    order: Array.from({ length: seats }, (_, i) => i),
    scores: [3, 5, 1, 0, 2, 0, 0, 0, 0, 0].slice(0, seats),
    out: Array(seats).fill(false),
    group: "animals",
    level: "tricky",
    remainingMs: 42_000,
    paused: false,
    turn: "1:1",
    last: null,
    winners: [],
    ...over,
  };
}

const snap = (r, seq = 5) => ({ t: "snapshot", protocol: 1, seq, room: r });

/** A cat's face, drawn as the TV gets it: ink ops on the 768 x 1024 grid. */
const CAT_INK = [
  ["s", 0, 0, 2, 384, 300, 120, 20, 60, 120, -20, 140, -100, 70, -120, 0, -100, -70, -20, -140, 60, -120, 120, -20],
  ["s", 1, 0, 2, 300, 330, -40, -150, 120, 90],
  ["s", 2, 0, 2, 468, 330, 40, -150, -120, 90],
  ["s", 3, 5, 2, 330, 470, 4, 4],
  ["s", 4, 5, 2, 440, 470, 4, 4],
  ["s", 5, 1, 1, 384, 540, -20, 20, 40, 0, -20, -20],
  ["s", 6, 0, 1, 384, 560, -30, 40, -30, -10],
  ["s", 7, 0, 1, 384, 560, 30, 40, 30, -10],
  ["s", 8, 0, 0, 300, 560, -120, -20],
  ["s", 9, 0, 0, 300, 580, -120, 20],
  ["s", 10, 0, 0, 468, 560, 120, -20],
  ["s", 11, 0, 0, 468, 580, 120, 20],
  ["s", 12, 3, 2, 120, 900, 520, 0],
  ["s", 13, 2, 1, 600, 140, 40, 40, -40, 40, -40, -40, 40, -40],
];

const browser = await chromium.launch({ args: ["--mute-audio"] });
let ip = 1;

/** A page whose room socket says what the script says. */
async function scripted(page) {
  let said = [];
  let close = null;
  await page.routeWebSocket(/\/v1\/rooms\/[A-Z0-9]+\/ws/, (ws) => {
    if (close) {
      ws.close(close);
      return;
    }
    ws.onMessage((m) => {
      if (JSON.parse(String(m)).t === "ping") ws.send(JSON.stringify({ t: "pong" }));
    });
    for (const m of said) ws.send(JSON.stringify(m));
  });
  return {
    say: (messages) => {
      said = messages;
      close = null;
    },
    refuse: (c) => (close = c),
  };
}

for (const size of PHONES) {
  const { name, big, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", reducedMotion: "reduce", extraHTTPHeaders: { "cf-connecting-ip": `10.81.${process.pid % 200}.${ip++}` } });
  if (big) await ctx.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  const shot = async (step, wait = 700) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png` });
  };
  await page.goto(`${BASE}/play/`);
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill("Mom");
  await page.getByRole("button", { name: "Done" }).click();
  await page.locator(".poster-grid").waitFor();
  const dismiss = async () => {
    for (const tip of await page.getByRole("button", { name: "Dismiss tip" }).all()) await tip.evaluate((b) => b.click()).catch(() => undefined);
  };
  await dismiss();
  const last = page.locator(".poster").last();
  await last.scrollIntoViewIfNeeded();
  await shot("home");
  if (BEFORE) {
    await ctx.close();
    continue;
  }
  await page.evaluate(() => window.scrollTo(0, 0));

  const s = await scripted(page);
  const open = async (messages, wait) => {
    s.say(messages);
    await page.goto(`${BASE}/play/t/BCDFG`);
    await page.locator(".screen").first().waitFor();
    await page.waitForTimeout(wait ?? 500);
  };

  await open([snap(room({ status: "lobby", players: 5 }))]);
  await shot("lobby-host");
  await page.getByRole("button", { name: /Great Aunt Josephine/ }).click();
  await shot("lobby-remove");
  await page.keyboard.press("Escape");
  await open([snap(room({ status: "lobby", players: 2, host: false, yours: [1], screen: false }))]);
  await shot("lobby-guest-no-tv");
  await open([snap(room({ status: "lobby", players: 10 }))]);
  await shot("lobby-ten");

  await open([snap(room({ yours: [1], view: view({ phase: "choosing", remainingMs: 8000, group: null, level: null, choices: { easy: "pizza", tricky: "sandcastle" } }) }))]);
  await shot("pick");
  await dismiss();
  await open([snap(room({ yours: [1], view: view({ word: "sandcastle", youDraw: true }) }))]);
  await shot("draw-empty");
  await dismiss();
  // A few strokes, as a finger draws them.
  const easel = page.locator("#purr-easel");
  const box = await easel.boundingBox();
  if (box) {
    const at = (x, y) => [box.x + box.width * x, box.y + box.height * y];
    const stroke = async (pts) => {
      await page.mouse.move(...at(...pts[0]));
      await page.mouse.down();
      for (const p of pts.slice(1)) await page.mouse.move(...at(...p), { steps: 6 });
      await page.mouse.up();
    };
    await stroke([[0.2, 0.7], [0.5, 0.45], [0.8, 0.7], [0.2, 0.7]]);
    await page.getByRole("radio", { name: "Blue" }).click();
    await stroke([[0.1, 0.85], [0.3, 0.8], [0.5, 0.88], [0.7, 0.8], [0.9, 0.86]]);
    await page.getByRole("radio", { name: "Yellow" }).click();
    await page.getByRole("radio", { name: "Thick" }).click();
    await stroke([[0.8, 0.15], [0.82, 0.17]]);
  }
  await shot("draw");
  await dismiss();
  await page.getByRole("button", { name: "Got it" }).click();
  await shot("got-it");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Give up" }).click();
  await shot("give-up");
  await page.keyboard.press("Escape");
  await open([snap(room({ yours: [1], view: view({ word: "sandcastle", youDraw: true }) })), { t: "error", code: "easel_full" }]);
  await shot("draw-full");

  await open([snap(room({ yours: [1, 3], view: view({ phase: "choosing", choices: { easy: "pizza", tricky: "sandcastle" } }) }))]);
  await shot("shared-curtain");

  await open([snap(room({ yours: [0], view: view() }))]);
  await shot("watch");
  await open([snap(room({ yours: [2], view: view() }))]);
  await shot("watch-next");
  await open([snap(room({ yours: [0], view: view({ paused: true }) }))]);
  await shot("watch-paused");
  await open([snap(room({ yours: [0], view: view({ phase: "reveal", last: { word: "sandcastle", guesser: 0, points: 2 }, scores: [5, 7, 1, 0, 2] }) }))]);
  await shot("watch-reveal");
  await open([snap(room({ status: "over", yours: [0], view: view({ phase: "over", drawer: null, scores: [9, 11, 4, 6, 2], winners: [1] }) }))], 1200);
  await shot("over");

  s.refuse({ code: 4403, reason: "not_near" });
  await page.goto(`${BASE}/play/t/BCDFG`);
  await page.locator("#table-refused").waitFor();
  await shot("not-near");
  s.refuse({ code: 4403, reason: "removed" });
  await page.goto(`${BASE}/play/t/BCDFG`);
  await page.locator("#table-refused").waitFor();
  await shot("removed");

  await page.goto(`${BASE}/play/join`);
  await page.getByLabel("Table code").fill("BCDFGKQ");
  await shot("join-code");
  await ctx.close();
}

for (const size of TVS) {
  const { name, ...device } = size;
  const ctx = await browser.newContext({ ...device, serviceWorkers: "block", reducedMotion: "reduce", extraHTTPHeaders: { "cf-connecting-ip": `10.82.${process.pid % 200}.${ip++}` } });
  await ctx.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(name, "pageerror:", e.message));
  const shot = async (step, wait = 900) => {
    await page.waitForTimeout(wait);
    await page.screenshot({ path: `${OUT}/${step}-${name}.png` });
  };
  await page.goto(`${BASE}/play/tv`);
  await page.getByRole("button", { name: "Start", exact: true }).click();
  await page.locator(".tv-poster").first().waitFor();
  await shot("tv-home", 1500);
  if (BEFORE) {
    await ctx.close();
    continue;
  }
  const s = await scripted(page);
  const open = async (messages, wait = 900) => {
    s.say(messages);
    await page.evaluate(() => localStorage.setItem("pounce.tv.room", "BCDFG"));
    await page.goto(`${BASE}/play/tv`);
    const wake = page.getByRole("button", { name: "Press OK for sound" });
    await wake.click();
    await page.waitForTimeout(wait);
  };
  const near = { key: "KQ2X7MNP", code: "BCDFGKQ", expiresIn: 30_000 };
  await open([snap(room({ status: "lobby", players: 5, near }))]);
  await shot("tv-lobby");
  await open([snap(room({ status: "lobby", players: 10, near }))]);
  await shot("tv-lobby-ten");
  await open([snap(room({ view: view({ phase: "choosing", group: null, level: null, remainingMs: 8000 }), near }))]);
  await shot("tv-picking");
  await open([snap(room({ view: view(), near })), { t: "inkSync", turn: "1:1", ops: CAT_INK }]);
  await shot("tv-drawing", 1500);
  await open([snap(room({ players: 10, view: view({ seats: 10, remainingMs: 7000 }), near })), { t: "inkSync", turn: "1:1", ops: CAT_INK }]);
  await shot("tv-drawing-ten", 1500);
  await open([snap(room({ view: view({ phase: "reveal", last: { word: "sandcastle", guesser: 0, points: 2 }, scores: [5, 7, 1, 0, 2] }), near })), { t: "inkSync", turn: "1:1", ops: CAT_INK }]);
  await shot("tv-reveal", 1500);
  await open([snap(room({ status: "over", view: view({ phase: "over", drawer: null, scores: [9, 11, 4, 6, 2], winners: [1] }), near }))], 2000);
  await shot("tv-over");
  await ctx.close();
}
await browser.close();
console.log(`shots in ${OUT}`);
