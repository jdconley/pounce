import { expect, test, type Page } from "@playwright/test";

import { firstRun, ownAddress, standInServer } from "./helpers";

import type { RoomView, ServerMessage } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";

/**
 * Your own Cat Tower hand is never see-through, in any view or state: off turn, waiting to draw,
 * playing, picked, held in a drag, staged in a tray, as cards arrive and move, with reduced motion
 * too. Every frame, each of your cards' drawn opacity (its own and every box it is in) is sampled.
 */
const ME = "11111111-1111-4111-8111-111111111111";
const SHOTS = process.env.SHOTS;
const ada: RoomView["seats"][number] = { kind: "human", person: { id: ME, name: "Ada", cat: 1 }, yours: true, presence: "awake" };
const bo: RoomView["seats"][number] = { kind: "human", person: { id: "22222222-2222-4222-8222-222222222222", name: "Bo", cat: 5 }, yours: true, presence: "awake" };
const bot: RoomView["seats"][number] = { kind: "bot", yours: false, presence: null };
// 2s and 5s of three coats (level 1), a 10 and a 12.
const HAND = [1, 25, 49, 4, 28, 52, 9, 11];
const label = (id: number) => `${(id % 12) + 1}, ${["tabby", "tuxedo", "calico", "gray"][Math.floor(id / 24)]}`;

