import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { slotAt } from "../src/notify/schedule";
import { addDays, dayKey } from "../src/streaks/clock";

import {
  BASE,
  call,
  connect,
  eventually,
  LA,
  mint,
  newPerson,
  profile,
  settle,
  table,
  playWhileAway,
  takeTurn,
  tokenOf,
  worker,
  type Client,
  type Device,
  type Person,
  type Sent,
} from "./play-helpers";

import type { ServerMessage } from "../src/protocol";
import type { RoomState } from "../src/room/core";
import type { Miniflare } from "miniflare";

const DAY_MS = 24 * 60 * 60 * 1000;
const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);
const JD_WIDGET = tokenOf(3);
const MIA_WIDGET = tokenOf(4);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];
const dirs: string[] = [];

beforeAll(async () => {
  const { bundle } = await import("./play-helpers");
  script = await bundle("./notify-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
  sent = [];
});

async function start(options: { streaks?: boolean; persist?: string } = {}): Promise<Miniflare> {
  const mf = await worker(script, { ...options, sent });
  open.push(mf);
  return mf;
}

type Aps = { alert: { title: string; body: string }; category?: string; "interruption-level"?: string; badge?: number; "thread-id"?: string };
const aps = (s: Sent) => s.body.aps as Aps;
const alertsTo = (token: string) => sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert");
const widgetsTo = (token: string) => sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "widgets");

/** JD on a phone (seat 0) and Mia on a tablet (seat 1), at a started table. */
async function setUp(mf: Miniflare, options: { miaBand?: string } = {}) {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  const ids = {
    ...(await profile(mf, phone, [jd], { apns: JD_TOKEN })),
    ...(await profile(mf, tablet, [mia], { apns: MIA_TOKEN, ...(options.miaBand ? { band: options.miaBand } : {}) })),
  };
  const t = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  const [a, b] = t.clients as [Client, Client];
  /** Each seat's person, token and player. */
  const seats = [
    { person: jd, token: JD_TOKEN, face: { name: "JD", cat: 1 }, id: ids[jd.id] as string },
    { person: mia, token: MIA_TOKEN, face: { name: "Mia", cat: 2 }, id: ids[mia.id] as string },
  ] as const;
  return { phone, tablet, jd, mia, ids, ...t, a, b, seats };
}

/**
 * Two turns, one each: a pair, a kept day, and the move back with whoever
 * moved first (`holder`). With `away`, each is away when the move reaches them.
 */
async function pairedUp(mf: Miniflare, away = true) {
  const s = await setUp(mf);
  const holder = s.a.game().turn;
  if (away) {
    await playWhileAway(s.clients);
    await playWhileAway(s.clients);
  } else {
    await takeTurn(s.clients);
    await takeTurn(s.clients);
  }
  const streak = await s.a.find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
  return { ...s, pairId: streak.pair, holder };
}

describe("your move (§12.2, §12.5)", { timeout: 30_000 }, () => {
  test("names who played and carries the category, level, badge and streak", async () => {
    const mf = await start();
    const { clients, name, code, seats } = await setUp(mf);
    const one = await playWhileAway(clients);
    const [first] = await eventually(() => alertsTo(seats[one.next].token), (l) => l.length === 1);
    expect(aps(first as Sent)).toMatchObject({
      alert: { title: seats[one.next].face.name, body: `${seats[one.mover].face.name} played. Your move at ${name}.` },
      category: "YOUR_MOVE",
      "interruption-level": expect.stringMatching(/^(active|passive)$/),
      "thread-id": code,
      "mutable-content": 1,
      "relevance-score": 1,
    });
    expect((first as Sent).body).toMatchObject({ code, kind: "your_move", from: seats[one.mover].face });
    expect(aps(first as Sent).badge).toBeGreaterThanOrEqual(1);

    const two = await playWhileAway(clients);
    const [second] = await eventually(() => alertsTo(seats[two.next].token), (l) => l.length === 1);
    expect((second as Sent).body).toMatchObject({ from: seats[two.mover].face, streak: { count: 1, me: true, them: true } });
    expect(JSON.stringify((second as Sent).body)).not.toContain("p_");
  });

  test("with STREAKS unset the push is the original one", async () => {
    const mf = await start({ streaks: false });
    const { clients, name, code, seats } = await setUp(mf);
    const { next } = await playWhileAway(clients);
    const [push] = await eventually(() => alertsTo(seats[next].token), (l) => l.length === 1);
    expect((push as Sent).body).toEqual({
      aps: { alert: { title: seats[next].face.name, body: `Your turn at ${name}` }, sound: "default", "thread-id": code },
      code,
    });
    expect((push as Sent).headers["apns-priority"]).toBe("10");
  });

  test("a kitten's device gets nothing (§14.1)", async () => {
    const mf = await start();
    const { clients } = await setUp(mf, { miaBand: "kitten" });
    await playWhileAway(clients);
    await playWhileAway(clients);
    await eventually(() => alertsTo(JD_TOKEN), (l) => l.length === 1);
    await settle();
    expect(sent.filter((s) => s.token === MIA_TOKEN)).toEqual([]);
  });

  test("a household kitten on a parent's phone still gets your move there, titled with their name (§14.1)", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const tablet = await mint(mf);
    const jd = newPerson("JD", 1);
    const kid = { ...newPerson("Mochi", 4), ageBand: "kitten" };
    const mia = newPerson("Mia", 2);
    await profile(mf, phone, [jd, kid], { apns: JD_TOKEN });
    await profile(mf, tablet, [mia], { apns: MIA_TOKEN });
    const { clients } = await table(mf, [
      [phone, kid],
      [tablet, mia],
    ]);
    if ((clients[0] as Client).game().turn === 0) await playWhileAway(clients);
    const { next } = await playWhileAway(clients);
    expect(next).toBe(0);
    const [push] = (await eventually(() => alertsTo(JD_TOKEN), (l) => l.length >= 1)) as [Sent];
    expect(aps(push).alert.title).toBe("Mochi");
    expect(push.body.kind).toBe("your_move");
  });
});

