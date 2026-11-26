import { devices, expect, test, type Browser, type Page } from "@playwright/test";

import { bwStep, cardPoint, newStats } from "./birdwatch-helpers";
import { dailyPhone } from "./daily-phone";
import { closeAll, firstRun, newPlayer } from "./helpers";
import { openSniff, wrongWords } from "./sniff-helpers";
import { speedAt, REFERENCE, type Speed } from "./speed";
import { easelPicture, inked, joinLink, phoneScans, PURR, purrTv, tvMakesPurrtrait } from "./purr-helpers";
import { controllerTurn, poster, startFromPhone, tilesTurn, tvDeck, tvTable } from "./tv-helpers";

/**
 * The rendering thread does UI work only, and keeps up (docs/main-thread.md). While both games are
 * played and a Daily Dish puzzle is played and shared (and Sniff played and given up), the page records long tasks and Long Animation Frames, and a DevTools trace gives each
 * frame's main-thread work. The gate fails on:
 * - any task or animation frame over 50 ms;
 * - per-frame main-thread work at p95 over 8.3 ms (one 120 Hz frame) on the laptop, or over
 *   16.7 ms (one 60 Hz frame) on a phone with its CPU slowed 4x, or on the TV with its CPU slowed
 *   4x too (a 1080p page that watches two phones play both games).
 *
 * Headless Chrome draws at 60 Hz whatever the flags, so frames aren't counted: what is gated is the
 * work in each frame, which is what decides whether a 120 Hz screen gets every frame.
 */

const LONG_MS = 50;
const BUDGET = { "laptop-chrome": 1000 / 120, "android-chrome": 1000 / 60, "tv-chrome": 1000 / 60 } as const;
/**
 * The profiles are fixed speeds, not "whatever runs the test": the laptop is a reference Mac
 * (Apple silicon) and the phone is that Mac slowed 4x. So is the TV: a Chromium smart TV's chip
 * (four Cortex-A55 to A73 class cores) runs a page about four to six times slower than that Mac,
 * and a mid laptop about two to three; the slower of the two is the one to hold to. TV panels and
 * their browsers draw at 60 Hz, so its budget is one 60 Hz frame, 16.7 ms: at 4x that leaves an
 * unthrottled mid laptop around 2x headroom, and a TV no less than a phone gets. Each run
 * benchmarks its own machine at
 * plain JavaScript and at style and layout (a Linux CI runner can match the Mac at one and be half
 * its speed at the other) and takes the slower of the two as its speed factor `f`:
 * - the phone's and the TV's CPU slowdown is 4 / f (from 1 to 4), so each lands on the same
 *   device everywhere;
 * - whatever a machine is slower than its target even unthrottled (`residual`, 1 on the reference)
 *   divides the measured times, which are reported raw beside the result.
 */
const SLOWDOWN: Partial<Record<Gate, number>> = { "android-chrome": 4, "tv-chrome": 4 };
type Gate = keyof typeof BUDGET;

const speedFor = (page: Page, gate: Gate): Promise<Speed> => speedAt(page, SLOWDOWN[gate]);

/** Long tasks and Long Animation Frames, as the page sees them. */
const RECORDER = `
  window.__long = [];
  for (const type of ["longtask", "long-animation-frame"]) {
    try {
      new PerformanceObserver((list) => {
        for (const e of list.getEntries()) {
          window.__long.push({
            type,
            duration: Math.round(e.duration),
            at: Math.round(e.startTime),
            render: e.renderStart ? Math.round(e.startTime + e.duration - e.renderStart) : 0,
            style: e.styleAndLayoutStart ? Math.round(e.startTime + e.duration - e.styleAndLayoutStart) : 0,
            step: (performance.getEntriesByType("mark").filter((m) => m.startTime <= e.startTime).at(-1) || {}).name || "-",
            blocking: Math.round(e.blockingDuration ?? 0),
            scriptMs: Math.round((e.scripts ?? []).reduce((n, x) => n + x.duration, 0)),
            scripts: (e.scripts ?? []).slice(0, 3).map((s) => (s.sourceFunctionName || s.invoker || "") + " " + (s.sourceURL || "").split("/").pop()),
          });
        }
      }).observe({ type, buffered: true });
    } catch {}
  }
`;

