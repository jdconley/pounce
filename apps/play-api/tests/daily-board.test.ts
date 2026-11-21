import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, eventually, mint, newPerson, PLAYER_ID_JSON, profile, worker, type Device, type Person } from "./play-helpers";

import type { Miniflare } from "miniflare";

/** The board socket, TV board links and watching (daily games design §6, §8), through the Worker (`DAILY` and `TV` on). */
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

type Msg = { t: string; [k: string]: unknown };

/** A socket: every message it hears, and its close code once it closes. */
async function listen(res: Response) {
  expect(res.status).toBe(101);
  const ws = (res as unknown as { webSocket: WebSocket & { accept(): void } }).webSocket;
  const heard: Msg[] = [];
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
  ws.addEventListener("message", (e) => heard.push(JSON.parse(e.data as string) as Msg));
  ws.accept();
  const find = (match: (m: Msg) => boolean) => eventually(() => heard.find(match), (m) => m !== undefined) as Promise<Msg>;
  return { ws, heard, closed, find, send: (v: unknown) => ws.send(JSON.stringify(v)) };
}

async function someone(mf: Miniflare, name: string): Promise<{ device: Device; person: Person; id: string }> {
  const device = await mint(mf);
  const person = newPerson(name, 3);
  const ids = await profile(mf, device, [person]);
  return { device, person, id: ids[person.id] as string };
}

const pairUp = async (mf: Miniflare, a: string, b: string) => expect((await mf.dispatchFetch(`${BASE}/__test/connect?a=${a}&b=${b}`)).status).toBe(204);

type Start = { run: string; level: number; date: string };
async function begin(mf: Miniflare, who: { device: Device; person: Person }): Promise<Start> {
  const res = await call(mf, who.device, "POST", `/v1/daily/test/start?person=${who.person.id}`);
  expect(res.status).toBe(200);
  return (await res.json()) as Start;
}
const steps = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => ({ k: "step", n: from + i }));
const send = (mf: Miniflare, who: { device: Device; person: Person }, run: string, from: number, moves: unknown[]) =>
  call(mf, who.device, "POST", `/v1/daily/runs/${run}/moves?person=${who.person.id}`, { from, moves });
const showOnTv = (mf: Miniflare, who: { device: Device; person: Person }, run: string, on: boolean) =>
  call(mf, who.device, "PUT", `/v1/daily/runs/${run}/tv?person=${who.person.id}`, { on });

/** A TV: its device and a link it shows, waiting on it. */
async function tvWaiting(mf: Miniflare) {
  const tv = await mint(mf);
  const res = await call(mf, tv, "POST", "/v1/screens", {});
  expect(res.status).toBe(201);
  const link = (await res.json()) as { token: string; code: string };
  const waiting = await listen((await mf.dispatchFetch(`${BASE}/v1/screens/${link.token}/ws`, { headers: { authorization: `Bearer ${tv.token}`, upgrade: "websocket" } })) as unknown as Response);
  return { tv, link, waiting };
}

/** A phone links a TV to its person's board; the TV's board token. */
async function linkBoard(mf: Miniflare, phone: { device: Device; person: Person }, how: "token" | "code" = "token") {
  const t = await tvWaiting(mf);
  const body = how === "token" ? { token: t.link.token, board: true } : { code: t.link.code.toLowerCase(), board: true };
  const res = await call(mf, phone.device, "POST", `/v1/screens/link?person=${phone.person.id}`, body);
  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ linked: true });
  const told = await t.waiting.find((m) => m.t === "board");
  expect(told.token).toMatch(/^[A-Za-z0-9_-]{22}$/);
  return { tv: t.tv, board: told.token as string };
}

const tvSocket = async (mf: Miniflare, tv: Device, board: string) =>
  listen((await mf.dispatchFetch(`${BASE}/v1/daily/board/ws?board=${board}`, { headers: { authorization: `Bearer ${tv.token}`, upgrade: "websocket" } })) as unknown as Response);
