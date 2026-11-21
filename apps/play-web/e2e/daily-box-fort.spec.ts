import { expect, test, type Page } from "@playwright/test";
import { place } from "@pounce/play-api/daily/box-fort/rules";

import { closeAll, newPlayer } from "./helpers";

/**
 * Box Fort in the browser, end to end, against the server (`DAILY=on`): from the Dish, every piece
 * dragged from the tray onto the rug until the fort is built or nothing fits, then the end. And the
 * drag's frame gate: while a piece is held and moved over the rug, no animation frame is long and
 * the rendering thread's work per frame stays within one frame.
 */

type Board = {
  rug: number[];
  pieces: [number, number][][];
  placed: boolean[];
  over: string | null;
  ready: boolean;
  x: number;
  y: number;
  cell: number;
};

const LIFT = 1.1;

async function board(page: Page): Promise<Board> {
  return JSON.parse((await page.locator(".bf").getAttribute("data-board")) ?? "null") as Board;
}

/** The greedy move: the placement that clears the most lines, the biggest piece first. */
function choose(b: Board): { slot: number; row: number; col: number } | null {
  let best: { slot: number; row: number; col: number; score: number } | null = null;
  b.pieces.forEach((cells, slot) => {
    if (b.placed[slot]) return;
    const piece = { id: "", tint: 1, cells };
    for (let row = 0; row < 8; row++) {
      for (let col = 0; col < 8; col++) {
        const out = place(b.rug, piece, row, col);
        if (!out) continue;
        // Clears first, then big pieces, then low and to the left (keeps the top open).
        const score = (out.cleared.rows.length + out.cleared.cols.length) * 1000 + cells.length * 50 + row * 4 - col;
        if (!best || score > best.score) best = { slot, row, col, score };
      }
    }
  });
  return best;
}

/** Where a finger lets go so the held piece's top left lands on (`row`, `col`), in the page. */
async function dropPoint(page: Page, b: Board, cells: [number, number][], row: number, col: number) {
  const root = (await page.locator(".bf").boundingBox())!;
  const rows = Math.max(...cells.map(([r]) => r)) + 1;
  const cols = Math.max(...cells.map(([, c]) => c)) + 1;
  return { x: root.x + b.x + (col + cols / 2) * b.cell, y: root.y + b.y + (row + rows + LIFT) * b.cell };
}

async function drag(page: Page, slot: number, to: { x: number; y: number }, steps = 12) {
  const button = page.getByTestId(`boxfort-slot-${slot}`);
  const from = (await button.boundingBox())!;
  const start = { x: from.x + from.width / 2, y: from.y + from.height / 2 };
  if (test.info().project.name === "iphone-safari") {
    // Playwright's mouse makes no pointer events in mobile WebKit: the finger's events go to the
    // piece as a touch would send them (it holds the pointer while it's dragged).
    const path = Array.from({ length: steps + 1 }, (_, i) => ({ x: start.x + ((to.x - start.x) * i) / steps, y: start.y + ((to.y - start.y) * i) / steps }));
    await button.evaluate(async (el, points) => {
      const fire = (type: string, p: { x: number; y: number }) =>
        el.dispatchEvent(new PointerEvent(type, { pointerId: 7, pointerType: "touch", isPrimary: true, button: 0, clientX: p.x, clientY: p.y, bubbles: true, cancelable: true }));
      fire("pointerdown", points[0]!);
      for (const p of points.slice(1)) {
        fire("pointermove", p);
        await new Promise(requestAnimationFrame);
      }
      fire("pointerup", points.at(-1)!);
    }, path);
    return;
  }
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) await page.mouse.move(start.x + ((to.x - start.x) * i) / steps, start.y + ((to.y - start.y) * i) / steps);
  await page.mouse.up();
}

async function openBoxFort(page: Page) {
  await page.getByRole("button", { name: "Open the Dish" }).click();
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible()) await tip.click();
  await page.getByRole("button", { name: "Play Box Fort" }).click();
  await expect(page).toHaveURL(/\/play\/daily\/box-fort$/);
  await expect(page.locator(".bf[data-board]")).toBeVisible();
}

test("Box Fort plays to the end: pieces dragged onto the rug, the score, the end", async ({ browser }) => {
  test.setTimeout(300_000);
  const kit = await newPlayer(browser, "Kit");
  const { page } = kit;
  await openBoxFort(page);

  let placed = 0;
  for (let guard = 0; guard < 400; guard++) {
    const b = await board(page);
    if (b.over !== null) break;
    if (!b.ready) {
      await page.waitForTimeout(100);
      continue;
    }
    const move = choose(b);
    expect(move, "a piece fits whenever the run goes on").not.toBeNull();
    const { slot, row, col } = move!;
    const before = b.placed.filter(Boolean).length;
    await drag(page, slot, await dropPoint(page, b, b.pieces[slot]!, row, col));
    // Placed: the slot empties, or a new set is dealt, or the run ends.
    await expect
      .poll(async () => {
        const n = await board(page);
        return n.over !== null || n.placed.filter(Boolean).length !== before || n.pieces.some((p, i) => JSON.stringify(p) !== JSON.stringify(b.pieces[i]));
      })
      .toBe(true);
    placed++;
  }
  expect(placed, "pieces placed").toBeGreaterThan(10);
  await expect(page.getByRole("heading", { name: "Fort done" })).toBeVisible({ timeout: 30_000 });
  await expect(page.locator(".dd-end")).toContainText(/\d+ (pts|points)/);
  await closeAll(kit.context);
});