type TraceEvent = { name: string; ph: string; ts: number; dur?: number; pid: number; tid: number; args?: { name?: string } };

/**
 * The measured page's rendering thread: the one that marked the steps. Other pages (the TV's
 * phones) have renderers of their own; with one page, it is the only one.
 */
function mainThread(events: TraceEvent[]): TraceEvent | undefined {
  const marked = events.find((e) => e.name.startsWith("step:"));
  const mains = events.filter((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
  return mains.find((e) => marked && e.pid === marked.pid && e.tid === marked.tid) ?? mains.find((e) => marked && e.pid === marked.pid) ?? mains[0];
}

/** Each frame's main-thread work from a trace: the top-level tasks between one frame's start and the next. */
export function frameCosts(events: TraceEvent[]): { costs: number[]; longest: number } {
  const main = mainThread(events);
  if (!main) return { costs: [], longest: 0 };
  const onMain = (e: TraceEvent) => e.pid === main.pid && e.tid === main.tid;
  const frames = events.filter((e) => onMain(e) && e.name === "BeginMainThreadFrame").map((e) => e.ts).sort((a, b) => a - b);
  const tasks = events.filter((e) => onMain(e) && e.name === "ThreadControllerImpl::RunTask" && e.ph === "X" && e.dur !== undefined).sort((a, b) => a.ts - b.ts);
  const costs: number[] = [];
  let t = 0;
  for (let i = 0; i + 1 < frames.length; i++) {
    const [from, to] = [frames[i] as number, frames[i + 1] as number];
    let busy = 0;
    while (t < tasks.length && (tasks[t] as TraceEvent).ts < to) {
      const task = tasks[t] as TraceEvent;
      if (task.ts >= from) busy += task.dur as number;
      t++;
    }
    costs.push(busy / 1000);
  }
  const longest = tasks.reduce((m, e) => Math.max(m, (e.dur as number) / 1000), 0);
  return { costs, longest };
}

const p95 = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(s.length * 0.95))] ?? 0;
};

const mark = (page: Page, step: string) => page.evaluate((s) => performance.mark(`step:${s}`), step);

async function playCatTower(page: Page) {
  await mark(page, "practice");
  await page.getByRole("button", { name: "Practice" }).click();
  await expect(page.locator("#deck")).toBeVisible();
  for (let turn = 0; turn < 3; turn++) {
    await expect(page.locator("#deck:not([disabled])")).toBeVisible({ timeout: 60_000 });
    const cards = page.locator(".card.mine .card-inner");
    const before = await cards.count();
    await mark(page, "draw");
    await page.locator("#deck").click();
    await expect(cards).toHaveCount(before + 1);
    await mark(page, "drag");
    // Drag a card across the table onto the discard pile.
    const from = (await cards.first().boundingBox())!;
    const to = (await page.locator("#discard").boundingBox())!;
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    for (let i = 1; i <= 40; i++) {
      await page.mouse.move(from.x + (to.x - from.x) * (i / 40) + Math.sin(i / 6) * 60, from.y + (to.y - from.y) * (i / 40));
    }
    await page.mouse.up();
    await expect(cards).toHaveCount(before);
  }
}

async function playTiles(page: Page) {
  // Home through the table's own menu: no page load inside the measured play.
  await mark(page, "menu");
  await page.getByRole("button", { name: "Menu" }).click();
  await mark(page, "home");
  await page.getByRole("button", { name: "Home" }).click();
  await mark(page, "tiles-lobby");
  await page.getByRole("button", { name: "Play Tuna Tiles" }).click();
  await mark(page, "tiles-start");
  await page.getByRole("button", { name: "Start" }).click();
  await expect(page.getByRole("img", { name: /Toy box/ })).toBeVisible();
  for (let turn = 0; turn < 2; turn++) {
    await expect(page.locator("#play-btn:not([disabled])")).toBeVisible({ timeout: 60_000 });
    // The hint runs in its Web Worker; the table only shows its answer.
    await mark(page, "hint");
    await page.getByRole("button", { name: "Hint" }).click();
    await page.waitForTimeout(600);
    await page.getByRole("button", { name: "Start over" }).click();
    await page.locator("#play-btn").click();
  }
}

