#!/usr/bin/env node
/**
 * Daily Dish cross-platform check: a logging proxy in front of the wrangler dev server. Every client (the
 * iPhone simulator, Playwright browsers, curl) talks to LISTEN; this forwards to TARGET and writes
 * each /v1/daily and /v1/screens request and answer, with who sent it, to LOG as JSON lines. Sockets
 * pass through uncompressed, and each JSON message a board socket is sent (a TV's watch frames among
 * them) is logged too.
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
  const app = /CFNetwork|Darwin|Pounce/.test(ua) && !/Mozilla/.test(ua);
  const client = req.headers["x-crosscheck-client"] ?? (app ? (/PounceTV|tvOS|AppleTV/i.test(ua) ? "appletv" : "ios") : /Mozilla/.test(ua) ? "web" : "other");
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
        if (req.url.startsWith("/v1/daily") || req.url.startsWith("/v1/screens") || req.url.startsWith("/v1/devices/me/tables")) {
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

/**
 * Reads the server's side of a socket: after the HTTP 101 head, unmasked frames. Logs each whole
 * text frame that is JSON (no compression: the upgrade is sent on without its extensions).
 */
function watchFrames(req) {
  let buf = Buffer.alloc(0);
  let open = false;
  const tag = { ...who(req), url: req.url.replace(/(board=)[^&]+/, "$1…") };
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    if (!open) {
      const end = buf.indexOf("\r\n\r\n");
      if (end < 0) return;
      buf = buf.subarray(end + 4);
      open = true;
    }
    for (;;) {
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0;
      const op = buf[0] & 0x0f;
      let len = buf[1] & 0x7f;
      let at = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        at = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        at = 10;
      }
      if (buf[1] & 0x80) at += 4;
      if (buf.length < at + len) return;
      const payload = buf.subarray(at, at + len);
      buf = buf.subarray(at + len);
      if (fin && op === 1) {
        try {
          const msg = JSON.parse(payload.toString());
          if (msg.t !== "pong") appendFileSync(log, JSON.stringify({ at: Date.now(), ...tag, method: "WSMSG", msg }) + "\n");
        } catch {
          // not JSON: skip
        }
      }
    }
  };
}

// Sockets: replay the upgrade request upstream, without compression, and pipe both ways.
server.on("upgrade", (req, socket, head) => {
  const up = connect(T, "127.0.0.1", () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      if (k.toLowerCase() === "sec-websocket-extensions") continue;
      lines.push(`${k}: ${k.toLowerCase() === "host" ? `127.0.0.1:${T}` : req.rawHeaders[i + 1]}`);
    }
    up.write(lines.join("\r\n") + "\r\n\r\n");
    if (head?.length) up.write(head);
    up.pipe(socket);
    socket.pipe(up);
    if (req.url.startsWith("/v1/daily/board/ws")) up.on("data", watchFrames(req));
    appendFileSync(log, JSON.stringify({ at: Date.now(), ...who(req), method: "WS", url: req.url.replace(/(board=)[^&]+/, "$1…") }) + "\n");
  });
  up.on("error", () => socket.destroy());
  socket.on("error", () => up.destroy());
});

server.listen(Number(listen), "127.0.0.1", () => console.log(`proxy ${listen} -> ${T}, log ${log}`));
