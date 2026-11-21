import { fileURLToPath } from "node:url";

import { expect, test, type Page } from "@playwright/test";
import { SAMPLE } from "@pounce/play-api/daily/nine-lives/samples";
import { build } from "esbuild";


/**
 * Nine Lives' watch view on a 1080p TV. The TV gives a watch view its whole stage as a box of known
 * size (1792 by 848 at 1080p: `grid-template: minmax(0, 1fr) / minmax(0, 1fr)`, the view's root at
 * width and height 100%), so the quilt must fit inside it, square and centred, whichever side is
 * shorter. The watch view is bundled on its own (as the TV loads it, without the play screen) and
 * mounted in that box, with the player's fonts and colours.
 */

const ROOT = fileURLToPath(new URL("..", import.meta.url));

/** The watch module, the app's fonts and colours, and a `__mount` to draw it. */
async function bundle(): Promise<{ js: string; css: string }> {
  const out = await build({
    stdin: {
      contents: [
        'import "@fontsource/nunito/latin-900.css";',
        'import "@fontsource/nunito/latin-800.css";',
        'import "./src/styles.css";',
        'import { h, render } from "preact";',
        'import Watch from "./src/daily/nine-lives/watch";',
        "window.__mount = (el, props) => render(h(Watch, props), el);",
      ].join("\n"),
      resolveDir: ROOT,
      loader: "tsx",
    },
    bundle: true,
    write: false,
    outdir: "out",
    format: "iife",
    jsx: "automatic",
    jsxImportSource: "preact",
    loader: { ".woff2": "dataurl", ".woff": "dataurl", ".svg": "dataurl", ".png": "dataurl", ".webp": "dataurl" },
    logLevel: "silent",
  });
  const text = (ext: string) => out.outputFiles.find((f) => f.path.endsWith(ext))?.text ?? "";
  return { js: text(".js"), css: text(".css") };
}

/** A 1080p TV page whose stage is `w` by `h`, the watch view mounted in it at `state`. */
async function mount(page: Page, w: number, h: number, cells: number[]) {
  const { js, css } = await bundle();
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.setContent(`<!doctype html><html><head><style>${css}
    body { margin: 0; display: grid; place-items: center; height: 100vh; }
    #stage { display: grid; grid-template: minmax(0, 1fr) / minmax(0, 1fr); place-items: center; width: ${w}px; height: ${h}px; outline: 2px dashed #fff8; }
  </style></head><body><div id="stage"></div></body></html>`);
  await page.addScriptTag({ content: js });
  await page.evaluate(
    ([givens, cells]) => (window as unknown as { __mount: (el: Element, p: unknown) => void }).__mount(document.getElementById("stage")!, { puzzle: { givens }, state: { cells, hinted: [] } }),
    [SAMPLE.givens, cells] as const,
  );
  await page.locator(".nl-board").waitFor();
  await page.evaluate(() => document.fonts.ready);
}

/** Midway: the givens and every other open cell. */
const MIDWAY = SAMPLE.solution.map((d, i) => (SAMPLE.givens[i] !== 0 || i % 2 === 0 ? d : 0));

test.describe("Nine Lives on a TV", () => {
  for (const [w, h] of [
    [1792, 848],
    [848, 1792],
    [1200, 1200],
  ] as const) {
    test(`the quilt fits a ${w} by ${h} stage: square, centred, as large as the shorter side`, async ({ page }, info) => {
      test.skip(info.project.name !== "tv-chrome", "the TV project only");
      await mount(page, w, h, MIDWAY);
      await page.screenshot({ path: info.outputPath(`nine-lives-tv-${w}x${h}.png`) });
      const stage = (await page.locator("#stage").boundingBox())!;
      const board = (await page.locator(".nl-board").boundingBox())!;
      const short = Math.min(w, h);
      // The quilt and its lip (a drop shadow straight down) inside the stage, every side.
      const lip = await page.locator(".nl-board").evaluate((el) => parseFloat(getComputedStyle(el).boxShadow.match(/(-?[\d.]+)px (-?[\d.]+)px/)?.[2] ?? "0"));
      const bottom = board.y + board.height + lip;
      expect(board.x).toBeGreaterThanOrEqual(stage.x - 0.5);
      expect(board.y).toBeGreaterThanOrEqual(stage.y - 0.5);
      expect(board.x + board.width).toBeLessThanOrEqual(stage.x + stage.width + 0.5);
      expect(bottom, "the quilt's lip").toBeLessThanOrEqual(stage.y + stage.height + 0.5);
      // Square, filling the shorter side (with its lip), centred on both.
      expect(Math.abs(board.width - board.height)).toBeLessThanOrEqual(1);
      expect(board.width).toBeGreaterThanOrEqual(Math.min(w, h / 1.014) - 1);
      expect(Math.abs(board.x + board.width / 2 - (stage.x + stage.width / 2))).toBeLessThanOrEqual(1);
      expect(Math.abs((board.y + bottom) / 2 - (stage.y + stage.height / 2))).toBeLessThanOrEqual(1);
      // Every cell inside the quilt, and a given's digit big enough to read from across a room.
      const cells = await page.locator(".nl-board [data-cell]").evaluateAll((els) => els.map((el) => el.getBoundingClientRect().bottom));
      expect(cells).toHaveLength(81);
      expect(Math.max(...cells)).toBeLessThanOrEqual(board.y + board.height + 0.5);
      const digit = await page.locator(".nl-board .nl-given .nl-digit").first().evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
      console.log(`nine lives tv ${w}x${h}: board ${board.width.toFixed(0)}x${board.height.toFixed(0)}, digit ${digit}px`);
      expect(digit, "a given's digit, px at 1080p").toBeGreaterThanOrEqual(short / 20);
    });
  }
});
