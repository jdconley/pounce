import { expect, type Page } from "@playwright/test";

import { tableCode } from "./helpers";

import type { ClientEvent } from "@pounce/play-api/tumble/wire";

/**
 * Playing Toy Tumble in a browser the way a person does: keys on a laptop, drags, taps and flicks
 * on a phone. What the box did is read off the wire (the page's own `tumble` batches), since the
 * box is drawn on a canvas. Every read here never waits on something that can vanish.
 */

/** Home's Play Toy Tumble: a new table, with the House Cat a first table gets, and `cats` in all. */
export async function tumbleTable(page: Page, cats = 1): Promise<string> {
  await page.getByRole("button", { name: "Play Toy Tumble" }).click();
  const code = await tableCode(page);
  await expect(page.locator(".lobby-seat.bot")).toHaveCount(1);
  for (let n = 1; n < cats; n++) {
    await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await expect(page.locator(".lobby-seat.bot")).toHaveCount(n + 1);
  }
  return code;
}

export type Wire = { sent: ClientEvent[]; batches: number; syncs: number; hits: number };

/** Records the `tumble` batches this page sends, and the syncs and hits it gets. */
export function watchWire(page: Page): Wire {
  const wire: Wire = { sent: [], batches: 0, syncs: 0, hits: 0 };
  page.on("websocket", (ws) => {
    ws.on("framesent", (f) => {
      const text = String(f.payload);
      if (!text.startsWith('{"t":"tumble"')) return;
      const m = JSON.parse(text) as { ev: ClientEvent[] };
      wire.batches++;
      wire.sent.push(...m.ev);
    });
    ws.on("framereceived", (f) => {
      const text = String(f.payload);
      if (text.startsWith('{"t":"tumbleSync"')) wire.syncs++;
      if (text.startsWith('{"t":"tumbleHit"')) wire.hits++;
    });
  });
  return wire;
}

export const setDowns = (w: Wire) => w.sent.filter((e) => e[0] === "l").length;

/** The page's own box is in play: drawn, and not out. */
export const playing = async (page: Page) => (await page.locator(".tt-table[data-live]").count()) > 0;

/** A few keys: a move or two, maybe a turn, then a drop. */
export async function keysTurn(page: Page, k: number): Promise<void> {
  const side = k % 3 === 0 ? "ArrowLeft" : k % 3 === 1 ? "ArrowRight" : null;
  for (let i = 0; side && i < (k % 4) + 1; i++) await page.keyboard.press(side);
  if (k % 2 === 0) await page.keyboard.press(k % 4 === 0 ? "ArrowUp" : "z");
  await page.keyboard.press("Space");
}

/** A few touches on the box: a sideways drag, a tap to turn, then a flick down to drop. */
export async function touchTurn(page: Page, k: number): Promise<void> {
  const box = await page.locator("#tt-box").boundingBox();
  if (!box) return;
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  const cell = box.width / 12.8;
  const dx = (k % 3) - 1;
  if (dx !== 0) {
    await page.mouse.move(cx, cy);
    await page.mouse.down();
    for (let i = 1; i <= 6; i++) await page.mouse.move(cx + dx * cell * 2.4 * (i / 6), cy + 2);
    await page.mouse.up();
  }
  if (k % 2 === 0) await page.mouse.click(cx, cy);
  // A flick: fast and down.
  await page.mouse.move(cx, cy - cell * 3);
  await page.mouse.down();
  await page.mouse.move(cx, cy, { steps: 2 });
  await page.mouse.up();
}

/** Plays until `done` (or the deadline), each page by keys or touch, as long as its box is in play. */
export async function playUntil(pages: { page: Page; how: "keys" | "touch" }[], done: () => Promise<boolean>, ms: number): Promise<void> {
  const deadline = Date.now() + ms;
  let k = 0;
  while (!(await done())) {
    if (Date.now() > deadline) throw new Error(`Toy Tumble didn't get there in ${ms / 1000} s`);
    let any = false;
    for (const p of pages) {
      if (!(await playing(p.page))) continue;
      any = true;
      if (p.how === "keys") await keysTurn(p.page, k++);
      else await touchTurn(p.page, k++);
    }
    await pages[0]!.page.waitForTimeout(any ? 120 : 300);
  }
}
