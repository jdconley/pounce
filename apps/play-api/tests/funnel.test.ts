import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { funnelId } from "../src/funnel/funnel";

import { BASE, bundle, call, connect, eventually, mint, newPerson, profile, SECRET, takeTurn, worker, type Device } from "./play-helpers";

import type { Miniflare } from "miniflare";

// The first-run funnel through the Worker (first-run funnel design, Part 3): the steps the server
// records by itself, `POST /v1/funnel`, the invite pages' counts, and deleting a device's data.

let script = "";
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("../src/index.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

async function funnelWorker(funnel = true): Promise<Miniflare> {
  const mf = await worker(script, { sent: [], funnel });
  open.push(mf);
  return mf;
}

const APP = { "x-pounce-app": "platform=ios; version=1.2; build=70; protocol=3" };

async function mintAs(mf: Miniflare, headers: Record<string, string> = APP): Promise<Device> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": crypto.randomUUID(), ...headers } });
  return (await res.json()) as Device;
}

type Row = Record<string, unknown>;

async function rows(mf: Miniflare, sql: string, ...params: unknown[]): Promise<Row[]> {
  const db = await mf.getD1Database("FUNNEL");
  try {
    return (await db.prepare(sql).bind(...params).all<Row>()).results;
  } catch {
    // The tables come with the first write.
    return [];
  }
}

const stepsOf = async (mf: Miniflare, device: Device): Promise<string[]> =>
  (await rows(mf, "SELECT milestone FROM milestones WHERE id = ? ORDER BY at, milestone", await funnelId(SECRET, device.deviceId))).map(
    (r) => r.milestone as string,
  );

const reachedAll = (want: string[]) => (have: string[]) => want.every((m) => have.includes(m));

