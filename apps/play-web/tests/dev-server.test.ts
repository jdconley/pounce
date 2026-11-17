/**
 * e2e/dev-server.mjs, the supervisor that keeps the e2e `wrangler dev` up, run with a stand-in
 * for wrangler: a node script that starts a helper (as wrangler starts workerd), notes both pids,
 * and exits on its first run as wrangler 4.116 does when a connection drops.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { afterEach, describe, expect, test } from "vitest";

const SUPERVISOR = resolve(__dirname, "../e2e/dev-server.mjs");

// Run n (counted in `runs`): note its pid and its helper's, then exit after `exitMs` when it is a
// run that exits (every run, or only the first), else stay up.
const STAND_IN = `
const { appendFileSync, existsSync, readFileSync, writeFileSync } = require("node:fs");
const { spawn } = require("node:child_process");
const [dir, exitMs, which] = process.argv.slice(2);
const runs = existsSync(dir + "/runs") ? Number(readFileSync(dir + "/runs", "utf8")) + 1 : 1;
writeFileSync(dir + "/runs", String(runs));
const helper = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
appendFileSync(dir + "/pids", process.pid + " " + helper.pid + "\\n");
if (which === "all" || runs === 1) setTimeout(() => process.exit(3), Number(exitMs));
else setInterval(() => {}, 1000);
`;

let dir = "";
let supervisor: ChildProcess | null = null;

afterEach(async () => {
  // A test that failed part way: the supervisor stops what it started.
  const left = supervisor;
  if (left && left.exitCode === null && left.signalCode === null) {
    const gone = new Promise((done) => left.once("exit", done));
    left.kill("SIGTERM");
    await gone;
  }
  rmSync(dir, { recursive: true, force: true });
});

function launch(exitMs: number, which: "first" | "all", env: Record<string, string> = {}, stdin: "ignore" | "pipe" = "ignore") {
  dir = mkdtempSync(join(tmpdir(), "dev-server-test-"));
  writeFileSync(join(dir, "stand-in.cjs"), STAND_IN);
  const run = spawn(process.execPath, [SUPERVISOR, process.execPath, join(dir, "stand-in.cjs"), dir, String(exitMs), which], {
    stdio: [stdin, "pipe", "pipe"],
    env: { ...process.env, ...env },
  });
  let err = "";
  run.stderr?.on("data", (chunk: Buffer) => (err += chunk.toString()));
  const exited = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((done) => run.on("exit", (code, signal) => done({ code, signal })));
  supervisor = run;
  return { run, stderr: () => err, exited };
}

/** Each run's [stand-in pid, helper pid]. */
function pids(): number[][] {
  try {
    return readFileSync(join(dir, "pids"), "utf8")
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => line.split(" ").map(Number));
  } catch {
    return [];
  }
}

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function until(check: () => boolean, ms = 10_000): Promise<void> {
  const end = Date.now() + ms;
  while (!check()) {
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 50));
  }
}

describe("the e2e dev server supervisor", () => {
  test("restarts the server when it exits on its own, then a SIGTERM stops everything", async () => {
    const { run, stderr, exited } = launch(1000, "first");
    await until(() => pids().length === 2);
    expect(stderr()).toContain("exited (code 3); restarting (1 of 5)");
    const [first, second] = pids() as [number[], number[]];
    // The crashed run's helper went with it.
    await until(() => first.every((p) => !alive(p)));
    expect(second.every(alive)).toBe(true);

    run.kill("SIGTERM");
    expect(await exited).toEqual({ code: 0, signal: null });
    // No orphans: the running server and its helper are gone too.
    await until(() => second.every((p) => !alive(p)), 2000);
    expect(pids()).toHaveLength(2);
  });

  test("gives up after its restarts, with the server's exit code", async () => {
    const { stderr, exited } = launch(50, "all", { DEV_SERVER_RESTART_MS: "10", DEV_SERVER_MAX_RESTARTS: "2" });
    expect((await exited).code).toBe(3);
    expect(pids()).toHaveLength(3);
    expect(stderr()).toContain("restarted 2 times in a row already, giving up");
    await until(() => pids().flat().every((p) => !alive(p)), 2000);
  });

  test("only restarts in a row count: a run that stayed up starts the count again", async () => {
    // Each run is up 300 ms, longer than the 100 ms that counts as steady: it never gives up.
    const { run, stderr, exited } = launch(300, "all", { DEV_SERVER_RESTART_MS: "10", DEV_SERVER_MAX_RESTARTS: "2", DEV_SERVER_STEADY_MS: "100" });
    await until(() => pids().length >= 5);
    expect(stderr()).not.toContain("giving up");
    expect(stderr()).toContain("restarting (1 of 2)");
    expect(stderr()).not.toContain("restarting (2 of 2)");
    run.kill("SIGTERM");
    expect((await exited).code).toBe(0);
    await until(() => pids().flat().every((p) => !alive(p)), 2000);
  });

  test("a command that can't start at all gives up at once with 127", async () => {
    dir = mkdtempSync(join(tmpdir(), "dev-server-test-"));
    const started = Date.now();
    const run = spawn(process.execPath, [SUPERVISOR, join(dir, "no-such-server")], { stdio: ["ignore", "pipe", "pipe"] });
    supervisor = run;
    let err = "";
    run.stderr?.on("data", (chunk: Buffer) => (err += chunk.toString()));
    const code = await new Promise<number | null>((done) => run.on("exit", (c) => done(c)));
    expect(code).toBe(127);
    expect(err).toContain("couldn't start");
    expect(err).toContain("giving up");
    expect(err).not.toContain("restarting");
    expect(Date.now() - started).toBeLessThan(5000);
  });

  test("stops when the stdin pipe it was given closes (Playwright gone)", async () => {
    const { run, exited } = launch(1000, "first", {}, "pipe");
    await until(() => pids().length === 1);
    run.stdin?.end();
    expect((await exited).code).toBe(0);
    await until(() => pids().flat().every((p) => !alive(p)), 2000);
    expect(pids()).toHaveLength(1);
  });
});