/**
 * Birdwatch against three House Cats: the deal, the bid, a hand of tricks with cards dragged onto
 * the sill and tapped, the trick sweeping to its winner.
 */
async function playBirdwatch(page: Page) {
  await mark(page, "bw-menu");
  await page.getByRole("button", { name: "Menu" }).click();
  await page.getByRole("button", { name: "Home" }).click();
  await mark(page, "bw-lobby");
  await page.getByRole("button", { name: "Play Birdwatch" }).click();
  await expect(page.getByRole("button", { name: "House Cat" }).nth(2)).toBeVisible();
  await mark(page, "bw-start");
  await page.getByRole("button", { name: "Start" }).click();
  await expect(page.locator(".bw-table")).toBeVisible();
  const stats = newStats();
  let dragged = 0;
  const until = Date.now() + 45_000;
  while (Date.now() < until && stats.plays < 6) {
    const lead = page.locator(".bw-table.choosing");
    if (dragged < 3 && (await lead.isVisible())) {
      // Drag a card the server lets this seat play onto the sill.
      const dims = await page.locator(".bw-hand-card").evaluateAll((els) => els.map((el) => el.classList.contains("dim")));
      const before = dims.length;
      if (!dims.includes(false)) continue;
      const from = await cardPoint(page, dims.indexOf(false));
      const to = (await page.locator(".bw-sill").boundingBox())!;
      if (!from) continue;
      await mark(page, "bw-drag");
      await page.mouse.move(from.x, from.y);
      await page.mouse.down();
      for (let i = 1; i <= 30; i++) await page.mouse.move(from.x + (to.x + to.width / 2 - from.x) * (i / 30), from.y + (to.y + to.height / 2 - from.y) * (i / 30));
      await page.mouse.up();
      await expect.poll(() => page.locator(".bw-hand-card").count()).toBeLessThan(before);
      dragged++;
      stats.plays++;
      continue;
    }
    await mark(page, "bw-step");
    if ((await bwStep(page, "keys", stats, { bid: () => stats.bids === 0 })) === null) await page.waitForTimeout(150);
  }
}

/**
 * The Daily Dish: Home's Today row, the Dish and its board tabs, a puzzle in the host (the server's
 * test game), its end, and Share, whose card is drawn in a Web Worker.
 */
async function playDish(page: Page) {
  await mark(page, "dish-menu");
  await page.getByRole("button", { name: "Menu" }).click();
  await page.getByRole("button", { name: "Home" }).click();
  await mark(page, "dish-open");
  await page.getByRole("button", { name: "Open the Dish" }).click();
  await expect(page.getByRole("tablist", { name: "Board" })).toBeVisible();
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible()) await tip.click();
  await mark(page, "dish-tabs");
  await page.getByRole("tab", { name: "Test" }).click();
  await page.getByRole("tab", { name: "Dish" }).click();
  await mark(page, "dish-play");
  await page.getByRole("button", { name: "Play Test" }).click();
  const step = page.getByRole("button", { name: "Step" });
  await expect(page.getByTestId("test-count")).toBeVisible();
  while (await step.isEnabled()) {
    await mark(page, "dish-step");
    await step.click();
    await page.waitForTimeout(250);
  }
  await mark(page, "dish-end");
  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  await page.waitForTimeout(1500);
  await mark(page, "dish-share");
  await page.getByRole("button", { name: "Share" }).click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __shared?: boolean }).__shared === true)).toBe(true);
  await mark(page, "dish-back");
  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await expect(page.getByRole("tablist", { name: "Board" })).toBeVisible();
  await page.waitForTimeout(600);
  await playSniff(page);
}

/**
 * Sniff: two guesses on its keys, an unknown word, then Give up and back to the Dish. The guesses
 * are never today's word (`wrongWords`), so the run is still going at each step.
 */
