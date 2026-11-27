import { randomBytes } from "node:crypto";

import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end: the built web player served by the real Worker (`wrangler dev`, its own port and
 * its own state), driven in real browsers. Build first (`pnpm build`). Never the dev server on
 * 8787 or anyone's 4343: this one starts and stops its own.
 */
const PORT = Number(process.env.E2E_PORT ?? 8791);
export const BASE = process.env.E2E_BASE ?? `http://127.0.0.1:${PORT}`;
// A throwaway token secret for this run only. Kept in the environment so the workers, which load
// this file again, see the same one (Sniff's test works out today's word from it, server side).
const SECRET = (process.env.E2E_TOKEN_SECRET ??= randomBytes(32).toString("hex"));

/** CI plays Birdwatch's long games in a job of their own (E2E_BIRDWATCH=off in the main one). */
const BIRDWATCH_GAMES = process.env.E2E_BIRDWATCH === "off" ? [/birdwatch\.spec/] : [];

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
    // The TV's own tests (tv.spec) run once, on the TV, which seats its phones itself.
    { name: "android-chrome", use: { ...devices["Pixel 7"] }, testIgnore: [/alerts\.spec/, /tv\.spec/, /tv-board\.spec/, ...BIRDWATCH_GAMES] },
    { name: "iphone-safari", use: { ...devices["iPhone 13"] }, testIgnore: [/alerts\.spec/, /tv\.spec/, /tv-board\.spec/, /birdwatch\.spec/] },
    { name: "laptop-chrome", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } }, testIgnore: [/alerts\.spec/, /tv\.spec/, /tv-board\.spec/, ...BIRDWATCH_GAMES] },
    // Gecko and desktop WebKit play the two-browser tables only, to keep CI quick.
    { name: "laptop-firefox", testMatch: /tables\.spec/, testIgnore: [/tv\.spec/, /tv-board\.spec/], use: { ...devices["Desktop Firefox"], viewport: { width: 1440, height: 900 } } },
    { name: "laptop-safari", testMatch: /tables\.spec/, testIgnore: [/tv\.spec/, /tv-board\.spec/], use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } } },
    // Pounce on the TV: a 1080p TV page with phones (Pixel 7, iPhone 13) it seats in each test, and
    // the TV's frame gate.
    { name: "tv-chrome", testMatch: [/tv\.spec/, /tv-board\.spec/, /main-thread\.spec/], use: { ...devices["Desktop Chrome"], viewport: { width: 1920, height: 1080 } } },
    // Turn alerts need full Chromium in its headless mode: the lighter headless shell refuses notifications.
    {
      name: "laptop-chromium-alerts",
      testMatch: /alerts\.spec/,
      testIgnore: [/tv\.spec/, /tv-board\.spec/],
      use: { ...devices["Desktop Chrome"], channel: "chromium", permissions: ["notifications"], serviceWorkers: "allow" },
    },
  ],
  webServer: process.env.E2E_BASE
    ? undefined
    : {
        // Kept up by e2e/dev-server.mjs: it holds the port, and restarts a wrangler dev that exits
        // with the same arguments (and the same state), so a crash never refuses a connection.
        command: `node e2e/dev-server.mjs pnpm --filter @pounce/play-api exec wrangler dev --port ${PORT} --ip 127.0.0.1 --persist-to .wrangler/e2e-${PORT}-${Date.now()} --var TOKEN_SECRET:${SECRET} --var GAMES:tiles,birdwatch,tumble --var LINK:on --var TV:on --var DAILY:on --var DAILY_TEST:on --var DEV_SPEED:20`,
        url: `${BASE}/healthz`,
        // The supervisor holds the port through a restart and lets connections through once the
        // new run answers this.
        env: { DEV_SERVER_READY_PATH: "/healthz" },
        reuseExistingServer: false,
        timeout: 120_000,
        stdout: "ignore",
        stderr: "pipe",
        // A SIGTERM first, so the supervisor stops its wrangler (its own process group) too.
        gracefulShutdown: { signal: "SIGTERM", timeout: 10_000 },
      },
});
