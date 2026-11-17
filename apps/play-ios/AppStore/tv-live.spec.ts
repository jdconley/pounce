// Plays the Apple TV's home, lobby and game over for the App Store screenshots: the Debug PounceTV
// app on an Apple TV simulator is the TV, and browser phones (Playwright) link it, join, start and
// leave, against your own dev server. Writes PNGs to RAW (default AppStore/raw/tv).
// Not part of any suite; copy it into apps/play-web/ (it imports ../e2e) and run:
//   pnpm --filter @pounce/play-api exec wrangler dev --port 8820 --ip 127.0.0.1 --persist-to .wrangler/tv-shots \
//     --var TOKEN_SECRET:<random> --var GAMES:tiles --var LINK:on --var TV:on --var DEV_SPEED:5
//   TV_SIM=<udid> RAW=<dir> APP=<PounceTV.app> npx playwright test -c <a config with baseURL http://127.0.0.1:8820>
// Never port 4343. The home shot shows the link code of that dev server.
import { execFileSync, execSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { devices, expect, test, type Browser, type Page } from "@playwright/test";

import { newPlayer } from "../e2e/helpers";
import { controllerTurn, forfeit, startFromPhone, tilesTurn } from "../e2e/tv-helpers";

const SHOTS = process.env.RAW ?? join(process.cwd(), "../play-ios/AppStore/raw/tv");
const APP = process.env.APP!;
const BUNDLE = "com.conleychaos.play";
const TV4K = process.env.TV_SIM!;

const LOGS = join(process.env.TMPDIR ?? "/tmp", "tv-shots-logs");
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

const count = (tv: Tv, kind: string) => readFileSync(tv.err, "utf8").split("\n").filter((l) => l.startsWith(`[tv] ${kind} `)).length;

const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Holds the dev server's worker still (no frames either way) for `ms`: the TV loses the table. */
async function serverStall(ms: number, during: () => Promise<void>) {
  const pids = execSync(`lsof -nP -iTCP -sTCP:LISTEN | awk '$2 ~ /^[0-9]+$/ && $9 ~ /:8800$/ {print $2}' | sort -u`, { encoding: "utf8" }).trim().split("\n").filter(Boolean);
  // wrangler's own process, and the workerd it runs (its child).
  const all = new Set<string>(pids);
  for (const pid of pids) for (const c of execSync(`pgrep -P ${pid} || true`, { encoding: "utf8" }).trim().split("\n").filter(Boolean)) all.add(c);
  console.log("stalling", [...all].join(","));
  for (const p of all) execSync(`kill -STOP ${p}`);
  try {
    await pause(ms);
    await during();
  } finally {
    for (const p of all) execSync(`kill -CONT ${p}`);
  }
}

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

async function phone(browser: Browser, name: string, path: string, device = devices["Pixel 7"]) {
  return newPlayer(browser, name, { path, context: { ...device } });
}


test("store shots: home, lobby, game over", async ({ browser }) => {
  tvReset(TV4K);
  const tv = tvLaunch(TV4K);
  const [, linkURL] = await tvLine(tv, "link");
  await pause(2500);
  shot(tv, "home");
  const jo = await phone(browser, "Great Aunt Josephine", "/play/");
  await jo.page.goto(new URL(linkURL).pathname);
  await jo.page.getByRole("button", { name: "Play Cat Tower" }).click();
  await expect(jo.page).toHaveURL(/\/play\/t\/[A-Z0-9]{5}$/);
  const code = jo.page.url().split("/").at(-1)!;
  await tvLine(tv, "table");
  await expect(jo.page.locator(".lobby-seat.bot")).toBeVisible({ timeout: 8000 }).catch(() => undefined);
  await removeHouseCats(jo.page);
  const ben = await phone(browser, "Ben", `/play/j/${code}`, devices["iPhone 13"]);
  await expect(ben.page).toHaveURL(new RegExp(`/play/t/${code}$`));
  await addHouseCats(jo.page, 2);
  await pause(3000);
  shot(tv, "lobby");
  await removeHouseCats(jo.page);
  await addHouseCats(jo.page, 1);
  await startFromPhone(jo.page, ben.page);
  await pause(5000);
  shot(tv, "table-live");
  await forfeit(ben.page);
  await pause(1500);
  await forfeit(jo.page);
  await pause(9000);
  shot(tv, "game-over");
  await jo.context.close();
  await ben.context.close();
});