async function playSniff(page: Page) {
  await mark(page, "sniff-open");
  const { answer } = await openSniff(page, () => page.getByRole("button", { name: "Play Sniff" }).click());
  const keys = page.getByRole("group", { name: "Keyboard" });
  const send = keys.getByRole("button", { name: "Sniff" });
  const tap = async (word: string) => {
    for (const l of word.toUpperCase()) await keys.getByRole("button", { name: new RegExp(`^${l}(,|$)`) }).click();
    await send.click();
  };
  const marks = (row: number) => page.getByRole("group", { name: `Try ${row}` }).locator(".sniff-tag[data-mark=spot], .sniff-tag[data-mark=near], .sniff-tag[data-mark=none]");
  for (const [i, word] of wrongWords(answer, 2).entries()) {
    // Still playing: the keys take input and this try is empty.
    await expect(send).toBeEnabled();
    await expect(marks(i + 1)).toHaveCount(0);
    await mark(page, "sniff-guess");
    await tap(word);
    await expect(marks(i + 1)).toHaveCount(5);
    await page.waitForTimeout(400);
  }
  await expect(send).toBeEnabled();
  await mark(page, "sniff-unknown");
  await tap("zzzzz");
  await expect(page.getByRole("status").filter({ hasText: "Not a word" })).toBeVisible();
  await page.waitForTimeout(600);
  for (let i = 0; i < 5; i++) await keys.getByRole("button", { name: "Delete" }).click();
  await mark(page, "sniff-give-up");
  await page.getByRole("button", { name: "Give up" }).click();
  await page.getByRole("dialog", { name: "Give up?" }).getByRole("button", { name: "Give up" }).click();
  await expect(page.getByRole("heading", { name: "Gave up" })).toBeVisible();
  await page.waitForTimeout(1200);
  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await expect(page.getByRole("tablist", { name: "Board" })).toBeVisible();
}

/**
 * The TV page shows a few turns of each game, played by two phones (other browser contexts, set
 * up before the trace): the TV is what is measured. Its own menu takes it from one game to the
 * next, and its poster makes each table.
 */
async function playOnTv(page: Page, phones: Page[]) {
  const join = async (game: "Cat Tower" | "Tuna Tiles") => {
    await mark(page, `tv-${game}`);
    await poster(page, game).click();
    const code = await tvTable(page);
    // One at a time: each phone takes the first open seat, so two at once could pick the same one.
    for (const [i, p] of phones.entries()) {
      await p.goto(`/play/j/${code}`);
      await expect(p).toHaveURL(new RegExp(`/play/t/${code}$`));
      await expect(page.locator(".tv-seat:not(.open)")).toHaveCount(i + 1);
    }
    await startFromPhone(...phones);
    await expect(page.locator(".tv-table")).toBeVisible();
  };
  await join("Cat Tower");
  let turns = 0;
  for (let i = 0; turns < 6 && i < 120; i++) {
    for (const p of phones) {
      const before = await tvDeck(page);
      if (!(await controllerTurn(p))) continue;
      turns++;
      await mark(page, `tv-ct-turn-${turns}`);
      await expect.poll(() => tvDeck(page)).toBeLessThan(before);
    }
    await page.waitForTimeout(200);
  }
  expect(turns, "Cat Tower turns the TV showed").toBe(6);
  await mark(page, "tv-menu");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Leave table" }).click();
  await expect(poster(page, "Tuna Tiles")).toBeVisible();
  await join("Tuna Tiles");
  turns = 0;
  for (let i = 0; turns < 6 && i < 120; i++) {
    for (const p of phones) {
      if (!(await tilesTurn(p, { tv: page }))) continue;
      turns++;
      await mark(page, `tv-tiles-turn-${turns}`);
    }
    await page.waitForTimeout(200);
  }
  expect(turns, "Tuna Tiles turns the TV showed").toBe(6);
  await boardOnTv(page);
}

/**
 * Tonight's board on the TV (the Daily Dish): a phone links it from the board's poster, turns on
 * Show on TV for the server's test game, and the TV watches the run to its end, then shows its
 * result on the board.
 */
