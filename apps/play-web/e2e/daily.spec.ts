import { expect, test, type Page } from "@playwright/test";
import { puzzleNumber } from "@pounce/play-api/daily/days";

import { closeAll, firstRun, newPlayer, ownAddress, scan } from "./helpers";
import { openTv, shownLink } from "./tv-helpers";

/**
 * The Daily Dish in the browser, end to end, against the server's own test game ("count to
 * 3 + level", `DAILY_TEST=on`): Home's Today row, the Dish, the host and its clock, the end, the
 * board and stats, share, resuming, giving up, and the board on a TV.
 */

/** Steps the test game to its end. */
async function countToTheEnd(page: Page) {
  const step = page.getByRole("button", { name: "Step" });
  await expect(page.getByTestId("test-count")).toHaveText(/^\d+ \/ \d+$/);
  while (await step.isEnabled()) await step.click();
}

/**
 * Opens a test run and gives its share title: "Test 12" on the 12th day from launch, "Test" on a day
 * before it. The number comes from the run's own date and the server's `LAUNCH`, never from today,
 * so this holds on any day, and the server's number has to match it.
 */
async function openTestRun(page: Page): Promise<string> {
  const started = page.waitForResponse((r) => r.url().includes("/v1/daily/test/start") && r.ok());
  await page.goto("/play/daily/test");
  const run = (await (await started).json()) as { date: string; number: number };
  const n = puzzleNumber(run.date);
  expect(run.number).toBe(n);
  return n >= 1 ? `Test ${n}` : "Test";
}

async function dismissTip(page: Page) {
  const tip = page.getByRole("button", { name: "Dismiss tip" });
  if (await tip.isVisible()) await tip.click();
}

test("the test game plays end to end: Home, the host, the end, the board and stats", async ({ browser }) => {
  const mia = await newPlayer(browser, "Mia");
  const { page } = mia;
  await expect(page.getByRole("button", { name: "Open the Dish" })).toBeVisible();
  await page.getByRole("button", { name: "Test Play" }).click();
  await expect(page).toHaveURL(/\/play\/daily\/test$/);
  await expect(page.getByRole("timer")).toHaveText(/^0:0\d$/);
  await countToTheEnd(page);

  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  await expect(page.getByText("1st today")).toBeVisible();
  await page.getByRole("button", { name: "Stats" }).click();
  const sheet = page.getByRole("dialog", { name: "Test stats" });
  await expect(sheet.getByText("Played")).toBeVisible();
  await expect(sheet.locator(".dd-fig").first()).toContainText("1");
  await sheet.getByRole("button", { name: "Done" }).click();
  await expect(sheet).toBeHidden();

  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await expect(page).toHaveURL(/\/play\/daily$/);
  await dismissTip(page);
  await expect(page.getByRole("button", { name: /^Test: 0:0\d\. Result$/ })).toBeVisible();
  const board = page.getByRole("tabpanel");
  await expect(board.getByText("Mia")).toBeVisible();
  await expect(board.getByText("4 pts")).toBeVisible();
  await page.getByRole("tab", { name: "Test" }).click();
  await expect(board.getByText(/^0:0\d$/)).toBeVisible();
  await scan(page, "the Dish");

  await page.getByRole("button", { name: "Home" }).click();
  await expect(page.getByRole("button", { name: /^Test 0:0\d$/ })).toBeVisible();
  // One game played: "All done" while the test game is the only one, else "1 of" the Dish's games.
  await expect(page.locator(".dd-done")).toHaveText(/^(All done|1 of \d+)$/);
  await closeAll(mia.context);
});

