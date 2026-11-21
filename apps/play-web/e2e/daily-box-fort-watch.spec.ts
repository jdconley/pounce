/**
 * Box Fort's TV watch view reads from the couch: the score and the set count are big on a TV's
 * stage and sit clear of the rug. The view is drawn alone, on a page Vite's dev server serves
 * (e2e/fixtures/box-fort-watch.html), in a box the size the browser TV gives it.
 *
 * BOXFORT_SHOTS_DIR=<dir> also saves the 1080p page, named with BOXFORT_SHOTS_PREFIX ("before-", "after-").
 */
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { expect, test, type Locator, type Page } from "@playwright/test";
import { shape } from "@pounce/play-api/daily/box-fort/pieces";
import { createServer, type ViteDevServer } from "vite";

import type { BoxFortPublicState } from "@pounce/play-api/daily/box-fort/module";

const TV_STAGE = { width: 1792, height: 848 };
/** Read from 3 m away: no smaller than this, in CSS pixels on a 1080p page. */
const COUCH_PX = 28;

/** A rug from eight strings of eight: "#" is a box. */
const rugOf = (...rows: string[]) => rows.flatMap((row) => [...row].map((ch) => (ch === "#" ? 7 : 0)));
const piece = (id: string, tint: number) => ({ id, tint, cells: shape(id).cells });

const EARLY: BoxFortPublicState = {
  rug: rugOf(".#....##", "#...#...", "......##", "..#.....", "........", "..#.....", "........", "...###.."),
  set: 0,
  sets: 15,
  placed: [false, false, false],
  points: 5,
  combo: 0,
  lines: 0,
  over: null,
  pieces: [piece("five-v", 3), piece("tee-left", 5), piece("sq2", 2)],
};

/** The widest the score row gets: a big score, a combo and the last set. */
const LATE: BoxFortPublicState = {
  ...EARLY,
  rug: rugOf("##.##.##", "#......#", "..####..", "#......#", "##.##.##", "........", "#.#.#.#.", "........"),
  set: 14,
  points: 12345,
  combo: 12,
  lines: 40,
  placed: [true, false, false],
};

let vite: ViteDevServer;
let base = "";

test.beforeAll(async () => {
  vite = await createServer({
    root: fileURLToPath(new URL("..", import.meta.url)),
    logLevel: "error",
    server: { port: 5291, strictPort: false, hmr: false },
  });
  await vite.listen();
  base = vite.resolvedUrls!.local[0]!;
});

test.afterAll(async () => {
  await vite?.close();
});

test.skip(({ browserName, isMobile }) => browserName !== "chromium" || isMobile, "the browser TV is Chrome on a big screen");
test.use({ viewport: { width: 1920, height: 1080 } });

type Rect = { x: number; y: number; width: number; height: number };

async function rect(l: Locator): Promise<Rect> {
  const box = await l.boundingBox();
  expect(box, "drawn").not.toBeNull();
  return box!;
}

const overlaps = (a: Rect, b: Rect) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

async function show(page: Page, state: BoxFortPublicState, size: { width: number; height: number }) {
  await page.goto(`${base}e2e/fixtures/box-fort-watch.html`);
  await page.waitForFunction(() => "mount" in window);
  await page.evaluate(([s, w, h]) => (window as unknown as { mount: (...a: unknown[]) => void }).mount(s, w, h), [state, size.width, size.height] as const);
  await expect(page.getByTestId("boxfort-points")).toHaveText(String(state.points));
  await page.evaluate(() => document.fonts.ready);
  // The combo pops in from small: measure it once it has landed.
  await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== "running"));
}

/** The score row's parts, each on the stage and clear of the others and of the rug's fringe. */
async function scoreRow(page: Page, size: { width: number; height: number }) {
  const stage = await rect(page.locator("#stage"));
  expect(stage.width).toBe(size.width);
  const canvas = await rect(page.locator(".bf-rug"));
  // The rug's canvas reaches 0.6 spots past the rug, and its fringe 0.5: the fringe's top edge.
  const cell = canvas.width / 9.2;
  const fringeTop = canvas.y + 0.1 * cell;
  const parts = [page.getByTestId("boxfort-points"), page.locator(".bf-set"), page.getByTestId("boxfort-combo")];
  const rects: Rect[] = [];
  for (const part of parts) {
    if ((await part.count()) === 0) continue;
    const r = await rect(part);
    expect(r.x).toBeGreaterThanOrEqual(stage.x - 0.5);
    expect(r.y).toBeGreaterThanOrEqual(stage.y - 0.5);
    expect(r.x + r.width).toBeLessThanOrEqual(stage.x + stage.width + 0.5);
    expect(r.y + r.height, "clear of the rug").toBeLessThanOrEqual(fringeTop + 0.5);
    for (const other of rects) expect(overlaps(r, other), "the score row's parts apart").toBe(false);
    rects.push(r);
  }
  const [points, set] = rects as [Rect, Rect];
  const px = (l: Locator) => l.evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  const comboPx = (await parts[2]!.count()) ? await px(parts[2]!) : null;
  return { points, set, pointsPx: await px(parts[0]!), setPx: await px(parts[1]!), comboPx, cell };
}

test("on a TV's stage the score and the set count read from the couch, clear of the rug", async ({ page }) => {
  for (const state of [EARLY, LATE]) {
    await show(page, state, TV_STAGE);
    const row = await scoreRow(page, TV_STAGE);
    expect(row.points.height, `the score at ${state.points}`).toBeGreaterThanOrEqual(COUCH_PX);
    expect(row.set.height, "the set count").toBeGreaterThanOrEqual(COUCH_PX);
    expect(row.setPx, "the set count's text").toBeGreaterThanOrEqual(COUCH_PX);
    if (row.comboPx !== null) expect(row.comboPx, "the combo's text").toBeGreaterThanOrEqual(COUCH_PX);
    // The score is the biggest thing in the row.
    expect(row.pointsPx).toBeGreaterThan(row.setPx * 1.5);
    // The rug stays as big as it was.
    expect(row.cell).toBeGreaterThanOrEqual(70);
  }
});

test("in a smaller box the row shrinks with it and still fits", async ({ page }) => {
  const half = { width: 896, height: 424 };
  for (const state of [EARLY, LATE]) {
    await show(page, state, half);
    const row = await scoreRow(page, half);
    expect(row.setPx).toBeGreaterThanOrEqual(16);
    expect(row.setPx).toBeLessThan(COUCH_PX);
  }
});

test("shots", async ({ page }) => {
  const dir = process.env.BOXFORT_SHOTS_DIR;
  test.skip(!dir, "set BOXFORT_SHOTS_DIR to save shots");
  mkdirSync(dir!, { recursive: true });
  const prefix = process.env.BOXFORT_SHOTS_PREFIX ?? "";
  for (const [name, state] of [
    ["early", EARLY],
    ["late", LATE],
  ] as const) {
    await show(page, state, TV_STAGE);
    await page.screenshot({ path: join(dir!, `${prefix}web-watch-${name}-1080p.png`) });
  }
});
