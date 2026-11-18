// Plays the Apple TV's home and lobby for the App Store screenshots: the Debug PounceTV app on an
// Apple TV simulator is the TV, and browser phones (Playwright) link it and join, against your own
// dev server. Writes PNGs to RAW (default apps/play-ios/AppStore/raw/tv). Not part of any suite.
// Run from the repo root, never on port 4343:
//   pnpm --filter @pounce/play-web build        # the web player, into apps/play-api/public/play
//   cd apps/play-web && cp ../play-ios/AppStore/tv-live.spec.ts e2e/tv-live.spec.ts
//   (cd ../play-api && pnpm exec wrangler dev --port 8820 --ip 127.0.0.1 --persist-to .wrangler/tv-shots \
//     --var TOKEN_SECRET:$(openssl rand -hex 32) --var GAMES:tiles --var LINK:on --var TV:on --var DEV_SPEED:5) &
//   E2E_BASE=http://127.0.0.1:8820 TV_SIM=<udid> APP=<path to PounceTV.app> \
//     npx playwright test e2e/tv-live.spec.ts --project=laptop-chrome
//   rm e2e/tv-live.spec.ts    # then stop wrangler and delete .wrangler/tv-shots
// The home shot shows the link code of that dev server.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { devices, expect, test, type Browser, type Page } from "@playwright/test";

import { ownAddress } from "./helpers";

const SHOTS = process.env.RAW ?? join(process.cwd(), "../play-ios/AppStore/raw/tv");
const APP = process.env.APP!;
const BUNDLE = "com.conleychaos.play";
const TV4K = process.env.TV_SIM!;

// The app writes its `[tv] link` lines to a file here: not /tmp, which the simulator will not write to.
const LOGS = join(process.cwd(), "../play-ios/build/tv-shots-logs");
mkdirSync(SHOTS, { recursive: true });
mkdirSync(LOGS, { recursive: true });

type Tv = { sim: string; err: string };

function simctl(...args: string[]) {
  return execFileSync("xcrun", ["simctl", ...args], { encoding: "utf8", env: { ...process.env, SIMCTL_CHILD_POUNCE_API_BASE_URL: "http://127.0.0.1:8820" } });
}

/** A TV with nothing kept: the app installed afresh. */
function tvReset(sim: string) {
  try { simctl("terminate", sim, BUNDLE); } catch { /* not running */ }
  try { simctl("uninstall", sim, BUNDLE); } catch { /* not installed */ }
  simctl("install", sim, APP);
}

function tvLaunch(sim: string, args: string[] = []): Tv {
  const err = join(LOGS, `tv-${sim.slice(0, 4)}-${Date.now()}.log`);
  writeFileSync(err, "");
  try { simctl("terminate", sim, BUNDLE); } catch { /* not running */ }
  simctl("launch", `--stderr=${err}`, `--stdout=${err}.out`, sim, BUNDLE, ...args);
  return { sim, err };
}

function shot(tv: Tv | string, name: string) {
  const sim = typeof tv === "string" ? tv : tv.sim;
  simctl("io", sim, "screenshot", join(SHOTS, `${name}.png`));
  console.log("shot", name);
}

/** The last `[tv] <kind> ...` line's words. */
async function tvLine(tv: Tv, kind: "link" | "table", after = 0): Promise<string[]> {
  let found: string[] | null = null;
  await expect.poll(() => {
    const lines = readFileSync(tv.err, "utf8").split("\n").filter((l) => l.startsWith(`[tv] ${kind} `));
    if (lines.length <= after) return false;
    found = lines.at(-1)!.split(" ").slice(2);
    return true;
  }, { timeout: 30_000, message: `the TV's ${kind}` }).toBe(true);
  return found!;
}

const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function addHouseCats(page: Page, n: number) {
  for (let i = 0; i < n; i++) {
    await page.locator("#add-bar").getByRole("button", { name: "House Cat" }).click();
    await pause(400);
  }
}

async function removeHouseCats(page: Page) {
  for (let i = 0; i < 6; i++) {
    const cat = page.locator(".lobby-seat.bot").first();
    if (!(await cat.isVisible().catch(() => false))) return;
    await cat.click();
    await page.getByRole("button", { name: "Remove House Cat" }).click();
    await pause(400);
  }
}

/** A new player in a browser of their own: the age check, a name and the cat at `cat` (0 to 7). */
async function phone(browser: Browser, name: string, path: string, cat: number, device = devices["Pixel 7"]) {
  const context = await browser.newContext({ ...device });
  await ownAddress(context);
  const page = await context.newPage();
  await page.goto(path);
  await expect(page.getByRole("heading", { name: "What year were you born?" })).toBeVisible();
  for (const d of "1985") await page.getByRole("button", { name: d, exact: true }).click();
  await page.getByRole("button", { name: "Done" }).click();
  await page.getByLabel("Your name").fill(name);
  await page.getByRole("radiogroup", { name: "Your cat" }).getByRole("radio").nth(cat).click();
  await page.getByRole("button", { name: "Done" }).click();
  return { context, page };
}

test("store shots: home and lobby", async ({ browser }) => {
  tvReset(TV4K);
  const tv = tvLaunch(TV4K);
  const [, linkURL] = await tvLine(tv, "link");
  await pause(2500);
  shot(tv, "home");
  // Great Aunt Josephine scans the TV's code and makes a Cat Tower table on it.
  const jo = await phone(browser, "Great Aunt Josephine", "/play/", 0);
  await jo.page.goto(new URL(linkURL).pathname);
  await jo.page.getByRole("button", { name: "Play Cat Tower" }).click();
  await expect(jo.page).toHaveURL(/\/play\/t\/[A-Z0-9]{5}$/);
  const code = jo.page.url().split("/").at(-1)!;
  await tvLine(tv, "table");
  // A first table gets a House Cat a moment after its phone sits: take it off. Open three seats
  // (a House Cat each), then three more people join, each with a different cat, and take them.
  await expect(jo.page.locator(".lobby-seat.bot")).toBeVisible({ timeout: 8000 }).catch(() => undefined);
  await removeHouseCats(jo.page);
  await addHouseCats(jo.page, 3);
  const others = [
    await phone(browser, "Ben", `/play/j/${code}`, 2, devices["iPhone 13"]),
    await phone(browser, "Kiki", `/play/j/${code}`, 4),
    await phone(browser, "Theo", `/play/j/${code}`, 6, devices["iPhone 13"]),
  ];
  for (const o of others) await expect(o.page).toHaveURL(new RegExp(`/play/t/${code}$`));
  await expect(jo.page.locator(".lobby-seat.human")).toHaveCount(4, { timeout: 15_000 });
  await pause(4000);
  shot(tv, "lobby");
  for (const o of [jo, ...others]) await o.context.close();
});