async function boardOnTv(page: Page) {
  await mark(page, "tv-board");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Leave table" }).click();
  await page.getByRole("button", { name: "Tonight's board" }).click();
  const shown = page.locator(".tv-board-link .tv-code");
  await expect(shown).toHaveText(/^[A-Z0-9]{6}$/);
  const mom = await dailyPhone("Mom");
  expect(await mom.linkBoard(((await shown.textContent()) ?? "").trim())).toBe(200);
  await expect(page.locator(".tv-board")).toBeVisible();
  const { run, target } = await mom.start();
  await mom.showOnTv(run, true);
  await page.getByRole("button", { name: "Watch" }).click();
  for (let n = 1; n <= target; n++) {
    await mark(page, `tv-watch-${n}`);
    await mom.moves(run, n - 1, n);
    await page.waitForTimeout(400);
  }
  await expect(page.locator(".tv-watch-ended")).toBeVisible();
  // The result shows over the run, then the board comes back with it.
  await mark(page, "tv-board-back");
  await expect(page.locator('.tv-board-row[data-player="me"]')).toBeVisible({ timeout: 10_000 });
  await page.waitForTimeout(1500);
}

async function measure(browser: Browser, page: Page, gate: Gate, play: () => Promise<void>) {
  const speed = await speedFor(page, gate);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: speed.rate });
  // Only gameplay counts: entries that started before it (the page loading) are set aside, even
  // when the observer delivers them late.
  const since = await page.evaluate(() => performance.now());
  await browser.startTracing(page, { categories: ["toplevel", "devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink.user_timing"] });
  await play();
  const trace = JSON.parse((await browser.stopTracing()).toString()) as { traceEvents: TraceEvent[] };
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });
  const all = (await page.evaluate(() => (window as unknown as { __long: unknown[] }).__long)) as {
    type: string;
    duration: number;
    at: number;
    blocking: number;
    scriptMs: number;
    scripts: string[];
  }[];
  const long = all.filter((e) => e.at >= since);
  const atLoad = all.filter((e) => e.at < since).map((e) => e.duration);
  const { costs, longest } = frameCosts(trace.traceEvents);
  if (process.env.MT_DEBUG) {
    const ev = trace.traceEvents;
    const main = mainThread(ev)!;
    const marks = ev.filter((e) => e.name.startsWith("step:")).map((e) => [e.ts, e.name] as const);
    const near = (ts: number) => marks.filter(([m]) => m <= ts).at(-1)?.[1] ?? "-";
    const top = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.name === "ThreadControllerImpl::RunTask" && e.dur).sort((a, b) => (b.dur as number) - (a.dur as number)).slice(0, 4);
    for (const t of top) {
      const inside = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.ph === "X" && e.ts >= t.ts && e.ts < t.ts + (t.dur as number) && e.dur && (e.dur as number) > 2000 && e.name !== "ThreadControllerImpl::RunTask" && e.name !== "RunTask");
      const what = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.name === "EventDispatch" && e.ts >= t.ts && e.ts < t.ts + (t.dur as number)).map((e) => (e.args as { data?: { type?: string } })?.data?.type).join(",");
      console.log("LONG", ((t.dur as number) / 1000).toFixed(1), near(t.ts), what, inside.slice(0, 8).map((e) => `${e.name}:${((e.dur as number) / 1000).toFixed(1)}${(e.args as { data?: { url?: string; functionName?: string } })?.data?.functionName ? "(" + (e.args as { data: { functionName: string } }).data.functionName + ")" : ""}${(e.args as { data?: { url?: string } })?.data?.url ? "[" + String((e.args as { data: { url: string } }).data.url).split("/").pop() + "]" : ""}`).join(" "));
    }
  }
  return { frames: costs.length, p95: p95(costs), longest, long, speed, atLoad };
}