/** Samples, every frame, the faintest any of this player's hand cards is drawn. */
const SAMPLER = () => {
  const w = window as unknown as { __faintest: number; __frames: number };
  w.__faintest = 1;
  w.__frames = 0;
  const seen = (el: Element | null): number => {
    let o = 1;
    for (let e = el; e && e instanceof HTMLElement; e = e.parentElement) o *= Number(getComputedStyle(e).opacity);
    return o;
  };
  const tick = () => {
    for (const el of document.querySelectorAll(".card.mine .card-inner")) {
      w.__faintest = Math.min(w.__faintest, seen(el), seen(el.querySelector(".face")));
    }
    w.__frames += 1;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};
const faintest = async (page: Page) => {
  await expect.poll(() => page.evaluate(() => (window as unknown as { __frames: number }).__frames)).toBeGreaterThan(30);
  // Read, then start again for the next state.
  return page.evaluate(() => {
    const w = window as unknown as { __faintest: number; __frames: number };
    const seen = w.__faintest;
    w.__faintest = 1;
    w.__frames = 0;
    return seen;
  });
};

const game = (over: Partial<CatTowerView> = {}): CatTowerView => ({
  round: 1, dealer: 1, turn: 1, step: "draw", status: "playing", deckCount: 40, discardTop: 0, discardCount: 1, phase: [0, 0], scores: [0, 0],
  laid: [null, null], handCounts: [8, 10], hands: { 0: HAND }, pendingSkip: [false, false], winners: [], forfeited: [false, false], ...over,
});
const room = (g: CatTowerView, over: Partial<RoomView> = {}): RoomView => ({ code: "BCDFG", name: "Hands", status: "playing", youAreHost: true, seats: [ada, bot], game: g, ...over });

async function open(page: Page, r: RoomView) {
  const server = await standInServer(page);
  server.send({ t: "snapshot", protocol: 1, seq: 1, room: r });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(HAND.length);
  return server;
}

/** Off turn, our turn to draw, the draw, picking, staging, a drag, and the discard, each sampled. */
async function playThrough(page: Page, send: (m: ServerMessage) => void, over: Partial<RoomView>, shot: string) {
  const states: Record<string, number> = {};
  states["off turn"] = await faintest(page);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/hand-${shot}-off-turn.png` });
  send({ t: "event", seq: 2, event: { kind: "game", event: { kind: "turn", seat: 0 } } });
  send({ t: "snapshot", protocol: 1, seq: 2, room: room(game({ turn: 0 }), over) });
  await expect(page.locator("#deck:not([disabled])")).toBeVisible();
  states["waiting to draw"] = await faintest(page);
  send({ t: "event", seq: 3, event: { kind: "game", event: { kind: "drew", seat: 0, from: "deck", card: 60 } } });
  send({ t: "snapshot", protocol: 1, seq: 3, room: room(game({ turn: 0, step: "play", deckCount: 39, handCounts: [9, 10], hands: { 0: [...HAND, 60] } }), over) });
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(HAND.length + 1);
  // The hand as it makes room for the drawn card.
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/hand-${shot}-drawing.png` });
  states["a card drawn"] = await faintest(page);
  const ten = page.locator(`.card.mine .card-inner[aria-label="${label(9)}"]`);
  await ten.press("Enter");
  await expect(ten).toHaveAttribute("aria-pressed", "true");
  states["picked"] = await faintest(page);
  await ten.press("Enter");
  // Staged: the 2s into the first tray.
  for (const id of [1, 25, 49]) {
    const c = page.locator(`.card.mine .card-inner[aria-label="${label(id)}"]`);
    await page.waitForTimeout(300);
    await c.press("Enter");
    await expect(c).toHaveAttribute("aria-pressed", "true");
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const tray = page.locator(".tray").first();
    const at = await tray.evaluate((t) => {
      const r = t.getBoundingClientRect();
      for (let y = r.bottom - 4; y > r.top; y -= 6)
        for (let x = r.right - 4; x > r.left; x -= 6) {
          const hit = document.elementFromPoint(x, y);
          if (hit && t.contains(hit)) return { x, y };
        }
      return null;
    });
    await page.mouse.click(at!.x, at!.y);
  }
  await expect(page.locator(".tray").first()).toHaveAttribute("aria-label", /, 3 of 3/);
  states["staged in a tray"] = await faintest(page);
  // Held in a drag, over the rug.
  const b = (await page.locator(`.card.mine .card-inner[aria-label="${label(11)}"]`).boundingBox())!;
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2 - i * 25);
  await expect(page.locator(".card.mine.dragging")).toHaveCount(1);
  states["held in a drag"] = await faintest(page);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/hand-${shot}-drag.png` });
  await page.mouse.up();
  states["put back"] = await faintest(page);
  return states;
}

test.beforeEach(async ({ page, context }, info) => {
  test.skip(!["android-chrome", "iphone-safari", "laptop-chrome"].includes(info.project.name), "phones and the laptop");
  await ownAddress(context);
  await page.addInitScript(SAMPLER);
  await page.goto("/play/");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
});

for (const reduced of [false, true]) {
  test(`the full table${reduced ? ", reduced motion" : ""}: my hand is never see-through`, async ({ page }, info) => {
    if (reduced) await page.emulateMedia({ reducedMotion: "reduce" });
    const { send } = await open(page, room(game()));
    const states = await playThrough(page, send, {}, `${info.project.name}${reduced ? "-reduced" : ""}`);
    expect(states).toEqual(Object.fromEntries(Object.keys(states).map((k) => [k, 1])));
  });
}

test("on Cards at a TV table: my hand is never see-through", async ({ page }, info) => {
  test.skip(info.project.name === "laptop-chrome", "a phone at a TV table");
  const { send } = await open(page, room(game(), { screen: true }));
  await expect(page.locator(".ctl")).toBeVisible();
  const states: Record<string, number> = { "off turn": await faintest(page) };
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/hand-cards-${info.project.name}-off-turn.png` });
  send({ t: "event", seq: 2, event: { kind: "game", event: { kind: "turn", seat: 0 } } });
  send({ t: "snapshot", protocol: 1, seq: 2, room: room(game({ turn: 0 }), { screen: true }) });
  await expect(page.locator("#deck:not([disabled])")).toBeVisible();
  states["waiting to draw"] = await faintest(page);
  send({ t: "event", seq: 3, event: { kind: "game", event: { kind: "drew", seat: 0, from: "deck", card: 60 } } });
  send({ t: "snapshot", protocol: 1, seq: 3, room: room(game({ turn: 0, step: "play", deckCount: 39, handCounts: [9, 10], hands: { 0: [...HAND, 60] } }), { screen: true }) });
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(HAND.length + 1);
  states["a card drawn"] = await faintest(page);
  const b = (await page.locator(`.card.mine .card-inner[aria-label="${label(11)}"]`).boundingBox())!;
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2 - i * 25);
  states["held in a drag"] = await faintest(page);
  await page.mouse.up();
  expect(states).toEqual(Object.fromEntries(Object.keys(states).map((k) => [k, 1])));
});

test("pass and play, and a tablet: my hand is never see-through", async ({ page }, info) => {
  test.skip(info.project.name !== "laptop-chrome", "a tablet's size, set here");
  await page.setViewportSize({ width: 820, height: 1180 });
  // Two people on this device: the curtain, then Ada's hand.
  await open(page, { ...room(game({ turn: 0, step: "draw" })), seats: [ada, bo] }).catch(() => undefined);
  const hold = page.getByRole("button", { name: /Hold to see your hand/ });
  if (await hold.isVisible()) {
    const h = (await hold.boundingBox())!;
    await page.mouse.move(h.x + h.width / 2, h.y + h.height / 2);
    await page.mouse.down();
    await expect(page.locator(".card.mine .card-inner")).toHaveCount(HAND.length, { timeout: 5000 });
    await page.mouse.up();
  }
  await page.evaluate(() => ((window as unknown as { __faintest: number }).__faintest = 1));
  expect(await faintest(page)).toBe(1);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/hand-tablet-pass-and-play.png` });
});