type TraceEvent = { name: string; ph: string; ts: number; dur?: number; pid: number; tid: number; args?: { name?: string } };

/** Each frame's main-thread work from a trace, as the main-thread gate counts it. */
function frameWork(events: TraceEvent[]): number[] {
  const marked = events.find((e) => e.name.startsWith("step:"));
  const mains = events.filter((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
  const main = mains.find((e) => marked && e.pid === marked.pid && e.tid === marked.tid) ?? mains[0];
  if (!main) return [];
  const onMain = (e: TraceEvent) => e.pid === main.pid && e.tid === main.tid;
  const frames = events.filter((e) => onMain(e) && e.name === "BeginMainThreadFrame").map((e) => e.ts).sort((a, b) => a - b);
  const tasks = events.filter((e) => onMain(e) && e.name === "ThreadControllerImpl::RunTask" && e.ph === "X" && e.dur !== undefined).sort((a, b) => a.ts - b.ts);
  const costs: number[] = [];
  let t = 0;
  for (let i = 0; i + 1 < frames.length; i++) {
    let busy = 0;
    while (t < tasks.length && tasks[t]!.ts < frames[i + 1]!) {
      if (tasks[t]!.ts >= frames[i]!) busy += tasks[t]!.dur!;
      t++;
    }
    costs.push(busy / 1000);
  }
  return costs;
}

const BUDGET: Record<string, number> = { "laptop-chrome": 1000 / 120, "android-chrome": 1000 / 60 };

test("the drag holds the frame rate: no long frame, frame work within one frame", async ({ browser }, info) => {
  const gate = info.project.name;
  test.skip(!(gate in BUDGET), "Chrome on the laptop and on a phone slowed 4x");
  const ivy = await newPlayer(browser, "Ivy");
  const { page } = ivy;
  await page.evaluate(() => {
    const w = window as unknown as { __long: { duration: number; blocking: number; script: number }[] };
    w.__long = [];
    new PerformanceObserver((list) => {
      for (const e of list.getEntries() as (PerformanceEntry & { blockingDuration?: number; scripts?: { duration: number }[] })[]) {
        w.__long.push({ duration: e.duration, blocking: e.blockingDuration ?? 0, script: (e.scripts ?? []).reduce((n, s) => n + s.duration, 0) });
      }
    }).observe({ type: "long-animation-frame" });
  });
  await openBoxFort(page);
  await page.waitForTimeout(1000);
  const cdp = await page.context().newCDPSession(page);
  if (gate === "android-chrome") await cdp.send("Emulation.setCPUThrottlingRate", { rate: 4 });
  await page.evaluate(() => {
    (window as unknown as { __long: unknown[] }).__long = [];
    performance.mark("step:drag");
  });
  await browser.startTracing(page, { categories: ["toplevel", "devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink.user_timing"] });

  // Pick up each piece and sweep it over the rug, row by row, without letting go on it.
  const b = await board(page);
  const root = (await page.locator(".bf").boundingBox())!;
  for (const slot of [0, 1, 2]) {
    const from = (await page.getByTestId(`boxfort-slot-${slot}`).boundingBox())!;
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    for (let i = 0; i <= 90; i++) {
      const sweep = i / 90;
      await page.mouse.move(root.x + b.x + b.cell * (1 + 6 * Math.abs(Math.sin(sweep * Math.PI * 3))), root.y + b.y + b.cell * (3 + 6 * sweep));
    }
    // Let go at the top, where the piece floats off the rug and goes back to its slot.
    await page.mouse.move(root.x + root.width / 2, root.y + 4, { steps: 8 });
    await page.mouse.up();
  }

  const trace = JSON.parse((await browser.stopTracing()).toString()) as { traceEvents: TraceEvent[] };
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });
  const long = (await page.evaluate(() => (window as unknown as { __long: { duration: number; blocking: number; script: number }[] }).__long)) ?? [];
  const costs = frameWork(trace.traceEvents).sort((p, q) => p - q);
  const p95 = costs[Math.min(costs.length - 1, Math.floor(costs.length * 0.95))] ?? 0;
  const summary = { profile: gate, frames: costs.length, p95FrameWorkMs: Math.round(p95 * 100) / 100, budgetMs: Math.round(BUDGET[gate]! * 100) / 100, longFrames: long.map((e) => Math.round(e.duration)) };
  console.log(`box fort drag: ${JSON.stringify(summary)}`);
  await info.attach("box-fort-drag.json", { body: JSON.stringify(summary, null, 2), contentType: "application/json" });

  // Every piece went back: nothing was placed by the sweep.
  expect((await board(page)).placed).toEqual([false, false, false]);
  expect(costs.length, "frames traced").toBeGreaterThan(100);
  expect(long.filter((e) => e.blocking > 0 || e.script > 50), "animation frames over 50 ms on the rendering thread").toEqual([]);
  expect(p95, `p95 main-thread work per frame, ms (budget ${summary.budgetMs})`).toBeLessThanOrEqual(BUDGET[gate]!);
  await closeAll(ivy.context);
});

