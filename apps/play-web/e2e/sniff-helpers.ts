import { expect, type Page } from "@playwright/test";
import { cycleKey } from "@pounce/play-api/daily/seed";
import { answerFor } from "@pounce/play-api/daily/sniff/answer";

/**
 * Sniff's answer stays on the server until a run ends, so a test that has to keep a run going (or
 * end it) works out today's word itself: from the run's token secret (`E2E_TOKEN_SECRET`, which
 * `playwright.config.ts` hands the Worker) and the date the server started the run for, exactly as
 * the server does. Nothing the page loads carries it.
 */

/** Allowed words with no letter twice, for guesses that aren't the answer. */
const WORDS = ["crane", "sloth", "pudgy", "witch", "femur", "balky", "dozen", "jumpy"];

/** Runs `open` (a tap that starts today's Sniff) and returns the run's date and its answer. */
export async function openSniff(page: Page, open: () => Promise<void>): Promise<{ date: string; answer: string }> {
  const secret = process.env.E2E_TOKEN_SECRET;
  if (!secret) throw new Error("no E2E_TOKEN_SECRET: set it to the server's TOKEN_SECRET");
  const started = page.waitForResponse((r) => /\/v1\/daily\/sniff\/start(\?|$)/.test(r.url()) && r.ok());
  await open();
  const { date } = (await (await started).json()) as { date: string };
  await expect(page.getByRole("group", { name: "Keyboard" })).toBeVisible();
  return { date, answer: answerFor(await cycleKey(secret, "sniff"), date) };
}

/** `n` allowed words that aren't `answer`: guesses that keep the run going. */
export function wrongWords(answer: string, n: number): string[] {
  return WORDS.filter((w) => w !== answer).slice(0, n);
}
