#!/usr/bin/env node
/**
 * Daily Dish cross-platform check: a logging proxy in front of the wrangler dev server. Every client (the
 * iPhone simulator, Playwright browsers, curl) talks to LISTEN; this forwards to TARGET and writes
 * each /v1/daily request and answer, with who sent it, to LOG as JSON lines. Socket upgrades pass
 * straight through.
 *
 *   node proxy.mjs <listen port> <target port> <log file>
 */
import { appendFileSync } from "node:fs";
import { createServer, request } from "node:http";
import { connect } from "node:net";

const [listen, target, log] = process.argv.slice(2);
const T = Number(target);

function who(req) {
  const ua = req.headers["user-agent"] ?? "";
  const client = req.headers["x-crosscheck-client"] ?? (/CFNetwork|Darwin|Pounce\//.test(ua) && !/Mozilla/.test(ua) ? "ios" : /Mozilla/.test(ua) ? "web" : "other");
  const auth = req.headers.authorization ?? "";
  const device = auth.split(".")[1] ?? null; // v1.<device id>.<mac>: the id only
  return { client, device, games: req.headers["x-pounce-games"] ?? null, ua: ua.slice(0, 80) };
}

const server = createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks);
    const headers = { ...req.headers, host: `127.0.0.1:${T}`, "accept-encoding": "identity" };
    const up = request({ host: "127.0.0.1", port: T, method: req.method, path: req.url, headers }, (ur) => {
      const out = [];
      ur.on("data", (c) => out.push(c));
      ur.on("end", () => {
        const answer = Buffer.concat(out);
        res.writeHead(ur.statusCode ?? 502, ur.headers);
        res.end(answer);
        if (req.url.startsWith("/v1/daily") || req.url.startsWith("/v1/screens/link") || req.url.startsWith("/v1/devices/me/tables")) {
          const parse = (b) => {
            if (!b.length) return null;
            try { return JSON.parse(b.toString()); } catch { return b.toString().slice(0, 300); }
          };
          appendFileSync(log, JSON.stringify({ at: Date.now(), ...who(req), method: req.method, url: req.url, status: ur.statusCode, req: parse(body), res: parse(answer) }) + "\n");
        }
      });
    });
    up.on("error", (e) => { res.writeHead(502); res.end(String(e)); });
    up.end(body);
  });
});

// Sockets: replay the upgrade request upstream and pipe both ways.
server.on("upgrade", (req, socket, head) => {
  const up = connect(T, "127.0.0.1", () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      lines.push(`${k}: ${k.toLowerCase() === "host" ? `127.0.0.1:${T}` : req.rawHeaders[i + 1]}`);
    }
    up.write(lines.join("\r\n") + "\r\n\r\n");
    if (head?.length) up.write(head);
    up.pipe(socket);
    socket.pipe(up);
    appendFileSync(log, JSON.stringify({ at: Date.now(), ...who(req), method: "WS", url: req.url }) + "\n");
  });
  up.on("error", () => socket.destroy());
  socket.on("error", () => up.destroy());
});

server.listen(Number(listen), "127.0.0.1", () => console.log(`proxy ${listen} -> ${T}, log ${log}`));