test("the rendering thread keeps every frame: no long task, frame work within budget", async ({ browser, page, context }, info) => {
  const gate = info.project.name as Gate;
  test.skip(!(gate in BUDGET), "Chrome on the laptop, on a slowed phone, and on the TV");
  test.setTimeout(gate === "tv-chrome" ? 360_000 : 300_000);
  await context.setExtraHTTPHeaders({ "cf-connecting-ip": `10.250.${{ "laptop-chrome": 1, "android-chrome": 2, "tv-chrome": 3 }[gate]}.${(process.pid % 250) + 1}` });
  await context.addInitScript(RECORDER);
  let play: () => Promise<void>;
  const phones: Awaited<ReturnType<typeof newPlayer>>[] = [];
  if (gate === "tv-chrome") {
    // The TV: Start, then home with its posters. Full screen would change the viewport under the trace.
    await context.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
    await page.goto("/play/tv");
    await page.getByRole("button", { name: "Start" }).click();
    await expect(poster(page, "Cat Tower")).toBeVisible();
    phones.push(await newPlayer(browser, "Ava", { context: devices["Pixel 7"] }), await newPlayer(browser, "Ben", { context: devices["iPhone 13"] }));
    play = () => playOnTv(page, phones.map((p) => p.page));
  } else {
    // Share's sheet is the system's; here it only records that the card arrived.
    await context.addInitScript(() => {
      Object.defineProperty(navigator, "canShare", { value: () => true, configurable: true });
      Object.defineProperty(navigator, "share", { value: async () => void ((window as unknown as { __shared: boolean }).__shared = true), configurable: true });
    });
    await page.goto("/play/");
    await firstRun(page, "Gauge");
    await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
    play = async () => {
      await playCatTower(page);
      await playTiles(page);
      await playBirdwatch(page);
      await playDish(page);
    };
  }

  const r = await measure(browser, page, gate, play);
  await closeAll(...phones.map((p) => p.context));
  // On a machine slower than the profile even unthrottled, times are scaled to the profile's speed.
  const k = r.speed.residual;
  const round = (n: number, d = 10) => Math.round(n * d) / d;
  const long = r.long.map((e) => ({ ...e, duration: round(e.duration / k) })).sort((a, b) => b.duration - a.duration) as (typeof r.long[number] & { blocking: number; scriptMs: number })[];
  const summary = {
    profile: gate,
    machine: `js ${round(r.speed.jsMs)} ms, render ${round(r.speed.renderMs)} ms (reference ${REFERENCE.jsMs}, ${REFERENCE.renderMs}): ${round(r.speed.f, 100)}x the reference's time`,
    cpuSlowdown: round(r.speed.rate, 100),
    scaledBy: round(k, 100),
    frames: r.frames,
    p95FrameWorkMs: round(r.p95 / k, 100),
    rawP95FrameWorkMs: round(r.p95, 100),
    budgetMs: round(BUDGET[gate], 100),
    longestTaskMs: round(r.longest / k),
    rawLongestTaskMs: round(r.longest),
    longEntries: long.slice(0, 5),
    loadLongFramesMs: r.atLoad,
  };
  console.log(`main thread: ${JSON.stringify(summary)}`);
  await info.attach("main-thread.json", { body: JSON.stringify(summary, null, 2), contentType: "application/json" });

  expect(r.frames, "frames traced").toBeGreaterThan(200);
  // A long task, or a long animation frame whose time was the rendering thread's (blocked, or
  // running script). A frame that was long while that thread sat idle (waiting on a worker or the
  // GPU) isn't the thread's doing; it is reported above, not failed.
  const ours = long.filter((e) => e.type === "longtask" ? e.duration > LONG_MS : e.blocking / k > 0 || e.scriptMs / k > LONG_MS);
  expect(ours, "tasks and animation frames over 50 ms on the rendering thread").toEqual([]);
  expect(r.longest / k, "longest main-thread task, ms").toBeLessThanOrEqual(LONG_MS);
  expect(r.p95 / k, `p95 main-thread work per frame, ms (budget ${summary.budgetMs})`).toBeLessThanOrEqual(BUDGET[gate]);
});

/**
 * Purrtrait's drawing (design §7): a scripted finger draws for 10 seconds on the drawer's phone
 * while the TV draws the stream. On android-chrome the drawer's slowed phone is measured, on
 * tv-chrome the TV page: no task over 50 ms, frame work within one 60 Hz frame at p95.
 */
