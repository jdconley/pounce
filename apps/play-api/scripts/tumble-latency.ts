/**
 * Toy Tumble over a real network (spec §6.7, §9.5). Opens one table on a deployed (or local)
 * Worker with N scripted players, all run from this machine, plays for `--seconds`, and reports,
 * as p50 / p95 / max in ms:
 * - `rtt`: a ping to the room and back;
 * - `relay`: a player's set-down sent, to another player hearing it relayed (what a TV or a
 *   mini box waits);
 * - `hit`: a set-down that sends junk, or a trick used, to its target hearing the hit.
 * Every client shares this machine's clock, so no clock alignment is needed: each number is two
 * trips through the network between here and the room. Run it from places far apart (this Mac,
 * a cloud runner) to see what remote players get.
 *
 * Run: pnpm --filter @pounce/play-api latency:tumble -- --base https://<worker> --players 3 --seconds 60
 * The Worker must list `tumble` in GAMES (production does).
 */
import { performance } from "node:perf_hooks";

import { applyHit, newBox, receiveJunk, setDown, useTrick, type Box, type Hit } from "../src/tumble/box";
import { placements } from "../src/tumble/cats";

import type { Seed } from "../src/rules/rng";
import type { ClientEvent, HitWire, TumbleServer, TumbleSync } from "../src/tumble/wire";

const flag = (name: string, fallback: string): string => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? (process.argv[i + 1] ?? fallback) : fallback;
};
const BASE = flag("base", "http://127.0.0.1:8799").replace(/\/$/, "");
const PLAYERS = Math.min(6, Math.max(2, Number(flag("players", "3"))));
const SECONDS = Number(flag("seconds", "60"));
const GAMES = "cat-tower,tiles,birdwatch,tumble";
const APP = "platform=web; version=2026.1126.1200; build=1; protocol=1";
const NAMES = ["Ada", "Bo", "Cy", "Di", "Ed", "Flo"];

type Device = { deviceId: string; token: string };
type View = { status: string; r: number; startsAt: number; roundSeed?: Seed; trickSeeds?: Seed[] };

const now = (): number => performance.timeOrigin + performance.now();
const samples: Record<"rtt" | "relay" | "hit", number[]> = { rtt: [], relay: [], hit: [] };

async function mint(): Promise<Device> {
  const res = await fetch(`${BASE}/v1/devices`, { method: "POST" });
  if (!res.ok) throw new Error(`device: ${res.status} ${await res.text()}`);
  return (await res.json()) as Device;
}

async function createTable(host: Device): Promise<string> {
  const res = await fetch(`${BASE}/v1/rooms`, {
    method: "POST",
    headers: { authorization: `Bearer ${host.token}`, "content-type": "application/json", "x-pounce-games": GAMES, "x-pounce-app": APP },
    body: JSON.stringify({ game: "tumble" }),
  });
  if (res.status !== 201) throw new Error(`room: ${res.status} ${await res.text()} (does this Worker list tumble in GAMES?)`);
  return ((await res.json()) as { code: string }).code;
}

/** One scripted player: plays its own box with the engine, acks its hits, and times what it hears. */
class Player {
  ws!: WebSocket;
  view: View | null = null;
  box: Box | null = null;
  round = 0;
  pings = new Map<number, number>();
  /** When this player sent each set-down, by its toy index: for `relay` as others hear it. */
  static sentAt = new Map<string, number>();
  /** When a throw that should hit someone left, by thrower. */
  static thrownAt = new Map<number, number>();

  constructor(readonly seat: number, readonly device: Device) {}

  async open(code: string): Promise<void> {
    const url = `${BASE.replace(/^http/, "ws")}/v1/rooms/${code}/ws?games=${encodeURIComponent(GAMES)}&app=${encodeURIComponent(APP)}`;
    this.ws = new WebSocket(url, ["pounce", `pounce.token.${this.device.token}`]);
    await new Promise<void>((resolve, reject) => {
      this.ws.addEventListener("open", () => resolve(), { once: true });
      this.ws.addEventListener("error", () => reject(new Error(`socket for seat ${this.seat}`)), { once: true });
    });
    this.ws.addEventListener("message", (e) => this.hear(JSON.parse(String(e.data)) as Record<string, unknown>));
  }

