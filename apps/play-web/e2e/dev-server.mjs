#!/usr/bin/env node
/**
 * The e2e web server, kept up: runs the command it is given (playwright.config.ts passes its
 * `wrangler dev`) and, when that exits on its own, starts it again with the same arguments.
 *
 * Why: wrangler dev 4.116 exited when one proxied request to the Worker failed ("Error inside
 * ProxyWorker", an empty `✘ [ERROR]`; patches/wrangler@4.116.0.patch now keeps it serving), and
 * any server can still crash. Durable Object state survives a restart because the command keeps
 * its `--persist-to` directory.
 *
 *   node e2e/dev-server.mjs <command> [args...]
 *
 * - The port is held here, so a restart is never a refused connection. When the command is given
 *   `--port <n>` (and `--ip <host>`, else 127.0.0.1), this listens on that port itself, runs the
 *   command on a free port of its own, and passes each connection through. Until a run is ready
 *   (DEV_SERVER_READY_PATH answers over HTTP, without it the port takes a connection), new
 *   connections wait, unread; then they go to that run. A request the run hadn't answered when it
 *   died waits for the next run too when it is safe to send again (GET, HEAD, OPTIONS: page loads,
 *   assets, socket upgrades); a crash costs only the answers in flight and other unanswered calls.
 * - Each run of the command leads its own process group, so it and everything it starts (pnpm,
 *   wrangler, workerd) are stopped together, and a crashed run's leftovers go before the next.
 * - An exit we didn't ask for: one line on stderr, then a restart after DEV_SERVER_RESTART_MS
 *   (500). At most DEV_SERVER_MAX_RESTARTS (5) in a row: a run that stayed up DEV_SERVER_STEADY_MS
 *   (60 s) starts the count again, so a crash now and then over a long run always recovers and a
 *   server that can't stay up stops; after that it exits with the command's code.
 * - A command that can't be started at all (not found, not executable): it says so and exits 127.
 * - SIGTERM, SIGINT or SIGHUP (Playwright stopping its webServer), or stdin closing when it is a
 *   pipe (Playwright itself gone): the command's group is stopped, then this exits.
 */