describe("the reminder alarm (§12.1, §12.3)", { timeout: 30_000 }, () => {
  test("at 19:30 tomorrow, with your move and nobody in, one reminder goes out", async () => {
    const mf = await start();
    const { seats, holder } = await pairedUp(mf);
    const me = seats[holder];
    const other = seats[1 - holder] as (typeof seats)[number];
    const when = slotAt(addDays(dayKey(Date.now(), LA), 1), 19 * 60 + 30, LA);
    const before = alertsTo(me.token).length;
    await mf.dispatchFetch(`${BASE}/__test/remind?player=${me.id}&now=${when}`);
    const reminders = await eventually(() => alertsTo(me.token).slice(before), (l) => l.length >= 1);
    expect(reminders).toHaveLength(1);
    expect(reminders[0]?.body).toMatchObject({ kind: "reminder" });
    expect(aps(reminders[0] as Sent)).toMatchObject({ alert: { title: me.face.name }, category: "REMINDER", "relevance-score": 0.6 });
    expect(aps(reminders[0] as Sent).alert.body).toMatch(new RegExp(`${other.face.name}|The cats`));
    await mf.dispatchFetch(`${BASE}/__test/remind?player=${me.id}&now=${when + 60_000}`);
    await settle();
    expect(alertsTo(me.token).slice(before)).toHaveLength(1);
    const state = (await (await mf.dispatchFetch(`${BASE}/__test/notify?player=${me.id}`)).json()) as { reminders: number };
    expect(state.reminders).toBe(1);
    // The other person isn't up: it's not their move.
    const otherBefore = alertsTo(other.token).length;
    await mf.dispatchFetch(`${BASE}/__test/remind?player=${other.id}&now=${when}`);
    await settle();
    expect(alertsTo(other.token)).toHaveLength(otherBefore);
  });
});

describe("synced settings (§12.6)", { timeout: 30_000 }, () => {
  test("changing the reminder time moves the alarm at once", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    const ids = await profile(mf, phone, [jd]);
    const alarmAt = async () => (await (await mf.dispatchFetch(`${BASE}/__test/alarm?player=${ids[jd.id] as string}`)).json()) as number;
    const before = await alarmAt();
    const at = Date.now();
    const patch = {
      settings: {
        "reminders.auto": { v: false, at },
        "reminders.weekday": { v: { h: 9, m: 0 }, at },
        "reminders.weekend": { v: { h: 9, m: 0 }, at },
      },
    };
    expect((await call(mf, phone, "PATCH", `/v1/me/state?person=${jd.id}`, patch)).status).toBe(204);
    // Whatever the time of day, the next wake differs once the 19:30 default becomes 09:00.
    expect(await alarmAt()).not.toBe(before);
  });
});

