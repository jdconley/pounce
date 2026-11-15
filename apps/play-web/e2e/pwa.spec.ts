import { expect, test } from "@playwright/test";

import { firstRun } from "./helpers";

/**
 * The installable app (web player design, "PWA"): Chrome finds nothing in the way of installing
 * it, and once the service worker has the shell the app opens with no network at all.
 */
test.use({ serviceWorkers: "allow" });

test("installs cleanly, and opens offline once visited", async ({ page, context, browserName }, info) => {
  test.skip(browserName !== "chromium" || info.project.name !== "laptop-chrome", "Chrome's installability check, on the laptop");
  await page.goto("/play/");
  const cdp = await context.newCDPSession(page);
  const manifest = await cdp.send("Page.getAppManifest");
  expect(manifest.errors).toEqual([]);
  const parsed = JSON.parse(manifest.data ?? "{}") as { display?: string; start_url?: string; icons?: { purpose?: string }[] };
  expect(parsed.display).toBe("standalone");
  expect(parsed.start_url).toBe("/play/");
  expect(parsed.icons?.some((i) => i.purpose === "maskable")).toBe(true);
  // The service worker takes over, then Chrome has nothing against installing.
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload();
  await expect.poll(() => page.evaluate(() => Boolean(navigator.serviceWorker.controller))).toBe(true);
  const install = await cdp.send("Page.getInstallabilityErrors");
  expect(install.installabilityErrors).toEqual([]);

  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole("heading", { name: "What year were you born?" })).toBeVisible();
  // Offline, the first run still works on the device; only the server waits.
  await firstRun(page, "Offline Olly");
  await context.setOffline(false);
});
