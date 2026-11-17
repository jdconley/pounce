#!/usr/bin/env node
/**
 * The e2e web server, kept up: runs the command it is given (playwright.config.ts passes its
 * `wrangler dev`) and, when that exits on its own, starts it again with the same arguments.
 *
 * Why: wrangler dev 4.116 exits when a connection from its proxy to the Worker drops ("Error
 * inside ProxyWorker", an empty `✘ [ERROR]`), and every test after that is refused. Later
 * wranglers retry those connections; until we're on one, this restarts it. Durable Object state
 * survives a restart because the command keeps its `--persist-to` directory.
 *
 *   node e2e/dev-server.mjs <command> [args...]
 *
 * - Each run of the command leads its own process group, so it and everything it starts (pnpm,
 *   wrangler, workerd) are stopped together, and a crashed run's leftovers go before the next.
 * - An exit we didn't ask for: one line on stderr, then a restart after DEV_SERVER_RESTART_MS
 *   (500), at most DEV_SERVER_MAX_RESTARTS (5) times; after that it exits with the command's code.
 * - SIGTERM, SIGINT or SIGHUP (Playwright stopping its webServer), or stdin closing when it is a
 *   pipe (Playwright itself gone): the command's group is stopped, then this exits.
 */
import { spawn } from "node:child_process";
import { fstatSync } from "node:fs";

const [command, ...args] = process.argv.slice(2);
if (!command) {
  console.error("usage: dev-server.mjs <command> [args...]");
  process.exit(2);
}

const RESTART_MS = Number(process.env.DEV_SERVER_RESTART_MS ?? 500);
const MAX_RESTARTS = Number(process.env.DEV_SERVER_MAX_RESTARTS ?? 5);
/** How long the command has to stop on SIGTERM before its group is killed. */
const STOP_MS = 5000;

const say = (line) => process.stderr.write(`[dev-server] ${line}\n`);
/** What the lines call the server: "wrangler dev" for the e2e's, else the command. */
const NAME = args.join(" ").includes("wrangler dev") ? "wrangler dev" : command;

let child = null;
let restarts = 0;
let stopping = false;
let restartTimer = null;

/** Signals the whole process group `pgid` leads; it may already be gone. */
function signalGroup(pgid, signal) {
  try {
    process.kill(-pgid, signal);
    return true;
  } catch {
    return false;
  }
}

function start() {
  restartTimer = null;
  const run = spawn(command, args, { stdio: ["ignore", "inherit", "inherit"], detached: true });
  child = run;
  run.on("error", (error) => say(`couldn't start ${command}: ${error.message}`));
  run.on("exit", (code, signal) => {
    // Whatever the run left behind (a workerd still holding the port) goes with it.
    if (run.pid) signalGroup(run.pid, "SIGKILL");
    if (child === run) child = null;
    if (stopping) return;
    const how = signal ? `signal ${signal}` : `code ${code}`;
    if (restarts >= MAX_RESTARTS) {
      say(`${NAME} exited (${how}); restarted ${restarts} times already, giving up`);
      process.exit(code ?? 1);
    }
    restarts += 1;
    say(`${NAME} exited (${how}); restarting (${restarts} of ${MAX_RESTARTS})`);
    restartTimer = setTimeout(start, RESTART_MS);
  });
}

function stop() {
  if (stopping) return;
  stopping = true;
  if (restartTimer) clearTimeout(restartTimer);
  const run = child;
  if (!run?.pid || run.exitCode !== null || run.signalCode !== null) process.exit(0);
  signalGroup(run.pid, "SIGTERM");
  const force = setTimeout(() => {
    signalGroup(run.pid, "SIGKILL");
    process.exit(0);
  }, STOP_MS);
  run.once("exit", () => {
    clearTimeout(force);
    signalGroup(run.pid, "SIGKILL");
    process.exit(0);
  });
}

for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(signal, stop);

// Playwright gives its webServer a stdin pipe: when that closes, Playwright is gone (even killed
// outright), and so is anyone to stop this, so it stops itself.
try {
  const stdin = fstatSync(0);
  if (stdin.isFIFO() || stdin.isSocket()) {
    process.stdin.on("end", stop);
    process.stdin.on("close", stop);
    process.stdin.resume();
  }
} catch {
  // No stdin at all.
}

start();