const phoneSocket = async (mf: Miniflare, who: { device: Device; person: Person }) =>
  listen(
    (await mf.dispatchFetch(`${BASE}/v1/daily/board/ws?person=${who.person.id}`, {
      headers: { authorization: `Bearer ${who.device.token}`, upgrade: "websocket" },
    })) as unknown as Response,
  );

/** Every key anywhere in a value. */
function keys(v: unknown): string[] {
  if (Array.isArray(v)) return v.flatMap(keys);
  if (typeof v !== "object" || v === null) return [];
  return Object.entries(v).flatMap(([k, inner]) => [k, ...keys(inner)]);
}

describe("linking a TV to a board", { timeout: 30_000 }, () => {
  test("a phone links a TV to its board by token and by code", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const byToken = await linkBoard(mf, mom, "token");
    const byCode = await linkBoard(mf, mom, "code");
    expect(byCode.board).not.toBe(byToken.board);
    // A spent link can't be used again.
    const t = await tvWaiting(mf);
    expect((await call(mf, mom.device, "POST", `/v1/screens/link?person=${mom.person.id}`, { token: t.link.token, board: true })).status).toBe(200);
    expect((await call(mf, mom.device, "POST", `/v1/screens/link?person=${mom.person.id}`, { token: t.link.token, board: true })).status).toBe(404);
  });

  test("a board link needs a person the device speaks for, and a well-formed body", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const stranger = await mint(mf);
    const t = await tvWaiting(mf);
    expect((await call(mf, stranger, "POST", `/v1/screens/link?person=${mom.person.id}`, { token: t.link.token, board: true })).status).toBe(403);
    for (const body of [{ token: t.link.token, board: false }, { token: t.link.token, board: true, room: "ABCDE" }, { board: true }]) {
      expect((await call(mf, mom.device, "POST", `/v1/screens/link?person=${mom.person.id}`, body)).status, JSON.stringify(body)).toBe(400);
    }
  });

  test("the TV gets the board snapshot, then live results", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    const { tv, board } = await linkBoard(mf, mom);
    const screen = await tvSocket(mf, tv, board);
    const snapshot = await screen.find((m) => m.t === "board");
    expect(snapshot.board).toMatchObject({ games: [{ game: "test", rows: [] }], dish: { rows: [] } });
    const s = await begin(mf, kid);
    await send(mf, kid, s.run, 0, steps(1, 3 + s.level));
    const result = await screen.find((m) => m.t === "result");
    expect(result).toMatchObject({ player: expect.stringMatching(/^pr_/) as string, result: { outcome: "solved", game: "test" } });
    // A fresh snapshot follows each result, with the Dish worked out.
    await eventually(() => screen.heard.filter((m) => m.t === "board").length, (n) => n >= 2);
    expect(screen.heard.filter((m) => m.t === "board").at(-1)?.board).toMatchObject({ dish: { rows: [{ name: "Kid", points: 4 }] } });
    expect(JSON.stringify(screen.heard)).not.toMatch(PLAYER_ID_JSON);
  });

  test("a TV board token lasts 30 days and dies on revoke", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const { tv, board } = await linkBoard(mf, mom);
    const resolve = async (device: Device, now: number) =>
      (await (await mf.dispatchFetch(`${BASE}/__test/board-token?token=${board}&device=${device.token.split(".")[1]}&now=${now}`)).json()) as { player: string | null };
    const day = 86_400_000;
    expect((await resolve(tv, Date.now() + 29 * day)).player).toBe(mom.id);
    expect((await resolve(tv, Date.now() + 31 * day)).player).toBeNull();
    // Another device can't use the TV's token.
    expect((await resolve(mom.device, Date.now())).player).toBeNull();
    const screen = await tvSocket(mf, tv, board);
    await screen.find((m) => m.t === "board");
    expect((await call(mf, mom.device, "DELETE", `/v1/daily/board/tv?person=${mom.person.id}`)).status).toBe(204);
    await screen.closed;
    const again = await mf.dispatchFetch(`${BASE}/v1/daily/board/ws?board=${board}`, { headers: { authorization: `Bearer ${tv.token}`, upgrade: "websocket" } });
    expect(again.status).toBe(404);
  });

  test("a TV socket's other messages are not_allowed", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const { tv, board } = await linkBoard(mf, mom);
    const screen = await tvSocket(mf, tv, board);
    await screen.find((m) => m.t === "board");
    screen.send({ t: "ping" });
    await screen.find((m) => m.t === "pong");
    screen.send({ t: "move", moves: [] });
    expect(await screen.find((m) => m.t === "error")).toEqual({ t: "error", error: "not_allowed" });
  });

  test("a browser TV and a browser phone open their board sockets with subprotocols", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const { tv, board } = await linkBoard(mf, mom);
    const browser = (device: Device, query: string) =>
      mf.dispatchFetch(`${BASE}/v1/daily/board/ws${query}`, { headers: { upgrade: "websocket", "sec-websocket-protocol": `pounce, pounce.token.${device.token}` } });
    const screen = await listen((await browser(tv, `?board=${board}`)) as unknown as Response);
    expect((await screen.find((m) => m.t === "board")).board).toMatchObject({ games: [{ game: "test" }] });
    const phone = await listen((await browser(mom.device, `?person=${mom.person.id}`)) as unknown as Response);
    await phone.find((m) => m.t === "board");
  });

  test("a board socket without a board token or person is refused", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const tv = await mint(mf);
    const bad = await mf.dispatchFetch(`${BASE}/v1/daily/board/ws?board=${"A".repeat(22)}`, { headers: { authorization: `Bearer ${tv.token}`, upgrade: "websocket" } });
    expect(bad.status).toBe(404);
    const plain = await call(mf, mom.device, "GET", `/v1/daily/board/ws?person=${mom.person.id}`);
    expect(plain.status).toBe(426);
  });
});

