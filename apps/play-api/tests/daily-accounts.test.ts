import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { appleProof, BASE, bundle, call, eventually, mint, newPerson, profile, worker, type Device, type Person } from "./play-helpers";

import type { Miniflare } from "miniflare";

/**
 * The Daily Dish across sign-in (accounts design §13.1): an upgrade keeps everything in place; a
 * merge carries the guest's Dish (results, stats, runs and TV board tokens) to the account, keeps
 * one run per game and date (the one started first), and never opens a second run of today's puzzle.
 */
let script = "";
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./daily-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

async function start(): Promise<Miniflare> {
  const mf = await worker(script, { sent: [], trophy: true, tv: true, daily: true, dailyTest: true });
  open.push(mf);
  return mf;
}

type Who = { device: Device; person: Person };
type Start = { run: string; level: number; date: string; startedAt: number; seq: number; result: { outcome: string } | null };
type Board = { games: { game: string; rows: { player: string; name: string; result: { outcome: string } | null }[] }[] };

async function guest(mf: Miniflare, name: string): Promise<Who & { id: string }> {
  const device = await mint(mf);
  const person = newPerson(name, 3);
  const ids = await profile(mf, device, [person]);
  return { device, person, id: ids[person.id] as string };
}

const signIn = async (mf: Miniflare, who: Who, sub: string) => {
  const res = await call(mf, who.device, "POST", "/v1/identities/apple", { proof: await appleProof(sub), person: { id: who.person.id, key: who.person.key } });
  expect(res.status).toBe(200);
  return (await res.json()) as { playerId: string; outcome: string };
};
const begin = async (mf: Miniflare, who: Who): Promise<Start> => {
  const res = await call(mf, who.device, "POST", `/v1/daily/test/start?person=${who.person.id}`);
  expect(res.status).toBe(200);
  return (await res.json()) as Start;
};
const steps = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => ({ k: "step", n: from + i }));
const send = (mf: Miniflare, who: Who, run: string, from: number, moves: unknown[]) =>
  call(mf, who.device, "POST", `/v1/daily/runs/${run}/moves?person=${who.person.id}`, { from, moves });
const boardOf = async (mf: Miniflare, who: Who) =>
  (await (await call(mf, who.device, "GET", `/v1/daily/board?person=${who.person.id}`)).json()) as Board;
const testRows = (b: Board) => b.games.find((g) => g.game === "test")?.rows ?? [];
const statsOf = async (mf: Miniflare, who: Who) =>
  ((await (await call(mf, who.device, "GET", `/v1/daily/stats?person=${who.person.id}`)).json()) as { games: Record<string, { played: number; solved: number }> }).games.test;
const pairUp = async (mf: Miniflare, a: string, b: string) => expect((await mf.dispatchFetch(`${BASE}/__test/connect?a=${a}&b=${b}`)).status).toBe(204);

describe("an upgrade", { timeout: 30_000 }, () => {
  test("signing in for the first time keeps today's run, results and stats in place", async () => {
    const mf = await start();
    const mom = await guest(mf, "Mom");
    const s = await begin(mf, mom);
    await send(mf, mom, s.run, 0, steps(1, 3 + s.level));
    expect((await signIn(mf, mom, "apple-mom")).outcome).toBe("upgraded");
    expect(await begin(mf, mom)).toMatchObject({ run: s.run, startedAt: s.startedAt, result: { outcome: "solved" } });
    expect(testRows(await boardOf(mf, mom))).toMatchObject([{ player: "me", result: { outcome: "solved" } }]);
    expect(await statsOf(mf, mom)).toMatchObject({ played: 1, solved: 1 });
  });
});

