import { devices, expect, type Browser, type Page } from "@playwright/test";

import { newPlayer, ownAddress } from "./helpers";
import { TV_VIEWPORT, tvPage, type Tv } from "./tv-helpers";

/**
 * Purrtrait end to end: a TV page makes the table, phones join from the code it shows, and the
 * drawer's lines show on its easel. Everything runs on the Purrtrait server (playwright.config's
 * PURR_BASE), whose clock runs at the real speed.
 */
export const PURR = process.env.E2E_PURR_BASE ?? "http://127.0.0.1:8797";

/** A TV page on the Purrtrait server, at its home screen. */
export async function purrTv(browser: Browser, viewport = TV_VIEWPORT): Promise<Tv> {
  const context = await browser.newContext({ viewport, isMobile: false, hasTouch: false, baseURL: PURR });
  await ownAddress(context);
  const page = await tvPage(context);
  return { context, page, links: [] };
}

/** The TV makes a Purrtrait table from its poster; returns the table's code. */
export async function tvMakesPurrtrait(tv: Tv): Promise<string> {
  await tv.page.getByRole("button", { name: /^Purrtrait\s*2 to 10 players$/ }).click();
  const code = tv.page.locator(".tv-lobby .tv-code");
  await expect(code).toHaveText(/^[A-Z0-9]{5} [A-Z0-9]{3}$/);
  return ((await code.textContent()) ?? "").trim().slice(0, 5);
}

/** The URL the TV's join QR holds now. */
export async function joinLink(tv: Tv): Promise<string> {
  const qr = tv.page.locator(".tv-lobby .tv-qr[data-url]");
  await expect(qr).toBeVisible();
  return (await qr.getAttribute("data-url"))!;
}

/** A phone that scans the TV's code: first run, then the table, seated. */
export async function phoneScans(browser: Browser, tv: Tv, name: string, device = devices["Pixel 7"]) {
  // First run before the scan, so the key is fresh when the socket opens (a key lasts 30 to 60
  // seconds, and a slow machine's first run can take a good part of that).
  const phone = await newPlayer(browser, name, { path: "/play/", context: { ...device, baseURL: PURR } });
  await phone.page.goto(await joinLink(tv));
  await expect(phone.page).toHaveURL(/\/play\/t\/[A-Z0-9]{5}$/);
  await expect(phone.page.getByRole("button", { name: new RegExp(`^${name}, on this device`) })).toBeVisible();
  return phone;
}

/** Draws a stroke through `points` (shares of the easel) with the mouse or a finger. */
export async function drawStroke(page: Page, points: [number, number][], steps = 8): Promise<void> {
  const easel = page.locator("#purr-easel canvas.purr-live");
  const box = (await easel.boundingBox())!;
  const at = ([x, y]: [number, number]) => [box.x + box.width * x, box.y + box.height * y] as const;
  await page.mouse.move(...at(points[0]!));
  await page.mouse.down();
  for (const p of points.slice(1)) await page.mouse.move(...at(p), { steps });
  await page.mouse.up();
}

/**
 * The TV's easel as a coarse picture: both canvases composited, then each 8 x 8 block of device
 * pixels is ink (1) or paper (0). Two pictures of the same drawing match block for block.
 */
export async function easelPicture(page: Page): Promise<{ w: number; h: number; ink: number[] }> {
  return page.locator("#tv-easel").evaluate((el) => {
    const canvases = [...el.querySelectorAll("canvas")] as HTMLCanvasElement[];
    const w = canvases[0]!.width;
    const h = canvases[0]!.height;
    const c = new OffscreenCanvas(w, h);
    const x = c.getContext("2d")!;
    for (const k of canvases) x.drawImage(k, 0, 0);
    const d = x.getImageData(0, 0, w, h).data;
    const B = 8;
    const ink: number[] = [];
    for (let by = 0; by < Math.floor(h / B); by++)
      for (let bx = 0; bx < Math.floor(w / B); bx++) {
        let n = 0;
        for (let y = by * B; y < by * B + B; y++)
          for (let x2 = bx * B; x2 < bx * B + B; x2++) {
            const i = (y * w + x2) * 4;
            // Painted, and not white (white is the eraser, and the paper is the page behind).
            if (d[i + 3]! > 128 && d[i]! + d[i + 1]! + d[i + 2]! < 600) n += 1;
          }
        ink.push(n > 8 ? 1 : 0);
      }
    return { w, h, ink };
  });
}

/** How many blocks two pictures disagree on. */
export const differ = (a: { ink: number[] }, b: { ink: number[] }): number => a.ink.reduce((n, v, i) => n + (v !== b.ink[i] ? 1 : 0), 0);
export const inked = (a: { ink: number[] }): number => a.ink.reduce((n, v) => n + v, 0);

/** The pages that show the drawer's word cards (or the curtain before them) now. */
export async function drawerPage(pages: Page[]): Promise<Page> {
  let found: Page | null = null;
  await expect
    .poll(async () => {
      for (const p of pages) {
        if ((await p.locator("#purr-cards, .curtain, #purr-easel").count()) > 0) {
          found = p;
          return true;
        }
      }
      return false;
    }, { timeout: 30_000, message: "a phone shows the drawer's screen" })
    .toBe(true);
  return found!;
}

/** Lifts the curtain on a shared phone: holds its button until it fills. */
export async function liftCurtain(page: Page): Promise<void> {
  const hold = page.locator(".curtain button.hold");
  await hold.hover();
  await page.mouse.down();
  await page.waitForTimeout(900);
  await page.mouse.up();
  await expect(page.locator(".curtain")).toBeHidden();
}
