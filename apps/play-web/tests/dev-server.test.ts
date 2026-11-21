/**
 * e2e/dev-server.mjs, the supervisor that keeps the e2e `wrangler dev` up, run with a stand-in
 * for wrangler: a node script that starts a helper (as wrangler starts workerd), notes both pids,
 * and exits on its first run as wrangler 4.116 did when a connection dropped; and, for the port it
 * holds, a stand-in HTTP server that takes `--port` and `--ip` as wrangler dev does.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { createRequire } from "node:module";
import { createServer } from "node:net";
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

  describe("holding its port", () => {
    // A stand-in HTTP server that takes `--port` and `--ip` as wrangler dev does: it listens after
    // `delayMs` (a server starting up), notes its pid per run, and answers every path with its run.
    const HTTP_STAND_IN = `
const { appendFileSync, existsSync, readFileSync, writeFileSync } = require("node:fs");
const { createServer } = require("node:http");
const argv = process.argv.slice(2);
const [dir, delayMs] = argv;
const port = Number(argv[argv.indexOf("--port") + 1]);
const ip = argv[argv.indexOf("--ip") + 1];
const runs = existsSync(dir + "/runs") ? Number(readFileSync(dir + "/runs", "utf8")) + 1 : 1;
writeFileSync(dir + "/runs", String(runs));
appendFileSync(dir + "/pids", process.pid + "\\n");
setTimeout(() => createServer((req, res) => res.end("run " + runs + " " + req.url)).listen(port, ip), Number(delayMs));
`;

    async function freePort(): Promise<number> {
      const server = createServer();
      await new Promise<void>((done) => server.listen(0, "127.0.0.1", done));
      const port = (server.address() as { port: number }).port;
      await new Promise((done) => server.close(done));
      return port;
    }

    /** One GET to the supervisor's port: the body, or the error (never retried). */
    function get(port: number, path: string): Promise<string> {
      return new Promise((done, fail) => {
        const req = httpRequest({ host: "127.0.0.1", port, path, agent: false }, (res) => {
          let body = "";
          res.on("data", (c: Buffer) => (body += c.toString()));
          res.on("end", () => done(body));
        });
        req.on("error", fail);
        req.end();
      });
    }

    async function launchHttp(delayMs: number) {
      dir = mkdtempSync(join(tmpdir(), "dev-server-test-"));
      writeFileSync(join(dir, "http-stand-in.cjs"), HTTP_STAND_IN);
      const port = await freePort();
      const run = spawn(process.execPath, [SUPERVISOR, process.execPath, join(dir, "http-stand-in.cjs"), dir, String(delayMs), "--port", String(port), "--ip", "127.0.0.1"], {
        stdio: ["ignore", "pipe", "pipe"],
        env: { ...process.env, DEV_SERVER_RESTART_MS: "50" },
      });
      let err = "";
      run.stderr?.on("data", (chunk: Buffer) => (err += chunk.toString()));
      supervisor = run;
      // Up once it holds the port (Playwright waits out the start the same way).
      await until(() => err.includes("holding 127.0.0.1:"));
      return { port, run, stderr: () => err };
    }

    test("answers a request made before the server is up, once it is", async () => {
      const { port } = await launchHttp(400);
      expect(await get(port, "/first")).toBe("run 1 /first");
    });

    test("a server killed mid-run costs no request: the next ones wait for the restart", async () => {
      const { port, stderr } = await launchHttp(200);
      expect(await get(port, "/a")).toBe("run 1 /a");
      for (let crash = 1; crash <= 3; crash++) {
        const pid = Number(pids().at(-1));
        process.kill(pid, "SIGKILL");
        // The instant after the crash, while the server is going and starting again: never refused.
        const during = await Promise.all(["/b", "/c", "/d", "/e"].map((path) => get(port, path)));
        expect(during).toEqual(["/b", "/c", "/d", "/e"].map((path) => `run ${crash + 1} ${path}`));
        expect(stderr()).toContain(`restarting (${crash} of 5)`);
      }
    });
  });

  test("the e2e wrangler keeps serving when one proxied request fails (patches/wrangler@4.116.0.patch)", () => {
    // wrangler 4.116 ended `wrangler dev` on one failed request to the Worker. The patch, or any
    // wrangler from 4.129.1 on, logs that request's failure and carries on; a wrangler without
    // either would bring the mid-run crashes back.
    const wrangler = createRequire(resolve(__dirname, "../../play-api/package.json")).resolve("wrangler/package.json");
    const cli = readFileSync(join(wrangler, "../wrangler-dist/cli.js"), "utf8");
    expect(cli).toContain("(the affected request failed; the dev server continues)");
  });
});
