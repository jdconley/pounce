import { randomBytes } from "node:crypto";

import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end: the built web player served by the real Worker (`wrangler dev`, its own port and
 * its own state), driven in real browsers. Build first (`pnpm build`). Never the dev server on
 * 8787 or anyone's 4343: this one starts and stops its own.
 */
const PORT = Number(process.env.E2E_PORT ?? 8791);
export const BASE = process.env.E2E_BASE ?? `http://127.0.0.1:${PORT}`;
// A throwaway token secret for this run only.
const SECRET = randomBytes(32).toString("hex");

export default defineConfig({
  testDir: "e2e",
  timeout: 180_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: { baseURL: BASE, trace: "retain-on-failure", serviceWorkers: "block" },
  projects: [
    { name: "android-chrome", use: { ...devices["Pixel 7"] }, testIgnore: /alerts\.spec/ },
    { name: "iphone-safari", use: { ...devices["iPhone 13"] }, testIgnore: /alerts\.spec/ },
    { name: "laptop-chrome", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } }, testIgnore: /alerts\.spec/ },
    // Gecko and desktop WebKit play the two-browser tables only, to keep CI quick.
    { name: "laptop-firefox", testMatch: /tables\.spec/, use: { ...devices["Desktop Firefox"], viewport: { width: 1440, height: 900 } } },
    { name: "laptop-safari", testMatch: /tables\.spec/, use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } } },
    // Turn alerts need full Chromium in its headless mode: the lighter headless shell refuses notifications.
    {
      name: "laptop-chromium-alerts",
      testMatch: /alerts\.spec/,
      use: { ...devices["Desktop Chrome"], channel: "chromium", permissions: ["notifications"], serviceWorkers: "allow" },
    },
  ],
  webServer: process.env.E2E_BASE
    ? undefined
    : {
        command: `pnpm --filter @pounce/play-api exec wrangler dev --port ${PORT} --ip 127.0.0.1 --persist-to .wrangler/e2e-${PORT}-${Date.now()} --var TOKEN_SECRET:${SECRET} --var GAMES:tiles --var LINK:on --var DEV_SPEED:20`,
        url: `${BASE}/healthz`,
        reuseExistingServer: false,
        timeout: 120_000,
        stdout: "ignore",
        stderr: "pipe",
      },
});
