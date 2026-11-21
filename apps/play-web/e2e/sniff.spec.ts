import { expect, test, type Page } from "@playwright/test";

import { answerFor } from "@pounce/play-api/daily/sniff/answer";
import { cycleKey } from "@pounce/play-api/daily/seed";

import { closeAll, newPlayer, scan } from "./helpers";

/**
 * Sniff in the browser's Dish, end to end, against the real Worker with `DAILY=on`: Home's treat,
 * guesses marked by the server, an unknown word that's never sent, and the end, solved and missed;
 * axe finds nothing on Sniff's screen.
 *
 * The answer never reaches the page before the end. The test works it out on its own, from the
 * run's token secret (`E2E_TOKEN_SECRET`, which `playwright.config.ts` hands the Worker), exactly
 * as the server does; nothing the page loads carries it.
 */
const SECRET = process.env.E2E_TOKEN_SECRET;

/** Allowed words with no letter twice, for guesses that aren't the answer. */
const WORDS = ["crane", "sloth", "pudgy", "witch", "femur", "balky", "dozen", "jumpy"];

/** Opens today's Sniff from Home; returns the date the server started it for. */
async function openSniff(page: Page, bodies: string[]): Promise<string> {
  page.on("response", (r) => {
    if (r.url().includes("/v1/daily/")) void r.text().then((t) => bodies.push(t), () => undefined);
  });
  const started = page.waitForResponse((r) => /\/v1\/daily\/sniff\/start(\?|$)/.test(r.url()) && r.ok());
  await page.getByRole("button", { name: "Sniff Play" }).click();
  await expect(page).toHaveURL(/\/play\/daily\/sniff$/);
  const start = (await (await started).json()) as { date: string };
  await expect(page.getByRole("group", { name: "Keyboard" })).toBeVisible();
  return start.date;
}

/** Taps a word on the on-screen keys and sends it. */
async function tapWord(page: Page, word: string) {
  const keys = page.getByRole("group", { name: "Keyboard" });
  for (const l of word.toUpperCase()) await keys.getByRole("button", { name: new RegExp(`^${l}(,|$)`) }).click();
  await keys.getByRole("button", { name: "Sniff" }).click();
}

/** Waits for try `n` (from 1) to come back with five marks. */
async function marked(page: Page, n: number) {
  await expect(page.getByRole("group", { name: `Try ${n}` }).locator(".sniff-tag[data-mark=spot], .sniff-tag[data-mark=near], .sniff-tag[data-mark=none]")).toHaveCount(5);
}

const answerOn = async (date: string) => {
  if (!SECRET) test.skip(true, "no E2E_TOKEN_SECRET: the server's secret is someone else's");
  return answerFor(await cycleKey(SECRET!, "sniff"), date);
};

test("Sniff is solved: marks from the server, an unknown word never sent, the answer kept back", async ({ browser }) => {
  const ada = await newPlayer(browser, "Ada");
  const { page } = ada;
  const bodies: string[] = [];
  const date = await openSniff(page, bodies);
  const answer = await answerOn(date);
  const wrong = WORDS.find((w) => w !== answer)!;

  await tapWord(page, wrong);
  await marked(page, 1);
  await scan(page, "Sniff");

  // An unknown word: a note, the row stays typed, nothing goes to the server.
  const sent = bodies.length;
  await page.keyboard.type("zzzzz");
  await page.keyboard.press("Enter");
  await expect(page.getByRole("status").filter({ hasText: "Not a word" })).toBeVisible();
  await expect(page.getByRole("group", { name: "Try 2" }).getByRole("img", { name: "Z" })).toHaveCount(5);
  for (let i = 0; i < 5; i++) await page.keyboard.press("Backspace");
  expect(bodies.length).toBe(sent);

  // Nothing the page has loaded so far carries the answer.
  for (const body of bodies) expect(body).not.toContain(`"${answer}"`);

  await page.keyboard.type(answer);
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
  await expect(page.locator(".dd-end").getByRole("button", { name: "Share" })).toBeVisible();
  await closeAll(ada.context);
});

test("Sniff is missed after six tries", async ({ browser }) => {
  const sam = await newPlayer(browser, "Sam");
  const { page } = sam;
  const bodies: string[] = [];
  const date = await openSniff(page, bodies);
  const answer = await answerOn(date);
  const words = WORDS.filter((w) => w !== answer).slice(0, 6);

  for (const [i, word] of words.entries()) {
    await tapWord(page, word);
    if (i < 5) await marked(page, i + 1);
  }
  await expect(page.getByRole("heading", { name: "Missed" })).toBeVisible();
  await closeAll(sam.context);
});