  send(m: unknown): void {
    if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(m));
  }

  private hear(m: Record<string, unknown>): void {
    const at = now();
    if (m.t === "pong") {
      const first = [...this.pings.keys()][0];
      if (first !== undefined) {
        samples.rtt.push(at - (this.pings.get(first) as number));
        this.pings.delete(first);
      }
      return;
    }
    if (m.t === "error" && process.argv.includes("--verbose")) console.error(`seat ${this.seat}: ${String(m.code)}`);
    if (m.t === "snapshot") {
      const room = m.room as { tumble?: View };
      if (room.tumble) this.view = room.tumble;
      return;
    }
    const msg = m as unknown as TumbleServer;
    if (msg.t === "tumble") {
      for (const e of msg.ev) {
        if (e[0] !== "l") continue;
        const sent = Player.sentAt.get(`${msg.s}:${e[1]}`);
        if (sent !== undefined && this.seat === (msg.s + 1) % PLAYERS) samples.relay.push(at - sent);
      }
    } else if (msg.t === "tumbleHit" && msg.to === this.seat && this.box && msg.r === this.round) {
      this.takeHit(msg, at);
    } else if (msg.t === "tumbleSync" && msg.r === this.round) {
      const mine = (msg as TumbleSync).boxes.find((b) => b.s === this.seat);
      if (mine) this.box = mine.box;
    }
  }

  private takeHit(h: HitWire, at: number): void {
    const thrown = Player.thrownAt.get(h.from);
    if (thrown !== undefined && h.k !== "napped") samples.hit.push(at - thrown);
    if (h.k === "napped" || !this.box) return;
    if (h.k === "junk") {
      const x = h.x as { rows: number; gap: number };
      this.box = receiveJunk(this.box, { id: h.id, rows: x.rows, gap: x.gap });
    } else {
      this.box = applyHit(this.box, { k: h.k, ...(h.x ?? {}) } as Hit).box;
    }
    this.send({ t: "tumble", r: this.round, ev: [["a", h.id]] });
  }

  /** One step of play: a fresh round's box, then a set-down every call, and a trick now and then. */
  play(): void {
    const v = this.view;
    if (!v || v.status !== "playing" || !v.roundSeed || !v.trickSeeds?.[this.seat]) return;
    if (this.round !== v.r) {
      this.round = v.r;
      this.box = newBox(v.trickSeeds[this.seat] as Seed);
    }
    const box = this.box;
    if (!box || box.out) return;
    const ev: ClientEvent[] = [];
    if (box.held.length > 0) {
      const used = useTrick(box, 0);
      if (used) {
        this.box = used.box;
        ev.push(["u", 0, (this.seat + 1) % PLAYERS]);
        Player.thrownAt.set(this.seat, now());
      }
    }
    const best = placements(this.box as Box, v.roundSeed)[0];
    if (best) {
      const landed = (this.box as Box).waiting.map((w) => w.id);
      const ms = Math.max(0, Math.round(now() - v.startsAt));
      let r = setDown(this.box as Box, v.roundSeed, (this.box as Box).next, best.rot, best.x, best.y, landed);
      let sentLanded = landed;
      if ("error" in r) {
        r = setDown(this.box as Box, v.roundSeed, (this.box as Box).next, best.rot, best.x, best.y, []);
        sentLanded = [];
      }
      if (!("error" in r)) {
        ev.push(["l", (this.box as Box).next, best.rot, best.x, best.y, ms, sentLanded]);
        Player.sentAt.set(`${this.seat}:${(this.box as Box).next}`, now());
        if (r.sent > 0) Player.thrownAt.set(this.seat, now());
        this.box = r.box;
      }
    }
    if (ev.length > 0) this.send({ t: "tumble", r: this.round, ev });
  }

  ping(): void {
    this.pings.set(this.pings.size + Math.random(), now());
    this.send({ t: "ping" });
  }
}

const stats = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  const at = (p: number) => Math.round(s[Math.min(s.length - 1, Math.floor(p * s.length))] ?? 0);
  return { n: s.length, p50: at(0.5), p95: at(0.95), max: Math.round(s[s.length - 1] ?? 0) };
};

async function main(): Promise<void> {
  const devices = await Promise.all(Array.from({ length: PLAYERS }, () => mint()));
  const code = await createTable(devices[0] as Device);
  const players = devices.map((d, seat) => new Player(seat, d));
  for (const p of players) await p.open(code);
  const host = players[0] as Player;
  const claim = (p: Player) => p.send({ t: "claim", seat: p.seat, person: { id: crypto.randomUUID(), name: NAMES[p.seat], cat: p.seat } });
  const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));
  // The host sits first: only a seated host may open more seats.
  claim(host);
  await pause(500);
  for (let seat = 2; seat < PLAYERS; seat++) host.send({ t: "configure", seat, kind: "open" });
  await pause(500);
  for (const p of players.slice(1)) {
    claim(p);
    await pause(300);
  }
  await pause(1000);
  host.send({ t: "start" });
  const until = now() + SECONDS * 1000 + 4000;
  let tick = 0;
  while (now() < until) {
    await new Promise((r) => setTimeout(r, 100));
    tick++;
    if (tick % 7 === 0) for (const p of players) p.play();
    if (tick % 10 === 0) for (const p of players) p.ping();
    // Keep each device heard between set-downs, as a real phone's moves would.
    if (tick % 20 === 0) for (const p of players) if (p.round > 0) p.send({ t: "tumble", r: p.round, ev: [] });
  }
  for (const p of players) p.ws.close(1000);
  const seated = (host.view as { trickSeeds?: Seed[] } | null)?.trickSeeds?.length ?? 0;
  if (seated < PLAYERS) console.error(`only ${seated} of ${PLAYERS} seats played`);
  console.log(JSON.stringify({ base: BASE, players: PLAYERS, seconds: SECONDS, table: code, rtt: stats(samples.rtt), relay: stats(samples.relay), hit: stats(samples.hit) }, null, 2));
}

void main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});
