import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { IDLE_MS } from "../src/live/live";

import { BASE, call, connect, eventually, mint, newPerson, profile, settle, table, takeTurn, tokenOf, worker, type Client, type Sent } from "./play-helpers";

import type { Miniflare } from "miniflare";

const JD_APNS = tokenOf(1);
const MIA_APNS = tokenOf(2);
const JD_START = tokenOf(5);
const JD_LIVE = tokenOf(6);
const JD_LIVE_2 = tokenOf(7);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  const { bundle } = await import("./play-helpers");
  script = await bundle("./live-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
});

async function start(options: { live?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, { live: options.live ?? true, sent });
  open.push(mf);
  return mf;
}

type LiveAps = {
  event: string;
  timestamp: number;
  "content-state": { table: string; seats: { me: boolean }[]; turn: number | null; mine: boolean; streak: unknown };
  attributes?: { code: string };
  "attributes-type"?: string;
  alert?: { title: string; body: string; sound?: string };
  "stale-date"?: number;
  "dismissal-date"?: number;
};
const liveTo = (token: string) => sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "liveactivity");
const alertsTo = (token: string) => sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert");
const aps = (s: Sent | undefined) => (s as Sent).body.aps as LiveAps;

/** JD on a phone (seat 0, with a push-to-start token) and Mia on a tablet (seat 1), at a started table. */
async function setUp(mf: Miniflare, options: { band?: string; zone?: string; startToken?: boolean } = {}) {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  await profile(mf, phone, [jd], { apns: JD_APNS, ...(options.band ? { band: options.band } : {}), ...(options.zone ? { zone: options.zone } : {}) });
  await profile(mf, tablet, [mia], { apns: MIA_APNS });
  if (options.startToken !== false) {
    expect((await call(mf, phone, "PUT", "/v1/devices/me/live-activity", { pushToStart: JD_START })).status).toBe(204);
  }
  const t = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  const [a, b] = t.clients as [Client, Client];
  return { phone, tablet, jd, mia, ...t, a, b };
}

/** Plays (both awake) until it's Mia's move, so JD leaves on her move. */
async function miasMove(clients: Client[]): Promise<void> {
  for (let i = 0; i < 4 && (clients[0] as Client).game().turn !== 1; i++) await takeTurn(clients);
  expect((clients[0] as Client).game().turn).toBe(1);
}

/** JD leaves on Mia's move while she's at the table: the start lands on JD's push-to-start token. */
async function liveForJd(mf: Miniflare, s: Awaited<ReturnType<typeof setUp>>): Promise<Sent> {
  await miasMove(s.clients);
  s.a.away();
  const [startPush] = await eventually(() => liveTo(JD_START), (l) => l.length === 1);
  return startPush as Sent;
}

const uploadLiveToken = async (mf: Miniflare, s: { phone: Parameters<typeof call>[1] }, code: string, token: string | null) =>
  (await call(mf, s.phone, "PUT", "/v1/devices/me/live-activity", { activities: [{ code, token }] })).status;

/** Mia (seat 1) plays her turn while JD is away; the move comes back to JD. */
async function miaPlays(s: Awaited<ReturnType<typeof setUp>>): Promise<void> {
  await takeTurn(s.clients);
}

describe("the token route (§13.4)", { timeout: 30_000 }, () => {
  test("takes push-to-start and activity tokens; 400 for anything else; 404 with LIVE off", async () => {
    const mf = await start();
    const phone = await mint(mf);
    await profile(mf, phone, [newPerson("JD", 1)]);
    expect((await call(mf, phone, "PUT", "/v1/devices/me/live-activity", { pushToStart: JD_START })).status).toBe(204);
    expect((await call(mf, phone, "PUT", "/v1/devices/me/live-activity", { activities: [{ code: "GH2VD", token: null }] })).status).toBe(204);
    for (const bad of [{}, { pushToStart: "nope" }, { pushToStart: JD_START, more: 1 }, { activities: [{ code: "aaaaa", token: JD_LIVE }] }]) {
      expect((await call(mf, phone, "PUT", "/v1/devices/me/live-activity", bad)).status).toBe(400);
    }
    const res = await mf.dispatchFetch(`${BASE}/v1/devices/me/live-activity`, { method: "PUT", body: "{}" });
    expect(res.status).toBe(401);

    const off = await start({ live: false });
    const other = await mint(off);
    expect((await call(off, other, "PUT", "/v1/devices/me/live-activity", { pushToStart: JD_START })).status).toBe(404);
  });
});

