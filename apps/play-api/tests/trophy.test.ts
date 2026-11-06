import { afterEach, beforeAll, describe, expect, test } from "vitest";

import {
  bundle,
  call,
  connect,
  eventually,
  mint,
  newPerson,
  profile,
  settle,
  table,
  takeTurn,
  worker,
  type Client,
  type Device,
  type Person,
  type Sent,
} from "./play-helpers";

import type { ServerMessage } from "../src/protocol";
import type { StreakView } from "../src/streaks/pair-core";
import type { OwnStreak } from "../src/streaks/personal";
import type { Trophies } from "../src/streaks/trophies";
import type { Miniflare } from "miniflare";

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./pounce-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
});

async function start(trophy = true): Promise<Miniflare> {
  const mf = await worker(script, { links: true, trophy, sent });
  open.push(mf);
  return mf;
}

type List = { own?: OwnStreak; pairs: StreakView[]; left: unknown[] };

const streaks = async (mf: Miniflare, d: Device, p: Person): Promise<List> =>
  (await (await call(mf, d, "GET", `/v1/me/streaks?person=${p.id}`)).json()) as List;
const trophiesOf = (mf: Miniflare, d: Device, p: Person) => call(mf, d, "GET", `/v1/me/trophies?person=${p.id}`);
const pounce = (mf: Miniflare, d: Device, p: Person, body: unknown) => call(mf, d, "POST", `/v1/pounces?person=${p.id}`, body);
const answer = (mf: Miniflare, d: Device, p: Person, id: string, body: unknown) => call(mf, d, "POST", `/v1/pounces/${id}/answer?person=${p.id}`, body);

async function someone(mf: Miniflare, name: string, cat: number, band = "adult"): Promise<{ d: Device; p: Person }> {
  const d = await mint(mf);
  const p = newPerson(name, cat);
  await profile(mf, d, [p], { band });
  return { d, p };
}

/** JD's Messages link (target "new"): its pounce id and token. */
async function linkFrom(mf: Miniflare, d: Device, p: Person): Promise<{ id: string; token: string }> {
  const res = await pounce(mf, d, p, { target: "new" });
  expect(res.status).toBe(201);
  const { id, link } = (await res.json()) as { id: string; link: string };
  return { id, token: link.split("/").at(-1) as string };
}

describe("your own streak and GET /v1/me/trophies (trophy room design §2, §3, D1)", { timeout: 30_000 }, () => {
  test("a turn at a table with another person keeps your own day; the trophy room lists records, the catalog and the connection", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const mia = await someone(mf, "Mia", 2);
    const t = await table(mf, [
      [jd.d, jd.p],
      [mia.d, mia.p],
    ]);
    await takeTurn(t.clients);
    await takeTurn(t.clients);
    await (t.clients[0] as Client).find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak" && m.view.kept);

    const list = await eventually(() => streaks(mf, jd.d, jd.p), (l) => l.own?.count === 1);
    expect(list.own).toMatchObject({ count: 1, best: 1, kept: true, lifetimeKept: 1, winback: null });
    expect(list.own?.week).toHaveLength(7);
    expect((await streaks(mf, mia.d, mia.p)).own).toMatchObject({ count: 1, kept: true });

    const res = await trophiesOf(mf, jd.d, jd.p);
    expect(res.status).toBe(200);
    const room = (await res.json()) as Trophies;
    expect(room.records).toEqual({ current: 1, best: 1, longestPair: 1, totalDays: 1, perfectWeeks: 0 });
    expect(room.connections.map((c) => c.partner.name)).toEqual(["Mia"]);
    expect(room.connections[0]?.pair).toBe(list.pairs[0]?.pair);
    expect(room.catalog).toHaveLength(44);
    expect(room.earned.condoStage).toBe(1);
    // The kept day's toy is on the shelf.
    expect(room.earned.toys).toEqual([list.pairs[0]?.todayToy]);
    expect(JSON.stringify(room)).not.toContain("p_");
  });

  test("a table of one person and bots never counts", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const res = await call(mf, jd.d, "POST", "/v1/rooms", { game: "cat-tower" });
    const { code } = (await res.json()) as { code: string };
    const c = await connect(mf, code, jd.d);
    c.send({ t: "claim", seat: 0, person: { id: jd.p.id, name: jd.p.name, cat: jd.p.cat } });
    await c.until((s) => s.room.seats[0]?.kind === "human");
    c.send({ t: "configure", seat: 1, kind: "bot" });
    await c.until((s) => s.room.seats[1]?.kind === "bot");
    c.send({ t: "start" });
    await c.until((s) => s.room.status === "playing");
    // Play until JD has taken a turn.
    await c.until((s) => s.room.game?.turn === 0);
    await takeTurn([c, c]);
    await settle(500);
    const list = await streaks(mf, jd.d, jd.p);
    expect(list.own).toMatchObject({ count: 0, kept: false, lifetimeKept: 0 });
    expect(list.pairs).toEqual([]);
  });
});