describe("live progress and watching", { timeout: 30_000 }, () => {
  test("progress messages never carry state", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    await pairUp(mf, mom.id, kid.id);
    const phone = await phoneSocket(mf, mom);
    await phone.find((m) => m.t === "board");
    const s = await begin(mf, kid);
    await send(mf, kid, s.run, 0, steps(1, 2));
    const progress = await phone.find((m) => m.t === "progress");
    expect(progress).toEqual({ t: "progress", player: expect.stringMatching(/^pr_/) as string, game: "test", progress: 2 / (3 + s.level) });
    expect(keys(progress)).not.toContain("state");
    expect(keys(progress)).not.toContain("target");
    // The board shows Kid playing, with progress and no result.
    const board = (await (await call(mf, mom.device, "GET", `/v1/daily/board?person=${mom.person.id}`)).json()) as { games: { rows: unknown[] }[] };
    expect(board.games[0]?.rows).toEqual([{ player: progress.player, name: "Kid", cat: 3, rank: null, result: null, playing: { progress: progress.progress } }]);
    expect(phone.heard.some((m) => m.t === "watch" || m.t === "watchOffer")).toBe(false);
  });

  test("watch frames go out only after tv: on, and only to TVs whose board includes the player", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    const stranger = await someone(mf, "Stranger");
    await pairUp(mf, mom.id, kid.id);
    const momTv = await linkBoard(mf, mom);
    const strangerTv = await linkBoard(mf, stranger);
    const family = await tvSocket(mf, momTv.tv, momTv.board);
    const other = await tvSocket(mf, strangerTv.tv, strangerTv.board);
    await family.find((m) => m.t === "board");
    await other.find((m) => m.t === "board");

    const s = await begin(mf, kid);
    await send(mf, kid, s.run, 0, steps(1, 1));
    await family.find((m) => m.t === "progress");
    expect(family.heard.some((m) => m.t === "watch" || m.t === "watchOffer")).toBe(false);

    expect((await showOnTv(mf, kid, s.run, true)).status).toBe(204);
    expect(await family.find((m) => m.t === "watchOffer")).toEqual({ t: "watchOffer", player: expect.stringMatching(/^pr_/) as string, name: "Kid", cat: 3, game: "test" });
    expect(await family.find((m) => m.t === "watch")).toMatchObject({ t: "watch", game: "test", state: { n: 1 } });
    await send(mf, kid, s.run, 1, steps(2, 2));
    await eventually(() => family.heard.filter((m) => m.t === "watch").at(-1), (m) => (m?.state as { n: number } | undefined)?.n === 2);
    await send(mf, kid, s.run, 2, steps(3, 3 + s.level));
    expect(await family.find((m) => m.t === "watchEnd")).toMatchObject({ t: "watchEnd", game: "test", result: { outcome: "solved" } });

    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(other.heard.filter((m) => m.t !== "board")).toEqual([]);
  });

  test("turning Show on TV off ends the watch", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const momTv = await linkBoard(mf, mom);
    const screen = await tvSocket(mf, momTv.tv, momTv.board);
    await screen.find((m) => m.t === "board");
    const s = await begin(mf, mom);
    await showOnTv(mf, mom, s.run, true);
    await screen.find((m) => m.t === "watchOffer");
    await showOnTv(mf, mom, s.run, false);
    expect(await screen.find((m) => m.t === "watchEnd")).toEqual({ t: "watchEnd", player: "me", game: "test", result: null });
    await send(mf, mom, s.run, 0, steps(1, 1));
    await screen.find((m) => m.t === "progress");
    expect(screen.heard.filter((m) => m.t === "watch")).toHaveLength(1);
  });
});