describe("starting (§11.3)", { timeout: 30_000 }, () => {
  test("leaving while Mia is at the table starts the live table from JD's view", async () => {
    const mf = await start();
    const s = await setUp(mf);
    const push = await liveForJd(mf, s);
    expect(push.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-topic": "com.conleychaos.play.push-type.liveactivity",
      "apns-priority": "10",
    });
    const a = aps(push);
    expect(a).toMatchObject({ event: "start", "attributes-type": "LiveTableAttributes", attributes: { code: s.code }, "input-push-token": 1 });
    expect(a.alert).toEqual({ title: s.name, body: "Mia's move." });
    expect(a["content-state"]).toMatchObject({ table: s.name, turn: 1, mine: false, seats: [{ me: true }, { me: false }] });
    expect(a["stale-date"]).toBe(a.timestamp + IDLE_MS / 1000);
    // Leaving again (the socket closing) starts nothing more.
    s.a.ws.close();
    await settle();
    expect(liveTo(JD_START)).toHaveLength(1);
  });

  test("carries the pair's paws once both have played", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await takeTurn(s.clients);
    await takeTurn(s.clients);
    await s.a.find((m) => m.t === "streak");
    const push = await liveForJd(mf, s);
    expect(aps(push)["content-state"].streak).toEqual({ count: 1, me: true, them: true });
  });

  test("not when Mia is away too, and not with JD's toggle off", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await miasMove(s.clients);
    s.b.away();
    await settle();
    s.a.away();
    await settle(500);
    expect(liveTo(JD_START)).toEqual([]);

    const off = await start();
    const t = await setUp(off);
    const patch = { settings: { "liveTable.on": { v: false, at: Date.now() } } };
    expect((await call(off, t.phone, "PATCH", `/v1/me/state?person=${t.jd.id}`, patch)).status).toBe(204);
    await miasMove(t.clients);
    t.a.away();
    await settle(500);
    expect(liveTo(JD_START)).toEqual([]);
  });

  test("with LIVE off nothing starts and your move goes out as before", async () => {
    const mf = await start({ live: false });
    const s = await setUp(mf, { startToken: false });
    await miasMove(s.clients);
    s.a.away();
    await miaPlays(s);
    await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect(sent.filter((x) => x.headers["apns-push-type"] === "liveactivity")).toEqual([]);
  });
});

describe("updates and your move (§11.3, §12.1)", { timeout: 30_000 }, () => {
  test("with the activity's token, the move coming to JD rings the live table and your move stays quiet", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    expect(await uploadLiveToken(mf, s, s.code, JD_LIVE)).toBe(204);
    await miaPlays(s);
    const [update] = await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    expect((update as Sent).headers["apns-priority"]).toBe("10");
    expect(aps(update)).toMatchObject({ event: "update", "content-state": { turn: 0, mine: true } });
    expect(aps(update).alert).toEqual({ title: "JD", body: `Mia played. Your move at ${s.name}.`, sound: "default" });
    await settle(500);
    expect(alertsTo(JD_APNS)).toEqual([]);
  });

  test("before the token arrives, your move goes out as usual and no update is sent", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await miaPlays(s);
    await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect(liveTo(JD_LIVE)).toEqual([]);
  });

  test("a null token (swiped away on the phone) lets your move through again", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await uploadLiveToken(mf, s, s.code, null);
    await miaPlays(s);
    await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect(liveTo(JD_LIVE)).toEqual([]);
  });
});