describe("the funnel", () => {
  test("a new device: its row, under a hashed id, with the app's platform and version", async () => {
    const mf = await funnelWorker();
    const device = await mintAs(mf);
    const id = await funnelId(SECRET, device.deviceId);
    const [row] = await eventually(
      () => rows(mf, "SELECT * FROM devices"),
      (r) => r.length === 1,
    );
    expect(row).toMatchObject({ id, platform: "ios", app_version: "1.2", source: null });
    expect(JSON.stringify(await rows(mf, "SELECT * FROM devices"))).not.toContain(device.deviceId);
    expect(await stepsOf(mf, device)).toEqual(["device_created"]);
  });

  test("POST /v1/funnel keeps the app's steps, first time wins", async () => {
    const mf = await funnelWorker();
    const device = await mintAs(mf);
    const send = (body: unknown) => call(mf, device, "POST", "/v1/funnel", body, APP);
    expect((await send({ reached: { age_done: 5, named: 0 }, source: "organic", locale: "en-US" })).status).toBe(204);
    await eventually(() => stepsOf(mf, device), reachedAll(["age_done", "named"]));
    const [first] = await rows(mf, "SELECT at FROM milestones WHERE milestone = 'named'");
    expect((await send({ reached: { named: 0, home_seen: 0 } })).status).toBe(204);
    await eventually(() => stepsOf(mf, device), reachedAll(["home_seen"]));
    expect(await rows(mf, "SELECT at FROM milestones WHERE milestone = 'named'")).toEqual([first]);
    expect(await rows(mf, "SELECT locale, source FROM devices")).toEqual([{ locale: "en-US", source: "organic" }]);
  });

  test("POST /v1/funnel refuses what isn't a report, a stranger, and too many", async () => {
    const mf = await funnelWorker();
    const device = await mintAs(mf);
    expect((await call(mf, device, "POST", "/v1/funnel", { reached: {}, name: "Grandma" })).status).toBe(400);
    expect((await call(mf, device, "POST", "/v1/funnel", { reached: { first_move: 0 } })).status).toBe(204);
    expect((await call(mf, { ...device, token: "nope" }, "POST", "/v1/funnel", { reached: {} })).status).toBe(401);
    // A server step an app sends is left out.
    await eventually(() => rows(mf, "SELECT * FROM device_days"), (r) => r.length > 0);
    expect(await stepsOf(mf, device)).toEqual(["device_created"]);
    let status = 204;
    for (let i = 0; i < 30 && status === 204; i++) status = (await call(mf, device, "POST", "/v1/funnel", { reached: {} })).status;
    expect(status).toBe(429);
  });

  test("without the database, the endpoint still answers and nothing breaks", async () => {
    const mf = await funnelWorker(false);
    const device = await mint(mf);
    expect((await call(mf, device, "POST", "/v1/funnel", { reached: { age_done: 0 } })).status).toBe(204);
    const res = await call(mf, device, "POST", "/v1/rooms", { game: "cat-tower" });
    expect(res.status).toBe(201);
  });

  test("a table: created, a seat at your own and at someone else's, and each device's first move", async () => {
    const mf = await funnelWorker();
    const host = await mintAs(mf);
    const guest = await mintAs(mf);
    const res = await call(mf, host, "POST", "/v1/rooms", { game: "cat-tower" });
    const { code } = (await res.json()) as { code: string };
    const people = [newPerson("Grandma", 1), newPerson("Ava", 2)];
    const clients = [];
    for (const [i, device] of [host, guest].entries()) {
      const c = await connect(mf, code, device);
      const p = people[i] as (typeof people)[number];
      c.send({ t: "claim", seat: i, person: { id: p.id, name: p.name, cat: p.cat } });
      await c.until((s) => s.room.seats[i]?.kind === "human");
      clients.push(c);
    }
    clients[0]?.send({ t: "start" });
    for (const c of clients) await c.until((s) => s.room.status === "playing");
    const first = await takeTurn(clients);
    const mover = first === 0 ? host : guest;
    expect(await eventually(() => stepsOf(mf, host), reachedAll(["table_created", "seat_taken"]))).toEqual(
      expect.arrayContaining(["device_created", "table_created", "seat_taken"]),
    );
    expect(await eventually(() => stepsOf(mf, guest), reachedAll(["seat_taken", "joined_table"]))).not.toContain("table_created");
    expect(await eventually(() => stepsOf(mf, mover), reachedAll(["first_move"]))).toContain("first_move");
    expect(await stepsOf(mf, first === 0 ? guest : host)).not.toContain("first_move");
    expect(await rows(mf, "SELECT DISTINCT game FROM milestones WHERE game IS NOT NULL")).toEqual([{ game: "cat-tower" }]);
    // Opening a table is activity: day 0 of each device's life.
    expect(await rows(mf, "SELECT DISTINCT day FROM device_days")).toEqual([{ day: 0 }]);
    for (const c of clients) c.ws.close();
  });

  test("invite pages are counted per day, link previews apart", async () => {
    const mf = await funnelWorker();
    await mf.dispatchFetch(`${BASE}/j/ABCD`, { headers: { "user-agent": "facebookexternalhit/1.1 Facebot Twitterbot/1.0" } });
    await mf.dispatchFetch(`${BASE}/j/ABCD`, { headers: { "user-agent": "Mozilla/5.0 (iPhone)" } });
    const views = await eventually(
      () => rows(mf, "SELECT page, views FROM page_views ORDER BY page"),
      (r) => r.length === 2,
    );
    expect(views).toEqual([
      { page: "j", views: 1 },
      { page: "j_preview", views: 1 },
    ]);
  });

  test("deleting your data deletes the device's funnel rows", async () => {
    const mf = await funnelWorker();
    const device = await mintAs(mf);
    const ava = newPerson("Ava", 2);
    await profile(mf, device, [ava]);
    await call(mf, device, "POST", "/v1/funnel", { reached: { age_done: 0 } });
    await eventually(() => stepsOf(mf, device), reachedAll(["age_done"]));
    expect((await call(mf, device, "DELETE", `/v1/me?person=${ava.id}`)).status).toBe(204);
    expect(await stepsOf(mf, device)).toEqual([]);
    expect(await rows(mf, "SELECT * FROM devices")).toEqual([]);
  });
});
