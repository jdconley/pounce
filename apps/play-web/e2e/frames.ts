/**
 * A small frame gate for one page, the way `main-thread.spec.ts` measures (docs/main-thread.md):
 * long tasks as the page sees them, each frame's main-thread work from a DevTools trace, and the
 * machine's speed against the same reference Mac, so a slower CI runner is held to the same
 * device. Used by games' own specs (Nine Lives); main-thread.spec keeps its own copy for now.
 */
import type { Browser, Page } from "@playwright/test";

/** The reference Mac's times for `bench` (main-thread.spec's REFERENCE). */
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

/** Long tasks and Long Animation Frames, as the page sees them: add with `addInitScript`. */
export const RECORDER = `
  window.__long = [];
  for (const type of ["longtask", "long-animation-frame"]) {
    try {
      new PerformanceObserver((list) => {
        for (const e of list.getEntries()) window.__long.push({ type, duration: Math.round(e.duration), blocking: Math.round(e.blockingDuration ?? 0) });
      }).observe({ type });
    } catch {}
  }
`;

type TraceEvent = { name: string; ph: string; ts: number; dur?: number; pid: number; tid: number; args?: { name?: string } };

/** Each frame's main-thread work in a trace of one page: its tasks between one frame's start and the next. */
function frameCosts(events: TraceEvent[]): number[] {
  const main = events.find((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
  if (!main) return [];
  const on = (e: TraceEvent) => e.pid === main.pid && e.tid === main.tid;
  const frames = events.filter((e) => on(e) && e.name === "BeginMainThreadFrame").map((e) => e.ts).sort((a, b) => a - b);
  const tasks = events.filter((e) => on(e) && e.name === "ThreadControllerImpl::RunTask" && e.ph === "X" && e.dur !== undefined).sort((a, b) => a.ts - b.ts);
  const costs: number[] = [];
  let t = 0;
  for (let i = 0; i + 1 < frames.length; i++) {
    let busy = 0;
    while (t < tasks.length && (tasks[t] as TraceEvent).ts < (frames[i + 1] as number)) {
      if ((tasks[t] as TraceEvent).ts >= (frames[i] as number)) busy += (tasks[t] as TraceEvent).dur as number;
      t++;
    }
    costs.push(busy / 1000);
  }
  return costs;
}

export type FrameReport = {
  frames: number;
  /** How many times the reference's time this machine takes (1 or more); times below are divided by it. */
  scaledBy: number;
  p95FrameWorkMs: number;
  rawP95FrameWorkMs: number;
  longestFrameWorkMs: number;
  /** Long tasks over 50 ms, and Long Animation Frames that blocked the rendering thread. */
  long: { type: string; duration: number; blocking: number }[];
};

/** Traces `play` on `page` (which has `RECORDER`) and reports its frames at the reference's speed. */
export async function measureFrames(browser: Browser, page: Page, play: () => Promise<void>): Promise<FrameReport> {
  const b = await page.evaluate(bench);
  const k = Math.max(1, b.jsMs / REFERENCE.jsMs, b.renderMs / REFERENCE.renderMs);
  await page.evaluate(() => ((window as unknown as { __long: unknown[] }).__long = []));
  await browser.startTracing(page, { categories: ["toplevel", "devtools.timeline", "disabled-by-default-devtools.timeline.frame"] });
  await play();
  const trace = JSON.parse((await browser.stopTracing()).toString()) as { traceEvents: TraceEvent[] };
  const costs = frameCosts(trace.traceEvents).sort((p, q) => p - q);
  const p95 = costs[Math.min(costs.length - 1, Math.floor(costs.length * 0.95))] ?? 0;
  const all = await page.evaluate(() => (window as unknown as { __long: { type: string; duration: number; blocking: number }[] }).__long);
  const round = (n: number) => Math.round(n * 100) / 100;
  return {
    frames: costs.length,
    scaledBy: round(k),
    p95FrameWorkMs: round(p95 / k),
    rawP95FrameWorkMs: round(p95),
    longestFrameWorkMs: round((costs.at(-1) ?? 0) / k),
    long: all.filter((e) => (e.type === "longtask" ? e.duration / k > 50 : e.blocking > 0)),
  };
}