test("a run carries on after a reload, and Give up ends it", async ({ browser }) => {
  const sam = await newPlayer(browser, "Sam");
  const { page } = sam;
  await page.goto("/play/daily/test");
  const step = page.getByRole("button", { name: "Step" });
  await step.click();
  await step.click();
  await expect(page.getByTestId("test-count")).toHaveText(/^2 \//);
  // The moves go in their batch within a second; then the page goes.
  await page.waitForTimeout(1500);
  await page.reload();
  await expect(page.getByTestId("test-count")).toHaveText(/^2 \//);
  await scan(page, "the puzzle host");

  await page.getByRole("button", { name: "Give up" }).click();
  await page.getByRole("dialog", { name: "Give up?" }).getByRole("button", { name: "Give up" }).click();
  await expect(page.getByRole("heading", { name: "Gave up" })).toBeVisible();
  await page.locator(".dd-end").getByRole("button", { name: "Dish", exact: true }).click();
  await dismissTip(page);
  await page.getByRole("tab", { name: "Test" }).click();
  await expect(page.getByRole("tabpanel").getByText("Gave up")).toBeVisible();
  await closeAll(sam.context);
});

test("Share sends the card image, the words and the Dish's link", async ({ browser }) => {
  const ada = await newPlayer(browser, "Ada");
  const { page } = ada;
  await page.addInitScript(() => {
    const w = window as unknown as { __shared: unknown };
    Object.defineProperty(navigator, "canShare", { value: () => true, configurable: true });
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: async (d: ShareData) => {
        w.__shared = { text: d.text, url: d.url, files: (d.files ?? []).map((f) => ({ name: f.name, type: f.type, size: f.size })) };
      },
    });
  });
  const title = await openTestRun(page);
  await countToTheEnd(page);
  await page.getByRole("button", { name: "Share" }).click();
  const shared = (await expect
    .poll(() => page.evaluate(() => (window as unknown as { __shared?: unknown }).__shared ?? null))
    .not.toBeNull()
    .then(() => page.evaluate(() => (window as unknown as { __shared: unknown }).__shared))) as { text: string; url: string; files: { name: string; type: string; size: number }[] };
  expect(shared.text).toMatch(new RegExp(`^${title}: 0:0\\d$`));
  expect(shared.url).toBe("https://play.conleychaos.com/daily");
  expect(shared.files[0]?.type).toBe("image/png");
  expect(shared.files[0]?.size).toBeGreaterThan(5000);
  await closeAll(ada.context);
});

test("without Web Share, Share copies the words and the link", async ({ browser }) => {
  const bo = await newPlayer(browser, "Bo");
  const { page } = bo;
  await page.addInitScript(() => {
    const w = window as unknown as { __copied: string };
    Object.defineProperty(navigator, "share", { value: undefined, configurable: true });
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async (t: string) => void (w.__copied = t) }, configurable: true });
  });
  const title = await openTestRun(page);
  await countToTheEnd(page);
  await page.getByRole("button", { name: "Share" }).click();
  await expect(page.getByText("Copied")).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { __copied: string }).__copied)).toMatch(new RegExp(`^${title}: 0:0\\d https://play\\.conleychaos\\.com/daily$`));
  await closeAll(bo.context);
});

test("kittens play, but get no Share", async ({ browser }) => {
  // A kitten's name is made for them: the first run takes it as it comes.
  const context = await browser.newContext();
  await ownAddress(context);
  const page = await context.newPage();
  await page.goto("/play/");
  for (const d of String(new Date().getFullYear() - 8)) await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await expect(page.getByLabel("Your name")).toBeVisible();
  await page.getByRole("button", { name: "Done" }).click();
  await expect(page.getByRole("button", { name: "Open the Dish" })).toBeVisible();
  await page.goto("/play/daily/test");
  await countToTheEnd(page);
  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Stats" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Share" })).toHaveCount(0);
  await closeAll(context);
});

test("the board goes on a TV by its backup code, or from its QR", async ({ browser }, info) => {
  test.skip(info.project.name !== "laptop-chrome", "one browser is enough for the link");
  const tv = await openTv(browser);
  const jo = await newPlayer(browser, "Jo");
  const { page } = jo;
  await page.getByRole("button", { name: "Open the Dish" }).click();
  await dismissTip(page);
  await page.getByRole("button", { name: "Show board on TV" }).click();
  const { code } = await shownLink(tv);
  await page.getByLabel("TV code").fill(code);
  await page.getByRole("button", { name: "Show", exact: true }).click();
  await expect(page.getByText("On the TV")).toBeVisible();

  // A second TV's QR opens the TV-link page, which offers tonight's board.
  const tv2 = await openTv(browser);
  const { url } = await shownLink(tv2);
  await page.goto(new URL(url).pathname);
  await page.getByRole("button", { name: "Show tonight's board" }).click();
  await expect(page).toHaveURL(/\/play\/daily$/);
  await closeAll(tv.context, tv2.context, jo.context);
});

test("the Dish stays hidden while the server has it off", async ({ browser }) => {
  const off = await newPlayer(browser, "Off", { path: "/play/join" });
  const { page } = off;
  await page.route("**/v1/daily/**", (route) => route.fulfill({ status: 404, contentType: "application/json", body: '{"error":"not_found"}' }));
  await page.goto("/play/");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open the Dish" })).toHaveCount(0);
  await page.goto("/play/daily");
  await expect(page).toHaveURL(/\/play\/$/);
  await closeAll(off.context);
});

