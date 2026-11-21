import { expect, test, type Page } from "@playwright/test";

import { closeAll, newPlayer, scan } from "./helpers";
import { openSniff, wrongWords } from "./sniff-helpers";

/**
 * Sniff in the browser's Dish, end to end, against the real Worker with `DAILY=on`: Home's treat,
 * guesses marked by the server, an unknown word that's never sent, and the end, solved and missed;
 * axe finds nothing on Sniff's screen.
 *
 * The answer never reaches the page before the end. The test works it out on its own
 * (`sniff-helpers.ts`), and checks that nothing the page loads carries it.
 */

/** Opens today's Sniff from Home, keeping every daily answer's body in `bodies`. */
async function openFromHome(page: Page, bodies: string[]) {
  page.on("response", (r) => {
    if (r.url().includes("/v1/daily/")) void r.text().then((t) => bodies.push(t), () => undefined);
  });
  const today = await openSniff(page, () => page.getByRole("button", { name: "Sniff Play" }).click());
  await expect(page).toHaveURL(/\/play\/daily\/sniff$/);
  return today;
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

test("Sniff is solved: marks from the server, an unknown word never sent, the answer kept back", async ({ browser }) => {
  const ada = await newPlayer(browser, "Ada");
  const { page } = ada;
  const bodies: string[] = [];
  const { answer } = await openFromHome(page, bodies);
  const [wrong] = wrongWords(answer, 1);

  await tapWord(page, wrong!);
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
  const { answer } = await openFromHome(page, bodies);
  const words = wrongWords(answer, 6);

  for (const [i, word] of words.entries()) {
    await tapWord(page, word);
    if (i < 5) await marked(page, i + 1);
  }
  await expect(page.getByRole("heading", { name: "Missed" })).toBeVisible();
  await closeAll(sam.context);
});
