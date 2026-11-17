import { devices, expect, test, type Browser, type Page } from "@playwright/test";

import { closeAll, firstRun, newPlayer } from "./helpers";
import { controllerTurn, startFromPhone, tilesTurn, tvDeck, tvTable } from "./tv-helpers";

/**
 * The rendering thread does UI work only, and keeps up (docs/main-thread.md). While both games are
 * played, the page records long tasks and Long Animation Frames, and a DevTools trace gives each
 * frame's main-thread work. The gate fails on:
 * - any task or animation frame over 50 ms;
 * - per-frame main-thread work at p95 over 8.3 ms (one 120 Hz frame) on the laptop, or over
 *   16.7 ms (one 60 Hz frame) on a phone with its CPU slowed 4x, or on the TV (a 1080p page that
 *   watches two phones play both games: TV screens run at 60 Hz).
 *
 * Headless Chrome draws at 60 Hz whatever the flags, so frames aren't counted: what is gated is the
 * work in each frame, which is what decides whether a 120 Hz screen gets every frame.
 */

const LONG_MS = 50;
const BUDGET = { "laptop-chrome": 1000 / 120, "android-chrome": 1000 / 60, "tv-chrome": 1000 / 60 } as const;
/**
 * The profiles are fixed speeds, not "whatever runs the test": the laptop is a reference Mac
 * (Apple silicon) and the phone is that Mac slowed 4x. Each run benchmarks its own machine at
 * plain JavaScript and at style and layout (a Linux CI runner can match the Mac at one and be half
 * its speed at the other) and takes the slower of the two as its speed factor `f`:
 * - the phone's CPU slowdown is 4 / f (from 1 to 4), so it lands on the same phone everywhere;
 * - whatever a machine is slower than its target even unthrottled (`residual`, 1 on the reference)
 *   divides the measured times, which are reported raw beside the result.
 */
const PHONE_SLOWDOWN = 4;
const REFERENCE = { jsMs: 14.5, renderMs: 13.7 };

/** Fixed work in JavaScript, and in style and layout over a table-sized page: medians of 9. */
function bench(): { jsMs: number; renderMs: number } {
  const median = (runs: number[]) => runs.sort((p, q) => p - q)[Math.floor(runs.length / 2)] as number;
  const js: number[] = [];
  for (let r = 0; r < 9; r++) {
    const t0 = performance.now();
    let x = 0;
    const a: { i: number; s: string }[] = [];
    for (let i = 0; i < 2_000_000; i++) {
      x = (x * 31 + i) % 1_000_003;
      if (i % 100 === 0) a.push({ i, s: String(x) });
    }
    a.sort((p, q) => p.s.localeCompare(q.s));
    js.push(performance.now() - t0);
  }
  const host = document.createElement("div");
  host.style.cssText = "position:fixed;inset:0;contain:layout size;overflow:hidden;visibility:hidden";
  document.body.append(host);
  const els: HTMLElement[] = [];
  for (let i = 0; i < 160; i++) {
    const el = document.createElement("div");
    el.style.cssText = "position:absolute;left:0;top:0;width:60px;height:84px;border:3px solid #1b0b3a;border-radius:10px;background:linear-gradient(#fff,#eee);font:900 22px system-ui";
    el.innerHTML = `<span>${i % 13}</span><i style="display:block;width:20px;height:20px;background:#7b2fff"></i>`;
    host.append(el);
    els.push(el);
  }
  const render: number[] = [];
  for (let r = 0; r < 9; r++) {
    const t0 = performance.now();
    for (let k = 0; k < 20; k++) {
      els.forEach((el, i) => {
        el.style.transform = `translate(${(i * 7 + k * 13) % 900}px, ${(i * 11 + k * 5) % 600}px)`;
        el.className = (i + k) % 3 ? "a" : "b";
        (el.firstChild as Text).textContent = String((i + k) % 13);
        el.style.width = `${58 + ((i + k) % 5)}px`;
      });
      void host.offsetHeight;
    }
    render.push(performance.now() - t0);
  }
  host.remove();
  return { jsMs: median(js), renderMs: median(render) };
}

type Gate = keyof typeof BUDGET;

type Speed = { rate: number; residual: number; f: number; jsMs: number; renderMs: number };

async function speedFor(page: Page, gate: Gate): Promise<Speed> {
  const b = await page.evaluate(bench);
  const f = Math.max(b.jsMs / REFERENCE.jsMs, b.renderMs / REFERENCE.renderMs);
  if (gate !== "android-chrome") return { rate: 1, residual: Math.max(1, f), f, ...b };
  const rate = Math.min(PHONE_SLOWDOWN, Math.max(1, PHONE_SLOWDOWN / f));
  return { rate, residual: Math.max(1, (f * rate) / PHONE_SLOWDOWN), f, ...b };
}

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
 * The TV page shows a few turns of each game, played by two phones (other browser contexts, set
 * up before the trace): the TV is what is measured. Its own menu takes it from one game to the
 * next, and its poster makes each table.
 */
async function playOnTv(page: Page, phones: Page[]) {
  const join = async (game: "Cat Tower" | "Tuna Tiles") => {
    await mark(page, `tv-${game}`);
    await page.getByRole("button", { name: game, exact: true }).click();
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
  await expect(page.getByRole("button", { name: "Tuna Tiles", exact: true })).toBeVisible();
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
  test.setTimeout(gate === "tv-chrome" ? 360_000 : 240_000);
  await context.setExtraHTTPHeaders({ "cf-connecting-ip": `10.250.${{ "laptop-chrome": 1, "android-chrome": 2, "tv-chrome": 3 }[gate]}.${(process.pid % 250) + 1}` });
  await context.addInitScript(RECORDER);
  let play: () => Promise<void>;
  const phones: Awaited<ReturnType<typeof newPlayer>>[] = [];
  if (gate === "tv-chrome") {
    // The TV: Start, then home with its posters. Full screen would change the viewport under the trace.
    await context.addInitScript(() => (Element.prototype.requestFullscreen = () => Promise.resolve()));
    await page.goto("/play/tv");
    await page.getByRole("button", { name: "Start" }).click();
    await expect(page.getByRole("button", { name: "Cat Tower", exact: true })).toBeVisible();
    phones.push(await newPlayer(browser, "Ava", { context: devices["Pixel 7"] }), await newPlayer(browser, "Ben", { context: devices["iPhone 13"] }));
    play = () => playOnTv(page, phones.map((p) => p.page));
  } else {
    await page.goto("/play/");
    await firstRun(page, "Gauge");
    await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
    play = async () => {
      await playCatTower(page);
      await playTiles(page);
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