test("a slow first profile save still shows the Dish once it lands", async ({ browser }) => {
  // Home asks for the board as soon as a new player is named; until the server has their profile
  // it refuses (403). The Dish must come up when the save lands, not wait for a reload.
  const context = await browser.newContext();
  await ownAddress(context);
  const page = await context.newPage();
  let land: () => void = () => {};
  const held = new Promise<void>((done) => (land = done));
  await page.route("**/v1/devices/me/profile", async (route) => {
    if (route.request().method() === "PUT") await held;
    await route.continue();
  });
  const refused = page.waitForResponse((r) => r.url().includes("/v1/daily/board") && r.status() === 403);
  await page.goto("/play/");
  await firstRun(page, "Ivy");
  await refused;
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open the Dish" })).toHaveCount(0);
  land();
  await expect(page.getByRole("button", { name: "Open the Dish" })).toBeVisible();
  await closeAll(context);
});

type Box = { x: number; y: number; width: number; height: number };
const overlaps = (a: Box, b: Box) => a.x < b.x + b.width - 0.5 && b.x < a.x + a.width - 0.5 && a.y < b.y + b.height - 0.5 && b.y < a.y + a.height - 0.5;

async function box(page: Page, selector: string): Promise<Box> {
  const b = await page.locator(selector).first().boundingBox();
  expect(b, selector).not.toBeNull();
  return b!;
}

test("at the largest text nothing clips or overlaps: Home and its posters, the Dish's tip, a puzzle's bar", async ({ browser }) => {
  const lu = await newPlayer(browser, "Lu");
  const { page, context } = lu;
  // A TV shows the board, so the puzzle's bar carries the TV switch as well as Give up: the
  // server's board says so, and its socket stays quiet so nothing says otherwise.
  await page.route("**/v1/daily/board?*", async (route) => {
    const res = await route.fetch();
    await route.fulfill({ response: res, json: { ...(await res.json()), tvs: 1 } });
  });
  await page.routeWebSocket(/\/v1\/daily\/board\/ws/, () => {});
  // The browser's largest text size: every rem in the player doubles.
  await context.addInitScript(() => document.addEventListener("DOMContentLoaded", () => (document.documentElement.style.fontSize = "200%")));
  await page.reload();

  // Home: Practice and Join never sit over a game, and their words fit.
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();
  // Home starts at its top: nothing is centered up out of reach.
  expect((await box(page, ".home-top")).y, "Home's top bar on screen").toBeGreaterThanOrEqual(0);
  for (const name of ["Practice", "Join"]) {
    const button = page.getByRole("navigation", { name: "Start" }).getByRole("button", { name });
    const b = (await button.boundingBox())!;
    for (const other of await page.locator(".poster, .dd-tile").all()) expect(overlaps(b, (await other.boundingBox())!), `${name} over a game`).toBe(false);
    expect(await button.evaluate((e) => e.scrollWidth <= e.clientWidth + 1), `${name} fits`).toBe(true);
  }

  // Each game's poster: Play (or a TV game's "Starts on the TV") never covers its player count.
  for (const poster of await page.locator(".poster").all()) {
    const count = (await poster.locator(".players").boundingBox())!;
    const play = (await poster.locator(".poster-play, .poster-tv").first().boundingBox())!;
    expect(overlaps(count, play), "Play over the player count").toBe(false);
  }

  // The Dish: its first-visit tip points at the first card without hiding the board's heading.
  await page.getByRole("button", { name: "Open the Dish" }).click();
  const tip = page.locator(".tip[role=status]");
  await expect(tip).toBeVisible();
  await tip.evaluate((e) => Promise.all(e.getAnimations().map((a) => a.finished)));
  for (const target of ["#board-h", "#dish-tv"]) expect(overlaps(await box(page, ".tip[role=status]"), await box(page, target)), `tip over ${target}`).toBe(false);

  // A puzzle's bar, with the longest daily game's name in place of the test game's.
  await page.getByRole("button", { name: "Play Test" }).click();
  await expect(page.getByRole("switch", { name: "Show on TV" })).toBeVisible();
  const h1 = page.locator(".dd-play-title h1");
  await h1.evaluate((e) => (e.firstChild!.textContent = "Nine Lives "));
  expect(await h1.evaluate((e) => e.scrollWidth <= e.clientWidth + 1), "the name is whole").toBe(true);
  const title = await box(page, ".dd-play-title h1");
  expect(title.x >= 0 && title.x + title.width <= page.viewportSize()!.width, "the name is on screen").toBe(true);
  for (const other of [".dd-play-bar > :first-child", ".dd-play-actions"]) expect(overlaps(title, await box(page, other)), `the name under ${other}`).toBe(false);
  await closeAll(context);
});