describe("connections on accept (D2)", { timeout: 30_000 }, () => {
  test("Play on a link makes the pair at 0 at once, before any turn, in both lists, with the new table as a move", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const kim = await someone(mf, "Kim", 5);
    const { id, token } = await linkFrom(mf, jd.d, jd.p);
    const played = await answer(mf, kim.d, kim.p, id, { answer: "play", link: token });
    expect(played.status).toBe(200);
    const { code } = (await played.json()) as { code: string };

    const jdList = await streaks(mf, jd.d, jd.p);
    const kimList = await streaks(mf, kim.d, kim.p);
    expect(jdList.pairs).toHaveLength(1);
    expect(jdList.pairs[0]).toMatchObject({ partner: { name: "Kim", cat: 5 }, count: 0, kept: false });
    expect(kimList.pairs[0]).toMatchObject({ partner: { name: "JD", cat: 1 }, count: 0, pair: jdList.pairs[0]?.pair });
    // The deal reaches the new pair: the table is one of its moves.
    const moved = await eventually(
      () => streaks(mf, kim.d, kim.p),
      (l) => [...(l.pairs[0]?.myMove ?? []), ...(l.pairs[0]?.theirMove ?? [])].includes(code),
    );
    expect([...(moved.pairs[0]?.myMove ?? []), ...(moved.pairs[0]?.theirMove ?? [])]).toContain(code);
    // Nobody has played: no own streak yet.
    expect(jdList.own?.count).toBe(0);
    // The answered push names the pair.
    expect(JSON.stringify(sent)).not.toContain("p_");
  });

  test("a double tap makes one pair and one table; In a bit makes none", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const kim = await someone(mf, "Kim", 5);
    const sam = await someone(mf, "Sam", 3);
    const { id, token } = await linkFrom(mf, jd.d, jd.p);
    const results = await Promise.all([1, 2].map(() => answer(mf, kim.d, kim.p, id, { answer: "play", link: token })));
    const codes = new Set(
      (await Promise.all(results.map(async (r) => (r.status === 200 ? ((await r.json()) as { code?: string }).code : undefined)))).filter(Boolean),
    );
    expect(codes.size).toBe(1);
    expect((await streaks(mf, jd.d, jd.p)).pairs).toHaveLength(1);
    expect((await streaks(mf, kim.d, kim.p)).pairs).toHaveLength(1);

    const later = await linkFrom(mf, jd.d, jd.p);
    expect((await answer(mf, sam.d, sam.p, later.id, { answer: "later", link: later.token })).status).toBe(200);
    expect((await streaks(mf, sam.d, sam.p)).pairs).toEqual([]);
  });

  test("someone who left your streak isn't connected again by a link; the table still deals", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const kim = await someone(mf, "Kim", 5);
    const first = await linkFrom(mf, jd.d, jd.p);
    expect((await answer(mf, kim.d, kim.p, first.id, { answer: "play", link: first.token })).status).toBe(200);
    const pair = (await streaks(mf, kim.d, kim.p)).pairs[0]?.pair as string;
    expect((await call(mf, kim.d, "DELETE", `/v1/pairs/${pair}?person=${kim.p.id}`)).status).toBe(204);
    const second = await linkFrom(mf, jd.d, jd.p);
    const played = await answer(mf, kim.d, kim.p, second.id, { answer: "play", link: second.token });
    expect(played.status).toBe(200);
    expect(((await played.json()) as { code?: string }).code).toMatch(/^[A-Z0-9]{5}$/);
    expect((await streaks(mf, jd.d, jd.p)).pairs).toEqual([]);
  });

  test("a kitten can accept a link (and is connected) but can't send one", async () => {
    const mf = await start();
    const jd = await someone(mf, "JD", 1);
    const kit = await someone(mf, "Mochi", 4, "kitten");
    const { id, token } = await linkFrom(mf, jd.d, jd.p);
    const played = await answer(mf, kit.d, kit.p, id, { answer: "play", link: token });
    expect(played.status).toBe(200);
    expect((await streaks(mf, jd.d, jd.p)).pairs[0]).toMatchObject({ partner: { name: "Mochi", cat: 4 }, count: 0 });
    expect((await streaks(mf, kit.d, kit.p)).pairs[0]).toMatchObject({ partner: { name: "JD", cat: 1 }, count: 0 });
    expect((await pounce(mf, kit.d, kit.p, { target: "new" })).status).toBe(403);
  });
});

describe("with TROPHY off", { timeout: 30_000 }, () => {
  test("the server answers as before: no own streak, no trophy room, and a link makes no pair until both take a turn", async () => {
    const mf = await start(false);
    const jd = await someone(mf, "JD", 1);
    const kim = await someone(mf, "Kim", 5);
    expect(Object.keys(await streaks(mf, jd.d, jd.p)).sort()).toEqual(["left", "pairs"]);
    expect((await trophiesOf(mf, jd.d, jd.p)).status).toBe(404);
    const { id, token } = await linkFrom(mf, jd.d, jd.p);
    const played = await answer(mf, kim.d, kim.p, id, { answer: "play", link: token });
    const { code } = (await played.json()) as { code: string };
    await settle(500);
    expect((await streaks(mf, jd.d, jd.p)).pairs).toEqual([]);
    // Both take a turn at the dealt table: now they're a pair, as today.
    const a = await connect(mf, code, jd.d);
    const b = await connect(mf, code, kim.d);
    await takeTurn([a, b]);
    await takeTurn([a, b]);
    const list = await eventually(() => streaks(mf, jd.d, jd.p), (l) => l.pairs.length === 1);
    expect(list.pairs).toHaveLength(1);
    expect(list.own).toBeUndefined();
  });
});