describe("a merge", { timeout: 30_000 }, () => {
  test("the guest's run started first: it is kept, and the account's later run and result are dropped", async () => {
    const mf = await start();
    const phone = await guest(mf, "JD");
    await signIn(mf, phone, "apple-jd");
    const ipad = await guest(mf, "JD on iPad");
    // The guest starts first and makes one move; then the account starts and solves.
    const early = await begin(mf, ipad);
    await send(mf, ipad, early.run, 0, steps(1, 1));
    const late = await begin(mf, phone);
    expect(late.run).not.toBe(early.run);
    await send(mf, phone, late.run, 0, steps(1, 3 + late.level));
    await eventually(() => statsOf(mf, phone), (s) => s?.played === 1);

    expect((await signIn(mf, ipad, "apple-jd")).outcome).toBe("merged");
    // One run for the account, on both devices: the guest's, as it stood.
    for (const who of [phone, ipad]) expect(await begin(mf, who)).toMatchObject({ run: early.run, startedAt: early.startedAt, seq: 1, result: null });
    // The account can play on with it; the dropped run is gone.
    expect(await (await send(mf, phone, early.run, 1, steps(2, 2))).json()).toMatchObject({ ok: true, seq: 2 });
    expect((await send(mf, phone, late.run, 0, [])).status).toBe(404);
    // The dropped run's result is off the board and out of the stats.
    expect(testRows(await boardOf(mf, phone))).toEqual([expect.objectContaining({ player: "me", result: null })]);
    expect(await statsOf(mf, phone)).toMatchObject({ played: 0, solved: 0 });
  });

  test("the account's run started first: it is kept, and the guest's later run and result are dropped", async () => {
    const mf = await start();
    const phone = await guest(mf, "JD");
    await signIn(mf, phone, "apple-jd");
    const ipad = await guest(mf, "JD on iPad");
    const early = await begin(mf, phone);
    await send(mf, phone, early.run, 0, steps(1, 1));
    const late = await begin(mf, ipad);
    await send(mf, ipad, late.run, 0, steps(1, 3 + late.level));
    expect((await signIn(mf, ipad, "apple-jd")).outcome).toBe("merged");
    for (const who of [phone, ipad]) expect(await begin(mf, who)).toMatchObject({ run: early.run, seq: 1, result: null });
    expect((await send(mf, ipad, late.run, 0, [])).status).toBe(404);
    expect(await statsOf(mf, phone)).toMatchObject({ played: 0 });
  });

  test("the guest's results, stats, connections' results and TV come along", async () => {
    const mf = await start();
    const phone = await guest(mf, "JD");
    const account = (await signIn(mf, phone, "apple-jd")).playerId;
    const ipad = await guest(mf, "JD on iPad");
    const kid = await guest(mf, "Kid");
    await pairUp(mf, ipad.id, kid.id);
    // The guest solves today's puzzle, the kid does too, and the guest links a TV to its board.
    const g = await begin(mf, ipad);
    await send(mf, ipad, g.run, 0, steps(1, 3 + g.level));
    const k = await begin(mf, kid);
    await send(mf, kid, k.run, 0, steps(1, 3 + k.level));
    await eventually(async () => testRows(await boardOf(mf, ipad)).length, (n) => n === 2);
    const tv = await mint(mf);
    const link = (await (await call(mf, tv, "POST", "/v1/screens", {})).json()) as { token: string };
    const waiting = await mf.dispatchFetch(`${BASE}/v1/screens/${link.token}/ws`, { headers: { authorization: `Bearer ${tv.token}`, upgrade: "websocket" } });
    const ws = (waiting as unknown as { webSocket: WebSocket & { accept(): void } }).webSocket;
    const told: string[] = [];
    ws.addEventListener("message", (e) => told.push(e.data as string));
    ws.accept();
    expect((await call(mf, ipad.device, "POST", `/v1/screens/link?person=${ipad.person.id}`, { token: link.token, board: true })).status).toBe(200);
    const board = ((await eventually(() => told.map((t) => JSON.parse(t) as { t: string; token?: string }).find((m) => m.t === "board"), (m) => m !== undefined)) as { token: string }).token;

    expect((await signIn(mf, ipad, "apple-jd")).outcome).toBe("merged");
    // The account's board: its own result and the kid's, under the pair.
    const rows = testRows(await boardOf(mf, phone));
    expect(rows.map((r) => r.name).sort()).toEqual(["JD", "Kid"].sort());
    expect(rows.find((r) => r.name === "Kid")?.player).toMatch(/^pr_/);
    expect(await statsOf(mf, phone)).toMatchObject({ played: 1, solved: 1 });
    // The kid's board shows the account's result.
    await eventually(async () => testRows(await boardOf(mf, kid)).length, (n) => n === 2);
    // The TV's token now shows the account's board.
    const whose = (await (await mf.dispatchFetch(`${BASE}/__test/board-token?token=${board}&device=${tv.token.split(".")[1]}&now=${Date.now()}`)).json()) as { player: string };
    expect(whose.player).toBe(account);
  });
});