describe("status pushes (§8, §12.1)", { timeout: 30_000 }, () => {
  test("a pause tells the partner, quietly, titled with the table; widgets reload once in 15 minutes", async () => {
    const mf = await start();
    const { jd, phone, tablet, pairId, name } = await pairedUp(mf, false);
    for (const [d, t] of [
      [phone, JD_WIDGET],
      [tablet, MIA_WIDGET],
    ] as [Device, string][]) {
      expect((await call(mf, d, "PUT", "/v1/devices/me/widget-push", { token: t })).status).toBe(204);
    }
    expect((await call(mf, phone, "PUT", "/v1/devices/me/widget-push", { token: "nope" })).status).toBe(400);
    const before = alertsTo(MIA_TOKEN).length;
    expect((await call(mf, phone, "PUT", `/v1/pairs/${pairId}/pause?person=${jd.id}`, { days: 3 })).status).toBe(204);
    const [paused] = (await eventually(() => alertsTo(MIA_TOKEN).slice(before), (l) => l.length === 1)) as [Sent];
    expect(aps(paused)).toMatchObject({ alert: { title: name, body: "JD put the cats to bed for 3 days." }, "interruption-level": "passive", category: "STATUS" });
    expect(paused.body).toMatchObject({ kind: "paused", from: { name: "JD", cat: 1 } });
    expect(alertsTo(JD_TOKEN).filter((s) => s.body.kind === "paused")).toEqual([]);
    await eventually(() => widgetsTo(JD_WIDGET), (l) => l.length === 1);
    expect((await call(mf, phone, "PUT", `/v1/pairs/${pairId}/pause?person=${jd.id}`, { days: 4 })).status).toBe(204);
    await settle();
    expect(widgetsTo(JD_WIDGET)).toHaveLength(1);
    expect(widgetsTo(JD_WIDGET)[0]?.body).toEqual({ aps: { "content-changed": true } });
  });

  test("a missed day after a kept one tells both people about win-back", async () => {
    const mf = await start();
    const { pairId, name } = await pairedUp(mf);
    await mf.dispatchFetch(`${BASE}/__test/settle?pair=${pairId}&now=${Date.now() + 2 * DAY_MS}`);
    for (const token of [JD_TOKEN, MIA_TOKEN]) {
      const [winback] = (await eventually(() => alertsTo(token).filter((s) => s.body.kind === "winback"), (l) => l.length === 1)) as [Sent];
      expect(aps(winback)).toMatchObject({ alert: { title: name, body: "Two days in a row brings 1 back." }, "interruption-level": "passive" });
      expect(aps(winback)["thread-id"]).toBe(`pair:${pairId}`);
    }
  });
});

describe("play again (§10.4)", { timeout: 30_000 }, () => {
  async function importSqlite(): Promise<typeof import("node:sqlite")> {
    const emit = process.emitWarning;
    process.emitWarning = ((warning: string | Error, ...rest: unknown[]) => {
      if (String(warning).includes("SQLite")) return;
      (emit as (...args: unknown[]) => void).call(process, warning, ...rest);
    }) as typeof process.emitWarning;
    try {
      return await import("node:sqlite");
    } finally {
      process.emitWarning = emit;
    }
  }

  async function endStoredRoom(dir: string): Promise<void> {
    const { DatabaseSync } = await importSqlite();
    const rooms = join(dir, readdirSync(dir).find((d) => d.endsWith("GameRoom")) as string);
    const files = readdirSync(rooms).filter((f) => f.endsWith(".sqlite") && f !== "metadata.sqlite");
    const db = new DatabaseSync(join(rooms, files[0] as string));
    const row = db.prepare("SELECT json FROM room WHERE id = 1").get() as { json: string };
    const state = JSON.parse(row.json) as RoomState;
    state.status = "over";
    db.prepare("UPDATE room SET json = ? WHERE id = 1").run(JSON.stringify(state));
    db.close();
  }

  test("tells the others who dealt, except the first mover and anyone looking at the old table", async () => {
    const dir = mkdtempSync(join(tmpdir(), "play-api-notify-"));
    dirs.push(dir);
    const first = await start({ persist: dir });
    const phone = await mint(first);
    const tablet = await mint(first);
    const jd: Person = newPerson("JD", 1);
    const mia: Person = newPerson("Mia", 2);
    await profile(first, phone, [jd], { apns: JD_TOKEN });
    await profile(first, tablet, [mia], { apns: MIA_TOKEN });
    const { code, name } = await table(first, [
      [phone, jd],
      [tablet, mia],
    ]);
    await first.dispose();
    open.splice(open.indexOf(first), 1);
    await endStoredRoom(dir);

    const mf = await start({ persist: dir });
    // JD asks; Mia isn't looking. Seats rotate to [Mia, JD].
    const a = await connect(mf, code, phone);
    a.send({ t: "rematch" });
    const told = await a.find<Extract<ServerMessage, { t: "rematch" }>>((m) => m.t === "rematch");
    const next = await connect(mf, told.code, phone);
    const miaMovesFirst = next.last?.room.game?.turn === 0;
    const forMia = (kind: string) => alertsTo(MIA_TOKEN).filter((s) => s.body.kind === kind && s.body.code === told.code);
    if (miaMovesFirst) {
      // A flipped Cucumber gave Mia the first move: she hears "your move" instead.
      await eventually(() => forMia("your_move"), (l) => l.length === 1);
      await settle();
      expect(forMia("play_again")).toEqual([]);
    } else {
      const [dealt] = (await eventually(() => forMia("play_again"), (l) => l.length === 1)) as [Sent];
      expect(aps(dealt)).toMatchObject({ alert: { title: name, body: "JD dealt a new game." }, "thread-id": told.code });
      expect(dealt.body).toMatchObject({ code: told.code, from: { name: "JD", cat: 1 } });
      // Not Mia's move at either table, so no badge.
      expect(aps(dealt).badge).toBe(0);
    }
    await settle();
    expect(alertsTo(JD_TOKEN).filter((s) => s.body.kind === "play_again")).toEqual([]);
  });
});