/**
 * Screenshots of every screen Box Fort touches on the web, on a small phone, a big phone, an iPad
 * both ways and a laptop, and on a phone with the text at twice its size: the Dish with Box Fort on
 * it, a run under way, a piece held over the rug, and the end. Skipped unless `BOXFORT_SHOTS_DIR`
 * is set.
 */
test("screenshots", async ({ browser }, info) => {
  const dir = process.env.BOXFORT_SHOTS_DIR;
  test.skip(!dir || info.project.name !== "laptop-chrome", "BOXFORT_SHOTS_DIR, once");
  test.setTimeout(600_000);
  const phone = { isMobile: true, hasTouch: true, deviceScaleFactor: 2 };
  const sizes: [string, Parameters<typeof browser.newContext>[0], boolean?][] = [
    ["se", { ...phone, viewport: { width: 375, height: 667 } }],
    ["max", { ...phone, viewport: { width: 440, height: 956 }, deviceScaleFactor: 3 }],
    ["ipad-portrait", { ...phone, viewport: { width: 820, height: 1180 } }],
    ["ipad-landscape", { ...phone, viewport: { width: 1180, height: 820 } }],
    ["laptop", { viewport: { width: 1440, height: 900 } }],
    ["se-big-text", { ...phone, viewport: { width: 375, height: 667 } }, true],
  ];
  for (const [name, context, big] of sizes) {
    const who = await newPlayer(browser, "Marmalade Montgomery", { context });
    const { page } = who;
    if (big) await page.addStyleTag({ content: "html { font-size: 200% !important; }" });
    const shot = (what: string) => page.screenshot({ path: `${dir}/web-${name}-${what}.png` });
    await page.getByRole("button", { name: "Open the Dish" }).click();
    const tip = page.getByRole("button", { name: "Dismiss tip" });
    if (await tip.isVisible()) await tip.click();
    await page.waitForTimeout(600);
    await shot("dish");
    // The Dish as it was before Box Fort (a build without its line in the registry).
    if (process.env.BOXFORT_SHOTS_BEFORE) {
      await closeAll(who.context);
      continue;
    }
    await page.getByRole("button", { name: "Play Box Fort" }).click();
    await expect(page.locator(".bf[data-board]")).toBeVisible();
    if (big) await page.addStyleTag({ content: "html { font-size: 200% !important; }" });
    await page.waitForTimeout(800);
    await shot("start");
    for (let i = 0; i < 7; i++) {
      const b = await board(page);
      const move = choose(b);
      if (!move || b.over) break;
      await drag(page, move.slot, await dropPoint(page, b, b.pieces[move.slot]!, move.row, move.col));
      await page.waitForTimeout(450);
    }
    await page.waitForTimeout(900);
    await shot("play");
    // A piece held over the rug, its landing spot showing.
    const b = await board(page);
    const move = choose(b);
    if (move) {
      const from = (await page.getByTestId(`boxfort-slot-${move.slot}`).boundingBox())!;
      const to = await dropPoint(page, b, b.pieces[move.slot]!, move.row, move.col);
      await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
      await page.mouse.down();
      for (let i = 1; i <= 10; i++) await page.mouse.move(from.x + from.width / 2 + ((to.x - from.x - from.width / 2) * i) / 10, from.y + from.height / 2 + ((to.y - from.y - from.height / 2) * i) / 10);
      await page.waitForTimeout(200);
      await shot("drag");
      await page.mouse.up();
    }
    for (let guard = 0; guard < 400; guard++) {
      const n = await board(page);
      if (n.over !== null) break;
      if (!n.ready) {
        await page.waitForTimeout(100);
        continue;
      }
      const m = choose(n);
      if (!m) break;
      await drag(page, m.slot, await dropPoint(page, n, n.pieces[m.slot]!, m.row, m.col));
      await page.waitForTimeout(160);
    }
    await expect(page.getByRole("heading", { name: "Fort done" })).toBeVisible({ timeout: 30_000 });
    await page.waitForTimeout(2500);
    await shot("end");
    await closeAll(who.context);
  }
});