test("drawing for 10 seconds keeps every frame, on the drawer's phone and on the TV", async ({ browser, page, context }, info) => {
  const gate = info.project.name as Gate;
  test.skip(gate !== "android-chrome" && gate !== "tv-chrome", "the drawer's slowed phone, and the TV");
  test.setTimeout(240_000);
  await context.setExtraHTTPHeaders({ "cf-connecting-ip": `10.251.${gate === "tv-chrome" ? 3 : 2}.${(process.pid % 250) + 1}` });
  await context.addInitScript(RECORDER);
  await context.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
  // The measured page is this project's own: the TV on tv-chrome, the drawer's phone on android-chrome.
  let tvPage: Page;
  if (gate === "tv-chrome") {
    tvPage = page;
    await page.goto(`${PURR}/play/tv`);
    await page.getByRole("button", { name: "Start", exact: true }).click();
  } else {
    tvPage = (await purrTv(browser)).page;
  }
  const tv = { context: tvPage.context(), page: tvPage, links: [] };
  await tvMakesPurrtrait(tv);
  const others: Awaited<ReturnType<typeof phoneScans>>[] = [];
  let drawer: Page;
  if (gate === "android-chrome") {
    await page.goto(`${PURR}/play/`);
    await firstRun(page, "Gauge");
    await page.goto(await joinLink(tv));
    await expect(page.getByRole("button", { name: /^Gauge, on this device/ })).toBeVisible();
    others.push(await phoneScans(browser, tv, "Ben", devices["iPhone 13"]));
    drawer = page;
  } else {
    others.push(await phoneScans(browser, tv, "Ava", devices["Pixel 7"]), await phoneScans(browser, tv, "Ben", devices["iPhone 13"]));
    drawer = others[0]!.page;
  }
  await drawer.locator("#start").click();
  // The first seat draws first.
  await expect(drawer.locator("#purr-cards")).toBeVisible();
  await drawer.locator("#pick-tricky").click();
  await expect(drawer.locator("#purr-easel")).toBeVisible();
  for (const tip of await drawer.getByRole("button", { name: "Dismiss tip" }).all()) await tip.click().catch(() => undefined);

  const box = (await drawer.locator("#purr-easel canvas.purr-live").boundingBox())!;
  const scribble = async () => {
    const end = Date.now() + 10_000;
    let k = 0;
    while (Date.now() < end) {
      k += 1;
      const cx = 0.5 + 0.3 * Math.cos(k);
      const cy = 0.5 + 0.3 * Math.sin(k * 1.3);
      await drawer.mouse.move(box.x + box.width * cx, box.y + box.height * cy);
      await drawer.mouse.down();
      for (let i = 1; i <= 40; i++) {
        const a = (i / 40) * Math.PI * 2;
        await drawer.mouse.move(box.x + box.width * (cx + 0.15 * Math.cos(a + k)), box.y + box.height * (cy + 0.12 * Math.sin(2 * a)));
      }
      await drawer.mouse.up();
      if (k % 6 === 0) await drawer.locator("#purr-undo").click();
    }
  };
  const measured = gate === "tv-chrome" ? tvPage : drawer;
  const r = await measure(browser, measured, gate, scribble);
  // The TV drew what the phone did.
  await expect.poll(async () => inked(await easelPicture(tvPage))).toBeGreaterThan(50);
  await closeAll(...others.map((o) => o.context), ...(gate === "tv-chrome" ? [] : [tvPage.context()]));
  const k = r.speed.residual;
  const summary = { profile: gate, frames: r.frames, p95FrameWorkMs: Math.round((r.p95 / k) * 100) / 100, budgetMs: BUDGET[gate], longestTaskMs: Math.round(r.longest / k), longEntries: r.long.slice(0, 5) };
  console.log(`purrtrait drawing: ${JSON.stringify(summary)}`);
  await info.attach("purrtrait-drawing.json", { body: JSON.stringify(summary, null, 2), contentType: "application/json" });
  expect(r.frames, "frames traced").toBeGreaterThan(200);
  const ours = r.long.filter((e) => (e.type === "longtask" ? e.duration / k > LONG_MS : e.blocking / k > 0 || e.scriptMs / k > LONG_MS));
  expect(ours, "tasks and animation frames over 50 ms on the rendering thread").toEqual([]);
  expect(r.longest / k, "longest main-thread task, ms").toBeLessThanOrEqual(LONG_MS);
  expect(r.p95 / k, `p95 main-thread work per frame, ms (budget ${BUDGET[gate]})`).toBeLessThanOrEqual(BUDGET[gate]);
});
