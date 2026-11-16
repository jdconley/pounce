import { expect, test, type Browser, type Page } from "@playwright/test";

import { firstRun } from "./helpers";

/**
 * The rendering thread does UI work only, and keeps up (docs/main-thread.md). While both games are
 * played, the page records long tasks and Long Animation Frames, and a DevTools trace gives each
 * frame's main-thread work. The gate fails on:
 * - any task or animation frame over 50 ms;
 * - per-frame main-thread work at p95 over 8.3 ms (one 120 Hz frame) on the laptop, or over
 *   16.7 ms (one 60 Hz frame) on a phone with its CPU slowed 4x.
 *
 * Headless Chrome draws at 60 Hz whatever the flags, so frames aren't counted: what is gated is the
 * work in each frame, which is what decides whether a 120 Hz screen gets every frame.
 */

const LONG_MS = 50;
const BUDGET = { "laptop-chrome": 1000 / 120, "android-chrome": 1000 / 60 } as const;
/**
 * The phone is a fixed speed, not "4x slower than whatever runs the test": a reference Mac (Apple
 * silicon) slowed 4x. Each run benchmarks its own machine and picks the slowdown that lands on
 * that speed, so a slower CI runner gets less throttling, never a slower phone than intended.
 */
const PHONE_SLOWDOWN = 4;
const REFERENCE_BENCH_MS = 14.5;

/** A fixed piece of JavaScript work: its median time says how fast this machine is. */
function bench(): number {
  const runs: number[] = [];
  for (let r = 0; r < 9; r++) {
    const t0 = performance.now();
    let x = 0;
    const a: { i: number; s: string }[] = [];
    for (let i = 0; i < 2_000_000; i++) {
      x = (x * 31 + i) % 1_000_003;
      if (i % 100 === 0) a.push({ i, s: String(x) });
    }
    a.sort((p, q) => p.s.localeCompare(q.s));
    runs.push(performance.now() - t0);
  }
  runs.sort((p, q) => p - q);
  return runs[4] as number;
}

type Gate = keyof typeof BUDGET;

async function throttleFor(page: Page, gate: Gate): Promise<{ rate: number; benchMs: number }> {
  const benchMs = await page.evaluate(bench);
  if (gate !== "android-chrome") return { rate: 1, benchMs };
  return { rate: Math.min(PHONE_SLOWDOWN, Math.max(1, (PHONE_SLOWDOWN * REFERENCE_BENCH_MS) / benchMs)), benchMs };
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
            scripts: (e.scripts ?? []).slice(0, 3).map((s) => (s.sourceFunctionName || s.invoker || "") + " " + (s.sourceURL || "").split("/").pop()),
          });
        }
      }).observe({ type, buffered: true });
    } catch {}
  }
`;

type TraceEvent = { name: string; ph: string; ts: number; dur?: number; pid: number; tid: number; args?: { name?: string } };

/** Each frame's main-thread work from a trace: the top-level tasks between one frame's start and the next. */
export function frameCosts(events: TraceEvent[]): { costs: number[]; longest: number } {
  const main = events.find((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
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

async function measure(browser: Browser, page: Page, gate: Gate) {
  const { rate, benchMs } = await throttleFor(page, gate);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Emulation.setCPUThrottlingRate", { rate });
  // Only gameplay counts: entries that started before it (the page loading) are set aside, even
  // when the observer delivers them late.
  const since = await page.evaluate(() => performance.now());
  await browser.startTracing(page, { categories: ["toplevel", "devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink.user_timing"] });
  await playCatTower(page);
  await playTiles(page);
  const trace = JSON.parse((await browser.stopTracing()).toString()) as { traceEvents: TraceEvent[] };
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });
  const all = (await page.evaluate(() => (window as unknown as { __long: unknown[] }).__long)) as { type: string; duration: number; at: number; scripts: string[] }[];
  const long = all.filter((e) => e.at >= since);
  const atLoad = all.filter((e) => e.at < since).map((e) => e.duration);
  const { costs, longest } = frameCosts(trace.traceEvents);
  if (process.env.MT_DEBUG) {
    const ev = trace.traceEvents;
    const main = ev.find((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain")!;
    const marks = ev.filter((e) => e.name.startsWith("step:")).map((e) => [e.ts, e.name] as const);
    const near = (ts: number) => marks.filter(([m]) => m <= ts).at(-1)?.[1] ?? "-";
    const top = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.name === "ThreadControllerImpl::RunTask" && e.dur).sort((a, b) => (b.dur as number) - (a.dur as number)).slice(0, 4);
    for (const t of top) {
      const inside = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.ph === "X" && e.ts >= t.ts && e.ts < t.ts + (t.dur as number) && e.dur && (e.dur as number) > 2000 && e.name !== "ThreadControllerImpl::RunTask" && e.name !== "RunTask");
      const what = ev.filter((e) => e.pid === main.pid && e.tid === main.tid && e.name === "EventDispatch" && e.ts >= t.ts && e.ts < t.ts + (t.dur as number)).map((e) => (e.args as { data?: { type?: string } })?.data?.type).join(",");
      console.log("LONG", ((t.dur as number) / 1000).toFixed(1), near(t.ts), what, inside.slice(0, 8).map((e) => `${e.name}:${((e.dur as number) / 1000).toFixed(1)}${(e.args as { data?: { url?: string; functionName?: string } })?.data?.functionName ? "(" + (e.args as { data: { functionName: string } }).data.functionName + ")" : ""}${(e.args as { data?: { url?: string } })?.data?.url ? "[" + String((e.args as { data: { url: string } }).data.url).split("/").pop() + "]" : ""}`).join(" "));
    }
  }
  return { frames: costs.length, p95: p95(costs), longest, long, rate, benchMs, atLoad };
}

test("the rendering thread keeps every frame: no long task, frame work within budget", async ({ browser, page, context }, info) => {
  const gate = info.project.name as Gate;
  test.skip(!(gate in BUDGET), "Chrome on the laptop and on a slowed phone");
  test.setTimeout(240_000);
  await context.setExtraHTTPHeaders({ "cf-connecting-ip": `10.250.${gate === "laptop-chrome" ? 1 : 2}.${(process.pid % 250) + 1}` });
  await context.addInitScript(RECORDER);
  await page.goto("/play/");
  await firstRun(page, "Gauge");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();

  const r = await measure(browser, page, gate);
  const sorted = [...r.long].sort((a, b) => b.duration - a.duration);
  const summary = {
    profile: `${gate} (CPU x${r.rate.toFixed(2)}; machine bench ${r.benchMs.toFixed(1)} ms, reference ${REFERENCE_BENCH_MS} ms)`,
    frames: r.frames,
    p95FrameWorkMs: Math.round(r.p95 * 100) / 100,
    budgetMs: Math.round(BUDGET[gate] * 100) / 100,
    longestTaskMs: Math.round(r.longest * 10) / 10,
    longEntries: sorted.slice(0, 5),
    loadLongFramesMs: r.atLoad,
  };
  console.log(`main thread: ${JSON.stringify(summary)}`);
  await info.attach("main-thread.json", { body: JSON.stringify(summary, null, 2), contentType: "application/json" });

  expect(r.frames, "frames traced").toBeGreaterThan(200);
  expect(sorted.filter((e) => e.duration > LONG_MS), "tasks and animation frames over 50 ms").toEqual([]);
  expect(r.longest, "longest main-thread task, ms").toBeLessThanOrEqual(LONG_MS);
  expect(r.p95, `p95 main-thread work per frame, ms (budget ${summary.budgetMs})`).toBeLessThanOrEqual(BUDGET[gate]);
});
