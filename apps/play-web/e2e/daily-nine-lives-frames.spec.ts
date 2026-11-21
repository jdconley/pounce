import { expect, test } from "@playwright/test";

import { RECORDER, measureFrames } from "./frames";
import { closeAll, newPlayer } from "./helpers";
import { cell, fill, openToday, readBoard } from "./nine-lives-helpers";

/**
 * Nine Lives' frame gate (docs/main-thread.md): today's puzzle played to the end in laptop Chrome,
 * with notes, arrow keys and a hint. No long task, and p95 main-thread work per frame within one
 * 120 Hz frame, at the reference machine's speed.
 */

// Playwright's own trace snapshots lay the page out on every action: the harness's cost, not the game's.
test.use({ trace: "off" });

test("Nine Lives keeps every frame: no long task, p95 frame work within one 120 Hz frame", async ({ browser }, info) => {
  test.skip(info.project.name !== "laptop-chrome", "Chrome on the laptop; main-thread.spec gates the phone and the TV");
  const gus = await newPlayer(browser, "Gus");
  const { page } = gus;
  await page.addInitScript(RECORDER);
  await page.reload();
  const solution = await openToday(page);
  const r = await measureFrames(browser, page, async () => {
    await page.getByRole("button", { name: "Notes" }).click();
    await cell(page, (await readBoard(page)).find((c) => c.d === 0)!.i).click();
    for (const d of [1, 2, 3]) await page.keyboard.press(String(d));
    await page.getByRole("button", { name: "Notes on" }).click();
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowDown");
    await page.getByRole("button", { name: "Hint" }).click();
    await fill(page, solution, 60);
    await expect(page.getByRole("heading", { name: "Solved" })).toBeVisible();
    await page.waitForTimeout(1500);
  });
  console.log(`nine lives main thread: ${JSON.stringify(r)}`);
  await info.attach("nine-lives-main-thread.json", { body: JSON.stringify(r, null, 2), contentType: "application/json" });
  expect(r.frames, "frames traced").toBeGreaterThan(200);
  expect(r.long, "tasks over 50 ms on the rendering thread").toEqual([]);
  expect(r.p95FrameWorkMs, "p95 main-thread work per frame, ms").toBeLessThanOrEqual(1000 / 120);
  await closeAll(gus.context);
});