describe("how many TVs are watching", { timeout: 30_000 }, () => {
  test("phones see how many TVs show a board they're on, and hear when it changes", async () => {
    const mf = await start();
    const mom = await someone(mf, "Mom");
    const kid = await someone(mf, "Kid");
    const stranger = await someone(mf, "Stranger");
    await pairUp(mf, mom.id, kid.id);
    const phone = await phoneSocket(mf, mom);
    expect((await phone.find((m) => m.t === "board")).board).toMatchObject({ tvs: 0 });

    // A TV showing Kid's board counts for Mom: Kid's watch offers reach it.
    const kidTv = await linkBoard(mf, kid);
    const screen = await tvSocket(mf, kidTv.tv, kidTv.board);
    await screen.find((m) => m.t === "board");
    expect(await phone.find((m) => m.t === "tvs")).toEqual({ t: "tvs", count: 1 });
    const read = async () => (await (await call(mf, mom.device, "GET", `/v1/daily/board?person=${mom.person.id}`)).json()) as { tvs: number };
    expect((await read()).tvs).toBe(1);

    // A TV of someone Mom isn't paired with doesn't.
    const strangerTv = await linkBoard(mf, stranger);
    const other = await tvSocket(mf, strangerTv.tv, strangerTv.board);
    await other.find((m) => m.t === "board");
    expect((await read()).tvs).toBe(1);

    // Mom's own TV counts too; then both go.
    const momTv = await linkBoard(mf, mom);
    const own = await tvSocket(mf, momTv.tv, momTv.board);
    await own.find((m) => m.t === "board");
    await phone.find((m) => m.t === "tvs" && m.count === 2);
    screen.ws.close(1000, "bye");
    await phone.find((m) => m.t === "tvs" && m.count === 1);
    expect((await call(mf, mom.device, "DELETE", `/v1/daily/board/tv?person=${mom.person.id}`)).status).toBe(204);
    await phone.find((m) => m.t === "tvs" && m.count === 0);
    expect((await read()).tvs).toBe(0);
    // Only changes are sent, and never to a TV.
    expect(phone.heard.filter((m) => m.t === "tvs").map((m) => m.count)).toEqual([1, 2, 1, 0]);
    expect(other.heard.some((m) => m.t === "tvs")).toBe(false);
  });
});
