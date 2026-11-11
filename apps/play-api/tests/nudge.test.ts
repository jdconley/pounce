import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { NUDGE_AFTER_MS } from "../src/room/core";

import { bundle, eventually, mint, newPerson, profile, settle, table, takeTurn, tokenOf, worker, type Client, type Sent } from "./play-helpers";

import type { ServerMessage } from "../src/protocol";
import type { Miniflare } from "miniflare";

const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);
/** The dev server's top speed: the two-minute wait is 1.2 s, the ten-minute cooldown 6 s. */
const SPEED = 100;
const WAIT_MS = NUDGE_AFTER_MS / SPEED + 150;

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./notify-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
});

async function start(options: { nudge?: boolean; notify?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, { sent, nudge: options.nudge ?? true, notify: options.notify, devSpeed: SPEED });
  open.push(mf);
  return mf;
}

/** A fixed-offset zone where the local hour is `hour` right now, so quiet hours never depend on when the suite runs. */
function zoneAt(hour: number): string {
  const k = (((new Date().getUTCHours() - hour) % 24) + 24) % 24;
  return k <= 12 ? `Etc/GMT+${k}` : `Etc/GMT-${24 - k}`;
}

type Aps = { alert: { title: string; body: string }; category?: string; "interruption-level"?: string; sound?: string; "thread-id"?: string };
const aps = (s: Sent) => s.body.aps as Aps;
const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));

/**
 * JD on a phone and Mia on a tablet at a started table, Mia's zone at `hour` (midday unless
 * asked). Returns who holds the move (`target`) and who nudges (`sender`), with their clients.
 */
async function setUp(mf: Miniflare, options: { miaBand?: string; hour?: number } = {}) {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  await profile(mf, phone, [jd], { apns: JD_TOKEN, zone: zoneAt(12) });
  await profile(mf, tablet, [mia], { apns: MIA_TOKEN, zone: zoneAt(options.hour ?? 12), ...(options.miaBand ? { band: options.miaBand } : {}) });
  const t = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  const [a, b] = t.clients as [Client, Client];
  // Mia holds the move: JD plays first when the deal gave it to him.
  // (A skip can hand the move straight back.)
  for (let i = 0; i < 4 && a.game().turn === 0; i++) await takeTurn(t.clients);
  await b.until((s) => s.room.game?.turn === 1);
  return { ...t, sender: a, target: b };
}

/** Mia leaves the table (the app goes to the background), the wait passes, JD nudges her. */
async function nudgeAway(s: { sender: Client; target: Client }): Promise<void> {
  s.target.away();
  await settle(WAIT_MS);
  s.sender.send({ t: "nudge", seat: 1 });
  await s.sender.find((m) => m.t === "nudgeSent");
}

describe("nudge (NUDGE)", { timeout: 30_000 }, () => {
  test("too soon is refused with the wait in the snapshot; then it goes, and once a turn", async () => {
    const mf = await start();
    const s = await setUp(mf);
    const view = s.sender.last?.room.nudge;
    expect(view).toMatchObject({ seat: 1, sent: false });
    expect(view?.wait).toBeGreaterThan(0);
    expect(view?.wait).toBeLessThanOrEqual(NUDGE_AFTER_MS / SPEED);
    expect(s.target.last?.room).not.toHaveProperty("nudge");
    s.sender.send({ t: "nudge", seat: 1 });
    await s.sender.find((m) => m.t === "error" && m.code === "too_soon");
    await settle(WAIT_MS);
    s.sender.send({ t: "nudge", seat: 1 });
    expect(await s.sender.find((m) => m.t === "nudgeSent")).toEqual({ t: "nudgeSent", seat: 1 });
    s.sender.send({ t: "nudge", seat: 1 });
    await eventually(() => s.sender.received.filter((m) => m.t === "error" && m.code === "too_soon"), (l) => l.length === 2);
    expect(s.sender.received.filter((m) => m.t === "error" && m.code === "too_soon")).toHaveLength(2);
  });

  test("at the table: the app shows it and no push goes", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await settle(WAIT_MS);
    s.sender.send({ t: "nudge", seat: 1 });
    expect(await s.target.find((m) => m.t === "nudged")).toEqual({ t: "nudged", seat: 1, from: 0 });
    await settle(400);
    expect(alertsTo(MIA_TOKEN, "nudge")).toEqual([]);
  });

  test("away: a push for Mia, from JD, opening the table in its thread, with Play and In an hour", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await nudgeAway(s);
    const [push] = (await eventually(() => alertsTo(MIA_TOKEN, "nudge"), (l) => l.length === 1)) as [Sent];
    expect(aps(push)).toMatchObject({
      alert: { title: "Mia", body: `JD nudged you. Your move at ${s.name}.` },
      category: "YOUR_MOVE",
      "interruption-level": "active",
      sound: "default",
      "thread-id": s.code,
      "mutable-content": 1,
    });
    expect(push.body).toMatchObject({ kind: "nudge", code: s.code, from: { name: "JD", cat: 1 } });
    expect(push.headers["apns-collapse-id"]).toBe(s.code);
    expect(alertsTo(JD_TOKEN, "nudge")).toEqual([]);
  });

  test("in Mia's quiet hours it arrives without a sound", async () => {
    const mf = await start();
    const s = await setUp(mf, { hour: 23 });
    await nudgeAway(s);
    const [push] = (await eventually(() => alertsTo(MIA_TOKEN, "nudge"), (l) => l.length === 1)) as [Sent];
    expect(aps(push)["interruption-level"]).toBe("passive");
    expect(aps(push)).not.toHaveProperty("sound");
  });

  test("a teen gets nothing overnight, and a kitten's own device nothing at all (§14.1)", async () => {
    for (const [band, hour] of [
      ["teen", 2],
      ["kitten", 12],
    ] as const) {
      const mf = await start();
      const s = await setUp(mf, { miaBand: band, hour });
      await nudgeAway(s);
      await settle(400);
      expect(alertsTo(MIA_TOKEN, "nudge")).toEqual([]);
    }
  });

  test("with NOTIFY off it shows in the app only; with NUDGE off it's refused and snapshots are as before", async () => {
    const quiet = await start({ notify: false });
    const s = await setUp(quiet);
    await nudgeAway(s);
    await s.target.find((m) => m.t === "nudged");
    await settle(400);
    expect(alertsTo(MIA_TOKEN, "nudge")).toEqual([]);

    const off = await start({ nudge: false });
    const o = await setUp(off);
    expect(o.sender.last?.room).not.toHaveProperty("nudge");
    await settle(WAIT_MS);
    o.sender.send({ t: "nudge", seat: 1 });
    await o.sender.find((m: ServerMessage) => m.t === "error" && m.code === "bad_message");
  });
});