import { spawn } from "node:child_process";
import { fstatSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { connect, createServer } from "node:net";

const [command, ...args] = process.argv.slice(2);
if (!command) {
  console.error("usage: dev-server.mjs <command> [args...]");
  process.exit(2);
}

const RESTART_MS = Number(process.env.DEV_SERVER_RESTART_MS ?? 500);
const MAX_RESTARTS = Number(process.env.DEV_SERVER_MAX_RESTARTS ?? 5);
/** A run up this long was a good one: the restarts in a row count from zero again. */
const STEADY_MS = Number(process.env.DEV_SERVER_STEADY_MS ?? 60_000);
/** How long the command has to stop on SIGTERM before its group is killed. */
const STOP_MS = 5000;

const say = (line) => process.stderr.write(`[dev-server] ${line}\n`);
/** What the lines call the server: "wrangler dev" for the e2e's, else the command. */
const NAME = args.join(" ").includes("wrangler dev") ? "wrangler dev" : command;

let child = null;
let restarts = 0;
let stopping = false;
let restartTimer = null;

// Holding the port: where the command was told to listen, and where it listens instead.
const portAt = args.indexOf("--port");
const PUBLIC_PORT = portAt >= 0 ? Number(args[portAt + 1]) : null;
const ipAt = args.indexOf("--ip");
const HOST = ipAt >= 0 ? args[ipAt + 1] : "127.0.0.1";
const READY_PATH = process.env.DEV_SERVER_READY_PATH ?? null;
let innerPort = null;
/** The current run answers: connections go straight through. */
let ready = false;
/** Connections waiting, unread, for a run that is ready. */
const waiting = new Set();
let holder = null;

/** The command's arguments, with its port swapped for the inner one when holding. */
function runArgs() {
  if (PUBLIC_PORT === null) return args;
  const out = [...args];
  out[portAt + 1] = String(innerPort);
  return out;
}

function freePort() {
  return new Promise((done, fail) => {
    const probe = createServer();
    probe.once("error", fail);
    probe.listen(0, HOST, () => {
      const { port } = probe.address();
      probe.close(() => done(port));
    });
  });
}

/** Whether the run on the inner port answers: its ready path over HTTP, else a connection. */
function answers() {
  return new Promise((done) => {
    if (READY_PATH) {
      const req = httpRequest({ host: HOST, port: innerPort, path: READY_PATH, agent: false, timeout: 2000 }, (res) => {
        res.resume();
        done(res.statusCode !== undefined && res.statusCode < 500);
      });
      req.on("timeout", () => req.destroy());
      req.on("error", () => done(false));
      req.end();
    } else {
      const socket = connect(innerPort, HOST);
      socket.once("connect", () => {
        socket.destroy();
        done(true);
      });
      socket.once("error", () => done(false));
    }
  });
}

/** Watches `run` until it answers, then lets the waiting connections through. */
function awaitReady(run) {
  if (child !== run || ready || stopping) return;
  void answers().then((ok) => {
    if (child !== run || ready || stopping) return;
    if (!ok) {
      setTimeout(() => awaitReady(run), 100);
      return;
    }
    ready = true;
    for (const client of [...waiting]) passThrough(client);
  });
}

/** Requests safe to send again: the run that died can't have acted on them. */
const REPLAYABLE = /^(GET|HEAD|OPTIONS) /;

/**
 * One connection to the run on the inner port. Until the run answers it, what the client sent is
 * kept: if the run is gone before it answers (refused, or reset as it dies), a request that is
 * safe to repeat waits for the next run and goes to it again. Any other fails with its run.
 */
function passThrough(client) {
  waiting.delete(client);
  const upstream = connect(innerPort, HOST);
  const sent = [];
  let answered = false;
  let ended = false;
  const toUpstream = (chunk) => {
    if (!answered) sent.push(chunk);
    upstream.write(chunk);
  };
  const clientEnded = () => {
    ended = true;
    upstream.end();
  };
  upstream.once("connect", () => {
    client.on("data", toUpstream);
    client.on("end", clientEnded);
    client.resume();
  });
  upstream.on("data", (chunk) => {
    if (!answered) {
      answered = true;
      sent.length = 0;
    }
    client.write(chunk);
  });
  upstream.on("end", () => client.end());
  upstream.on("error", () => {});
  upstream.on("close", () => {
    client.off("data", toUpstream);
    client.off("end", clientEnded);
    if (client.destroyed) return;
    if (answered) return client.destroy();
    const request = Buffer.concat(sent);
    if (ended || (request.length > 0 && !REPLAYABLE.test(request.toString("latin1", 0, 8)))) return client.destroy();
    // The run is gone (or going) before it answered: this waits for the next one.
    client.pause();
    if (request.length > 0) client.unshift(request);
    ready = false;
    hold(client);
    if (child) awaitReady(child);
  });
  client.on("close", () => upstream.destroy());
}

function hold(client) {
  if (client.destroyed) return;
  if (ready) return passThrough(client);
  waiting.add(client);
}

function holdPort() {
  return new Promise((done) => {
    holder = createServer({ pauseOnConnect: true }, (client) => {
      client.on("error", () => {});
      client.once("close", () => waiting.delete(client));
      hold(client);
    });
    holder.once("error", (error) => {
      say(`couldn't listen on ${HOST}:${PUBLIC_PORT}: ${error.message}`);
      process.exit(1);
    });
    holder.listen(PUBLIC_PORT, HOST, () => {
      say(`holding ${HOST}:${PUBLIC_PORT}; ${NAME} runs on ${innerPort}`);
      done();
    });
  });
}

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
  const run = spawn(command, runArgs(), { stdio: ["ignore", "inherit", "inherit"], detached: true });
  const startedAt = Date.now();
  child = run;
  ready = false;
  if (PUBLIC_PORT !== null) awaitReady(run);
  run.on("error", (error) => {
    // Never started (no pid): no restart would do better, and Playwright shouldn't wait it out.
    if (run.pid === undefined) {
      say(`couldn't start ${command}: ${error.message}; giving up`);
      process.exit(127);
    }
    say(`${NAME}: ${error.message}`);
  });
  run.on("exit", (code, signal) => {
    // Whatever the run left behind (a workerd still holding the port) goes with it.
    if (run.pid) signalGroup(run.pid, "SIGKILL");
    if (child === run) {
      child = null;
      ready = false;
    }
    if (stopping) return;
    const how = signal ? `signal ${signal}` : `code ${code}`;
    if (Date.now() - startedAt >= STEADY_MS) restarts = 0;
    if (restarts >= MAX_RESTARTS) {
      say(`${NAME} exited (${how}); restarted ${restarts} times in a row already, giving up`);
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
  holder?.close();
  for (const client of waiting) client.destroy();
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

if (PUBLIC_PORT === null) start();
else {
  innerPort = await freePort();
  await holdPort();
  start();
}