describe("ending (§11.3)", { timeout: 30_000 }, () => {
  test("coming back to the table ends it now", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await connect(mf, s.code, s.phone);
    const [end] = await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    expect(aps(end)).toMatchObject({ event: "end" });
    expect(aps(end)["dismissal-date"]).toBe(aps(end).timestamp);
  });

  test("30 minutes with no move ends it; on JD's move his your move comes back, quietly, to that phone", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await miaPlays(s);
    await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    const at = Date.now();
    await mf.dispatchFetch(`${BASE}/__test/live?code=${s.code}&now=${at + IDLE_MS - 60_000}`);
    await settle();
    expect(liveTo(JD_LIVE)).toHaveLength(1);
    await mf.dispatchFetch(`${BASE}/__test/live?code=${s.code}&now=${at + IDLE_MS + 1000}`);
    const [, end] = await eventually(() => liveTo(JD_LIVE), (l) => l.length === 2);
    expect(aps(end).event).toBe("end");
    const [yourMove] = await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect((yourMove as Sent).body).toMatchObject({ kind: "your_move", code: s.code });
    expect(((yourMove as Sent).body.aps as Record<string, unknown>)["interruption-level"]).toBe("passive");
    expect((yourMove as Sent).body.aps).not.toHaveProperty("sound");
    expect(alertsTo(MIA_APNS)).toEqual([]);
  });

  test("a newer live table replaces the older one, which ends first", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    const second = await table(mf, [
      [s.phone, s.jd],
      [s.tablet, s.mia],
    ]);
    // Opening the second table doesn't end the first: JD's phone never came back to it.
    await miasMove(second.clients);
    (second.clients[0] as Client).away();
    await eventually(() => liveTo(JD_START), (l) => l.length === 2);
    const [end] = await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    expect(aps(end).event).toBe("end");
    expect(sent.indexOf(end as Sent)).toBeLessThan(sent.indexOf(liveTo(JD_START)[1] as Sent));
    // The first table's updates no longer reach the phone, and its your move isn't held back.
    expect(await uploadLiveToken(mf, s, second.code, JD_LIVE_2)).toBe(204);
    await miaPlays(s);
    await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect(liveTo(JD_LIVE)).toHaveLength(1);
  });

  test("replaced while it was JD's move there: that table's your move comes back, quietly", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await miaPlays(s);
    await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    expect(alertsTo(JD_APNS)).toEqual([]);
    const second = await table(mf, [
      [s.phone, s.jd],
      [s.tablet, s.mia],
    ]);
    await miasMove(second.clients);
    (second.clients[0] as Client).away();
    const [held] = await eventually(() => alertsTo(JD_APNS), (l) => l.length === 1);
    expect((held as Sent).body).toMatchObject({ kind: "your_move", code: s.code });
    expect(((held as Sent).body.aps as Record<string, unknown>)["interruption-level"]).toBe("passive");
  });

  test("closing the socket inside the app (Home, another table) starts nothing", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await miasMove(s.clients);
    s.a.ws.close();
    await settle(500);
    expect(liveTo(JD_START)).toEqual([]);
  });

  test("a held-back your move never outlives the live table's limits", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    const running = async (later: number) =>
      (await (await mf.dispatchFetch(`${BASE}/__test/running?device=${s.phone.deviceId}&code=${s.code}&now=${Date.now() + later}`)).json()) as boolean;
    expect(await running(0)).toBe(true);
    expect(await running(IDLE_MS - 60_000)).toBe(true);
    expect(await running(IDLE_MS + 1000)).toBe(false);
  });

  test("a null for the table before the new activity's token arrived is a late word about an old one", async () => {
    const mf = await start();
    const s = await setUp(mf);
    await liveForJd(mf, s);
    expect(await uploadLiveToken(mf, s, s.code, null)).toBe(204);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await miaPlays(s);
    await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
  });
});

describe("quiet hours (§12.3)", { timeout: 30_000 }, () => {
  test("the move coming to JD in his quiet hours updates the live table without ringing", async () => {
    // A zone where it's 23:00 now: inside an adult's 22:00–08:00.
    const k = (((new Date().getUTCHours() - 23) % 24) + 24) % 24;
    const zone = k <= 12 ? `Etc/GMT+${k}` : `Etc/GMT-${24 - k}`;
    const mf = await start();
    const s = await setUp(mf, { zone });
    await liveForJd(mf, s);
    await uploadLiveToken(mf, s, s.code, JD_LIVE);
    await miaPlays(s);
    const [update] = await eventually(() => liveTo(JD_LIVE), (l) => l.length === 1);
    expect((update as Sent).headers["apns-priority"]).toBe("5");
    expect(aps(update)).not.toHaveProperty("alert");
    expect(aps(update)["content-state"]).toMatchObject({ mine: true });
  });
});

describe("age bands (§14.1)", { timeout: 30_000 }, () => {
  test("a kitten's device keeps no live token and gets nothing", async () => {
    const mf = await start();
    const s = await setUp(mf, { band: "kitten" });
    await miasMove(s.clients);
    s.a.away();
    await settle(500);
    expect(sent.filter((x) => x.token === JD_START)).toEqual([]);
  });

  test("a teen's device gets nothing between 00:00 and 06:00", async () => {
    // A zone where it's 02:00 now.
    const k = (((new Date().getUTCHours() - 2) % 24) + 24) % 24;
    const zone = k <= 12 ? `Etc/GMT+${k}` : `Etc/GMT-${24 - k}`;
    const mf = await start();
    const s = await setUp(mf, { band: "teen", zone });
    await miasMove(s.clients);
    s.a.away();
    await settle(500);
    expect(sent.filter((x) => x.token === JD_START)).toEqual([]);
  });
});
