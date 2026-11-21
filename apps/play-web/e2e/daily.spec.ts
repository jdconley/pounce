import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer, ownAddress, scan } from "./helpers";
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
  // One puzzle played: "All done" when it is the Dish's only one, else "1 of" however many it has.
  const games = await page.locator(".dd-tile").count();
  await expect(page.locator(".dd-done")).toHaveText(games === 1 ? "All done" : `1 of ${games}`);
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
  await page.goto("/play/daily/test");
  await countToTheEnd(page);
  await page.getByRole("button", { name: "Share" }).click();
  const shared = (await expect
    .poll(() => page.evaluate(() => (window as unknown as { __shared?: unknown }).__shared ?? null))
    .not.toBeNull()
    .then(() => page.evaluate(() => (window as unknown as { __shared: unknown }).__shared))) as { text: string; url: string; files: { name: string; type: string; size: number }[] };
  expect(shared.text).toMatch(/^Test: 0:0\d$/);
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
  await page.goto("/play/daily/test");
  await countToTheEnd(page);
  await page.getByRole("button", { name: "Share" }).click();
  await expect(page.getByText("Copied")).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { __copied: string }).__copied)).toMatch(/^Test: 0:0\d https:\/\/play\.conleychaos\.com\/daily$/);
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
