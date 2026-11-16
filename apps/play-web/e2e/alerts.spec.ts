import { expect, test } from "@playwright/test";

/**
 * Turn alerts (web player design, "Web Push"): a push delivered to the service worker shows as a
 * notification naming the table. Runs in its own project (playwright.config.ts): full Chromium.
 */
test("a turn alert pushed to the service worker shows as a notification for its table", async ({ page, context }) => {
  await page.goto("/play/");
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  const cdp = await context.newCDPSession(page);
  const registration = new Promise<string>((resolve) => {
    cdp.on("ServiceWorker.workerRegistrationUpdated", (e) => {
      const reg = e.registrations.find((r) => r.scopeURL.endsWith("/play/"));
      if (reg) resolve(reg.registrationId);
    });
  });
  await cdp.send("ServiceWorker.enable");
  const registrationId = await registration;
  const origin = new URL(page.url()).origin;
  await cdp.send("ServiceWorker.deliverPushMessage", {
    origin,
    registrationId,
    data: JSON.stringify({ title: "The Sleepy Sardines", body: "Your move.", code: "BCDFG", tag: "move:BCDFG" }),
  });
  await expect
    .poll(() => page.evaluate(async () => (await (await navigator.serviceWorker.ready).getNotifications()).map((n) => [n.title, n.body, n.tag])))
    .toEqual([["The Sleepy Sardines", "Your move.", "move:BCDFG"]]);
});
