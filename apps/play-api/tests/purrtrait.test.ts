import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { WORDS } from "../src/purrtrait/words";

import { BASE, bundle, call, Client, eventually, mint, newPerson, profile, settle, worker, type Device, type Person, type Snapshot } from "./play-helpers";

import type { Stored } from "./room-storage-entry";
import type { ServerMessage } from "../src/protocol";
import type { InkOp } from "../src/purrtrait/ink";
import type { Miniflare } from "miniflare";

/** Purrtrait through the Worker and the room's Durable Object: same room only (design §5). */
let script = "";
const open: Miniflare[] = [];

beforeAll(async () => {
  // The real worker and room; the room can also hand a test every byte it stored.
  script = await bundle("./room-storage-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

/** What an app that can draw Purrtrait says. */
const PURR = { "x-pounce-games": "cat-tower,tiles,purrtrait" };
/** A near key's life at `DEV_SPEED` 100: 30 s for each of two keys, a hundred times faster. */
const FAST = 100;

async function start(options: { devSpeed?: number; games?: string; tv?: boolean; purrtraitAppLinks?: boolean; streaks?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, {
    sent: [],
    ...(options.streaks ? { streaks: true, links: true } : {}),
    tv: options.tv ?? true,
    games: options.games ?? "tiles,purrtrait",
    ...(options.devSpeed ? { devSpeed: options.devSpeed } : {}),
    ...(options.purrtraitAppLinks ? { purrtraitAppLinks: true } : {}),
  });
  open.push(mf);
  return mf;
}

const face = (p: Person) => ({ id: p.id, name: p.name, cat: p.cat });
type Near = { key: string; code: string; expiresIn: number };
const nearOf = (c: Client): Near => c.last?.room.near as Near;

/** An upgrade with whatever query, as the app opens it; the response, unaccepted. */
function upgrade(mf: Miniflare, code: string, device: Device, query = "", headers: Record<string, string> = {}) {
  return mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws${query}`, { headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", ...PURR, ...headers } });
}

async function opened(res: Response | Awaited<ReturnType<typeof upgrade>>): Promise<Client> {
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  ws.accept();
  const client = new Client(ws);
  await client.until(() => true);
  return client;
}

/** The TV makes a table and opens it as its screen. */
async function tvTable(mf: Miniflare, tv: Device): Promise<{ code: string; screen: Client }> {
  const made = await call(mf, tv, "POST", "/v1/rooms", { game: "purrtrait", screen: true }, PURR);
  expect(made.status).toBe(201);
  const { code } = (await made.json()) as { code: string };
  const screen = await opened(await upgrade(mf, code, tv, "?role=screen"));
  return { code, screen };
}

/** A phone joins with the TV's current key and sits. */
async function sit(mf: Miniflare, code: string, screen: Client, device: Device, seat: number, who: Person): Promise<Client> {
  const c = await opened(await upgrade(mf, code, device, `?near=${nearOf(screen).key}`));
  c.send({ t: "claim", seat, person: face(who) });
  await c.until((s) => s.room.seats[seat]?.kind === "human");
  return c;
}

const refusal = async (res: Awaited<ReturnType<typeof upgrade>>) => ({ status: res.status, body: (await res.json()) as unknown });
const NOT_NEAR = { status: 403, body: { error: "not_near" } };

/** A browser's socket, offered as the web player offers it: its close code once it closes. */
async function browser(mf: Miniflare, code: string, device: Device, query: string) {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws?games=cat-tower,tiles,purrtrait&${query}`, {
    headers: { upgrade: "websocket", "sec-websocket-protocol": `pounce, pounce.token.${device.token}` },
  });
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  const messages: Snapshot[] = [];
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data as string) as { t: string };
    if (m.t === "snapshot") messages.push(m as Snapshot);
  });
  ws.accept();
  return { ws, messages, closed };
}

describe("a Purrtrait table is made by its TV", { timeout: 30_000 }, () => {
  test("a phone can't make a purrtrait room; the TV can", async () => {
    const mf = await start();
    const [tv, phone] = [await mint(mf), await mint(mf)];
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "purrtrait" }, PURR)).status).toBe(400);
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "purrtrait", name: "Ours" }, PURR)).status).toBe(400);
    expect((await call(mf, tv, "POST", "/v1/rooms", { game: "purrtrait", screen: true }, PURR)).status).toBe(201);
    // Every other game still lets a phone make a table.
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "tiles" }, PURR)).status).toBe(201);
  });
});

describe("joining from the TV's code (design §5.2)", { timeout: 30_000 }, () => {
  test("a join with no key, a stale key (70 s), or the plain room code is 403 not_near and counted", async () => {
    const mf = await start({ devSpeed: FAST });
    const [tv, guesser, other] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const stale = nearOf(screen).key;
    // 70 seconds at the dev speed: the TV has moved on twice.
    await settle(70_000 / FAST);
    await eventually(() => nearOf(screen).key, (key) => key !== stale);
    expect(await refusal(await upgrade(mf, code, guesser))).toEqual(NOT_NEAR);
    expect(await refusal(await upgrade(mf, code, guesser, `?near=${stale}`))).toEqual(NOT_NEAR);
    expect(await refusal(await upgrade(mf, code, guesser, `?near=${code}`))).toEqual(NOT_NEAR);
    expect(await refusal(await upgrade(mf, code, guesser, `?near=${code}${stale.slice(0, 3)}`))).toEqual(NOT_NEAR);
    expect(await refusal(await upgrade(mf, code, guesser, "?near=not-a-key"))).toEqual(NOT_NEAR);
    expect(await refusal(await upgrade(mf, code, guesser, "?near=BBBBBBBB"))).toEqual(NOT_NEAR);
    // Six wrong guesses lock the device out, as six wrong room codes do: even the live key now.
    const locked = await upgrade(mf, code, guesser, `?near=${nearOf(screen).key}`);
    expect(locked.status).toBe(429);
    expect(((await locked.json()) as { error: string }).error).toBe("too_many_attempts");

    // A browser hears the refusal as 4403, and is let in with the live key.
    expect(await (await browser(mf, code, other, "")).closed).toBe(4403);
    const ok = await browser(mf, code, other, `near=${nearOf(screen).key}`);
    const snap = await eventually(() => ok.messages[0], Boolean);
    expect(snap?.room.gameId).toBe("purrtrait");
  });

  test("the typed 8-char code works inside 60 s, in any case", async () => {
    const mf = await start();
    const [tv, a, b, c] = [await mint(mf), await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const near = nearOf(screen);
    expect(near.code).toBe(`${code}${near.key.slice(0, 3)}`);
    expect(near.code).toHaveLength(8);
    await opened(await upgrade(mf, code, a, `?near=${near.code}`));
    await opened(await upgrade(mf, code, b, `?near=${near.code.toLowerCase()}`));
    await opened(await upgrade(mf, code, c, `?near=${near.key}`));
  });

  test("30 wrong guesses from many addresses close the typed code until the next key; the QR's key still works", async () => {
    const mf = await start();
    const [tv, late, fresh] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const { key, code: typed } = nearOf(screen);
    // Five devices, six counted misses each, every one from a new IPv6 /64, guessing the typing.
    const wrong = `${code}${typed.endsWith("BBB") ? "CCC" : "BBB"}`;
    let n = 0;
    for (let d = 0; d < 5; d++) {
      const guesser = await mint(mf);
      for (let i = 0; i < 6; i++) {
        const ip = `2001:db8:${(n += 1).toString(16)}::1`;
        const res = await upgrade(mf, code, guesser, `?near=${wrong}`, { "cf-connecting-ip": ip });
        expect(res.status).toBe(403);
      }
    }
    expect(await refusal(await upgrade(mf, code, late, `?near=${typed}`, { "cf-connecting-ip": "203.0.113.9" }))).toEqual(NOT_NEAR);
    await opened(await upgrade(mf, code, fresh, `?near=${key}`, { "cf-connecting-ip": "203.0.113.10" }));
  });

  test("a locked-out device's refused guesses don't close the typed code", async () => {
    const mf = await start();
    const [tv, guesser, late] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const { code: typed } = nearOf(screen);
    const wrong = `${code}${typed.endsWith("BBB") ? "CCC" : "BBB"}`;
    // Six counted misses lock the device out; the rest, each from a new /64, are refused uncounted.
    const statuses: number[] = [];
    for (let i = 0; i < 40; i++) {
      const ip = `2001:db8:${(i + 1).toString(16)}::1`;
      statuses.push((await upgrade(mf, code, guesser, `?near=${wrong}`, { "cf-connecting-ip": ip })).status);
    }
    expect(statuses).toEqual([...Array<number>(6).fill(403), ...Array<number>(34).fill(429)]);
    await opened(await upgrade(mf, code, late, `?near=${typed}`, { "cf-connecting-ip": "203.0.113.9" }));
  });

  test("a locked-out address's refused looks at /e/ don't close the typed code", async () => {
    const mf = await start();
    const [tv, late] = [await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const { code: typed } = nearOf(screen);
    const wrong = `${code}${typed.endsWith("BBB") ? "CCC" : "BBB"}`;
    // 21 counted misses lock the address out; the next 15 are refused uncounted.
    for (let i = 0; i < 36; i++) await mf.dispatchFetch(`${BASE}/e/${code}?near=${wrong}`, { headers: { "cf-connecting-ip": "203.0.113.50" }, redirect: "manual" });
    await opened(await upgrade(mf, code, late, `?near=${typed}`, { "cf-connecting-ip": "203.0.113.9" }));
  });

  test("addresses in one IPv6 /64 share one count", async () => {
    const mf = await start();
    const tv = await mint(mf);
    const { code } = await tvTable(mf, tv);
    // 20 misses an hour are free per address; the 21st locks the /64 out, whichever address in it.
    const statuses: number[] = [];
    for (let i = 0; i < 21; i++) {
      const guesser = await mint(mf);
      statuses.push((await upgrade(mf, code, guesser, "", { "cf-connecting-ip": `2001:db8:7:7::${(i + 1).toString(16)}` })).status);
    }
    expect(statuses).toEqual(Array<number>(21).fill(403));
    expect((await upgrade(mf, code, await mint(mf), "", { "cf-connecting-ip": "2001:db8:7:7:ffff::1" })).status).toBe(429);
    expect((await upgrade(mf, code, await mint(mf), "", { "cf-connecting-ip": "2001:db8:7:8::1" })).status).toBe(403);
  });

  test("a member reconnects with no key, long after the key it joined with", async () => {
    const mf = await start({ devSpeed: FAST });
    const [tv, a] = [await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const phone = await sit(mf, code, screen, a, 0, newPerson("Alice", 1));
    phone.ws.close();
    await settle(70_000 / FAST);
    const back = await opened(await upgrade(mf, code, a));
    expect(back.last?.room.seats[0]?.yours).toBe(true);
    // The TV comes back with no key too: it is the table's screen.
    screen.ws.close();
    await opened(await upgrade(mf, code, tv, "?role=screen"));
  });

  test("only the screen's snapshot has near, and the screen alone hears each new key", async () => {
    const mf = await start({ devSpeed: FAST });
    const [tv, a] = [await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const first = nearOf(screen);
    expect(first.key).toMatch(/^[BCDFGHJKLMNPQRTVWXZ2346789]{8}$/);
    expect(first.expiresIn).toBeGreaterThan(0);
    expect(first.expiresIn).toBeLessThanOrEqual(30_000 / FAST);
    const phone = await sit(mf, code, screen, a, 0, newPerson("Alice", 1));
    expect(phone.last?.room.near).toBeUndefined();
    const seen = phone.received.length;
    await eventually(() => nearOf(screen).key, (key) => key !== first.key);
    expect(phone.received.slice(seen).some((m) => m.t === "snapshot" && m.room.near !== undefined)).toBe(false);
    expect(phone.received.every((m) => m.t !== "snapshot" || m.room.near === undefined)).toBe(true);
  });
});

describe("Play again at a Purrtrait table", { timeout: 30_000 }, () => {
  test("both phones follow with no key, and the TV follows as the screen", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    // Signed in: their seats are their players', which only a device that speaks for them controls.
    const [alice, bo] = [newPerson("Alice", 1), newPerson("Bo", 2)];
    await profile(mf, a, [alice]);
    await profile(mf, b, [bo]);
    const pa = await sit(mf, code, screen, a, 0, alice);
    const pb = await sit(mf, code, screen, b, 1, bo);
    pa.send({ t: "start" });
    await pa.until((s) => s.room.purrtrait?.phase === "choosing");
    pa.send({ t: "act", seat: 0, action: { type: "forfeit" } });
    await pb.until((s) => s.room.status === "over");
    pb.send({ t: "rematch" });
    const next = (await pb.find<{ t: "rematch"; code: string }>((m) => m.t === "rematch")).code;
    expect(next).not.toBe(code);
    const tvNext = await opened(await upgrade(mf, next, tv, "?role=screen"));
    expect(tvNext.last?.room.near).toBeDefined();
    // The seats move one on at the new table; each phone still has its own.
    for (const device of [a, b]) {
      const back = await opened(await upgrade(mf, next, device));
      expect(back.last?.room.near).toBeUndefined();
      expect(back.last?.room.seats.filter((s) => s.yours)).toHaveLength(1);
    }
    // A stranger still needs the key at the new table.
    expect(await refusal(await upgrade(mf, next, await mint(mf)))).toEqual(NOT_NEAR);
  });
});

describe("the host removes a player (design §10.2)", { timeout: 30_000 }, () => {
  const REMOVED = { status: 403, body: { error: "removed" } };
  const closing = (c: Client) => new Promise<number>((resolve) => c.ws.addEventListener("close", (e) => resolve(e.code)));

  test("remove in the lobby opens the seat and the device is refused after, even with a fresh key", async () => {
    const mf = await start();
    const [tv, host, guest, intruder] = [await mint(mf), await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const h = await sit(mf, code, screen, host, 0, newPerson("Alice", 1));
    const g = await sit(mf, code, screen, guest, 1, newPerson("Bo", 2));
    h.send({ t: "configure", seat: 2, kind: "open" });
    await h.until((s) => s.room.seats[2]?.kind === "open");
    const x = await sit(mf, code, screen, intruder, 2, newPerson("Cy", 3));
    // Only the host may.
    g.send({ t: "remove", seat: 2 });
    expect(await g.find((m) => m.t === "error")).toEqual({ t: "error", code: "not_allowed" });
    const closed = closing(x);
    h.send({ t: "remove", seat: 2 });
    expect(await closed).toBe(4403);
    await h.until((s) => s.room.seats[2]?.kind === "open");
    // Refused with the TV's live key, as often as it tries: never counted as a wrong guess.
    for (let i = 0; i < 8; i++) expect(await refusal(await upgrade(mf, code, intruder, `?near=${nearOf(screen).key}`))).toEqual(REMOVED);
    expect(await refusal(await upgrade(mf, code, intruder))).toEqual(REMOVED);
    // A browser hears it as 4403.
    expect(await (await browser(mf, code, intruder, `near=${nearOf(screen).key}`)).closed).toBe(4403);
    // Somebody else may take the seat.
    await sit(mf, code, screen, await mint(mf), 2, newPerson("Di", 4));
  });

  test("remove in a game skips the seat; Play again keeps it out", async () => {
    const mf = await start();
    const [tv, a, b, c] = [await mint(mf), await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const [alice, bo, cy] = [newPerson("Alice", 1), newPerson("Bo", 2), newPerson("Cy", 3)];
    await profile(mf, a, [alice]);
    await profile(mf, b, [bo]);
    await profile(mf, c, [cy]);
    const pa = await sit(mf, code, screen, a, 0, alice);
    const pb = await sit(mf, code, screen, b, 1, bo);
    pa.send({ t: "configure", seat: 2, kind: "open" });
    await pa.until((s) => s.room.seats[2]?.kind === "open");
    const pc = await sit(mf, code, screen, c, 2, cy);
    const guest = await mint(mf);
    pa.send({ t: "configure", seat: 3, kind: "open" });
    await pa.until((s) => s.room.seats[3]?.kind === "open");
    const pg = await sit(mf, code, screen, guest, 3, newPerson("Di", 4));
    pa.send({ t: "start" });
    await pa.until((s) => s.room.purrtrait?.phase === "choosing");
    const closed = closing(pc);
    pa.send({ t: "remove", seat: 2 });
    expect(await closed).toBe(4403);
    await pa.until((s) => s.room.purrtrait?.out[2] === true);
    expect(pa.last?.room.status).toBe("playing");
    // A removed guest's phone (no player of its own) loses the table from its list.
    const codes = async (d: Device) => ((await (await call(mf, d, "GET", "/v1/devices/me/tables", undefined, PURR)).json()) as { tables: { code: string }[] }).tables.map((t) => t.code);
    expect(await codes(guest)).toContain(code);
    const gone = closing(pg);
    pa.send({ t: "remove", seat: 3 });
    expect(await gone).toBe(4403);
    expect(await eventually(() => codes(guest), (list) => !list.includes(code))).not.toContain(code);
    // The removed player on another device, with the TV's live key: refused too.
    const y = await mint(mf);
    await profile(mf, y, [cy]);
    expect(await refusal(await upgrade(mf, code, y, `?near=${nearOf(screen).key}`))).toEqual(REMOVED);
    // A removed signed-in player's other devices drop the table: their player's list loses it.
    expect(await eventually(() => codes(y), (list) => !list.includes(code))).not.toContain(code);
    pb.send({ t: "act", seat: 1, action: { type: "forfeit" } });
    await pa.until((s) => s.room.status === "over");
    pa.send({ t: "rematch" });
    const next = (await pa.find<{ t: "rematch"; code: string }>((m) => m.t === "rematch")).code;
    const tvNext = await opened(await upgrade(mf, next, tv, "?role=screen"));
    // Nor does it come back, as the old table or the next one, after Play again.
    await settle();
    expect(await codes(y)).not.toContain(code);
    expect(await codes(y)).not.toContain(next);
    const back = await opened(await upgrade(mf, next, a));
    expect(back.last?.room.seats.filter((s) => s.kind === "human").map((s) => s.person?.name)).toEqual(["Bo", "Alice"]);
    // Out of the new table too, with its TV's live key.
    expect(await refusal(await upgrade(mf, next, c, `?near=${nearOf(tvNext).key}`))).toEqual(REMOVED);
  });
});

describe("no requests to play at a Purrtrait table (design §5.1)", { timeout: 30_000 }, () => {
  test("a pair that drew at a Purrtrait table can't send a request to play to it", async () => {
    const mf = await start({ streaks: true, devSpeed: 10 });
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const [alice, bo] = [newPerson("Alice", 1), newPerson("Bo", 2)];
    await profile(mf, a, [alice], { apns: "a".repeat(64) });
    await profile(mf, b, [bo], { apns: "b".repeat(64) });
    const pa = await sit(mf, code, screen, a, 0, alice);
    const pb = await sit(mf, code, screen, b, 1, bo);
    pa.send({ t: "start" });
    // Each draws a turn that is guessed: a turn each makes them a pair, as at any table.
    for (const [drawer, guesser, c] of [[0, 1, pa], [1, 0, pb]] as const) {
      await c.until((s) => s.room.purrtrait?.phase === "choosing" && s.room.purrtrait.drawer === drawer);
      c.send({ t: "act", seat: drawer, action: { type: "choose", level: "easy" } });
      await c.until((s) => s.room.purrtrait?.phase === "drawing");
      c.send({ t: "act", seat: drawer, action: { type: "gotIt", seat: guesser } });
    }
    const streak = await pa.find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
    const res = await call(mf, a, "POST", `/v1/pounces?person=${alice.id}`, { to: streak.pair, target: { table: code } });
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: "not_shared" });
  });
});

describe("one TV: the host can swap it (design §5.1)", { timeout: 30_000 }, () => {
  /** The TV asks for a link; a phone links it to `room`. */
  async function link(mf: Miniflare, tv: Device, phone: Device, room: string): Promise<Response> {
    const made = await call(mf, tv, "POST", "/v1/screens", {});
    expect(made.status).toBe(201);
    const { token } = (await made.json()) as { token: string };
    return call(mf, phone, "POST", "/v1/screens/link", { token, room });
  }

  test("the host links a new TV and the old one is refused; anyone else gets not_allowed", async () => {
    const mf = await start();
    const [tv, tv2, tv3, host, guest, stranger] = [await mint(mf), await mint(mf), await mint(mf), await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const hostPhone = await sit(mf, code, screen, host, 0, newPerson("Alice", 1));
    await hostPhone.until((s) => s.room.youAreHost);
    await sit(mf, code, screen, guest, 1, newPerson("Bo", 2));

    // Seated but not the host: not_allowed. Not at the table at all: as for no table.
    const byGuest = await link(mf, tv3, guest, code);
    expect(byGuest.status).toBe(403);
    expect(await byGuest.json()).toEqual({ error: "not_allowed" });
    const byStranger = await link(mf, tv3, stranger, code);
    expect(byStranger.status).toBe(403);
    expect(await byStranger.json()).toEqual({ error: "not_seated" });

    const closed = new Promise<number>((resolve) => screen.ws.addEventListener("close", (e) => resolve(e.code)));
    const byHost = await link(mf, tv2, host, code);
    expect(byHost.status).toBe(200);
    expect(await closed).toBe(4403);
    const again = await upgrade(mf, code, tv, "?role=screen");
    expect(again.status).toBe(403);
    expect(await again.json()).toEqual({ error: "not_screen" });
    // Nor does the old TV get in as a phone without a key.
    expect(await refusal(await upgrade(mf, code, tv))).toEqual(NOT_NEAR);

    const next = await opened(await upgrade(mf, code, tv2, "?role=screen"));
    expect(nearOf(next).key).toMatch(/^[BCDFGHJKLMNPQRTVWXZ2346789]{8}$/);
    expect(next.last?.room.screen).toBe(true);
  });
});

describe("the links to a Purrtrait table", { timeout: 30_000 }, () => {
  test("/j/ for a purrtrait room has no join button", async () => {
    const mf = await start();
    const tv = await mint(mf);
    const { code } = await tvTable(mf, tv);
    const res = await mf.dispatchFetch(`${BASE}/j/${code}`);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("<h1>Scan the code on the TV.</h1>");
    expect(html.match(/<a [^>]*>/g)).toBeNull();
    expect(html).not.toContain(code);
  });

  test("/e/ redirects to /play/e/ with near, and says to scan the TV without a live key", async () => {
    const mf = await start();
    const tv = await mint(mf);
    const { code, screen } = await tvTable(mf, tv);
    const { key } = nearOf(screen);
    for (const near of [key, key.toLowerCase()]) {
      const res = await mf.dispatchFetch(`${BASE}/e/${code}?near=${near}`, { redirect: "manual" });
      expect(res.status).toBe(302);
      expect(res.headers.get("location")).toBe(`${BASE}/play/e/${code}?near=${key}`);
      expect(res.headers.get("cache-control")).toBe("no-store");
    }
    for (const path of [`/e/${code}`, `/e/${code}?near=BBBBBBBB`, `/e/${code}?near=<script>`, `/e/BBBBB?near=${key}`]) {
      const res = await mf.dispatchFetch(`${BASE}${path}`, { redirect: "manual" });
      expect(res.status, path).toBe(200);
      expect(await res.text(), path).toContain("<h1>Scan the code on the TV.</h1>");
    }
    for (const path of ["/e/bad!", `/e/${code}/x`, "/e/"]) {
      expect((await mf.dispatchFetch(`${BASE}${path}`, { redirect: "manual" })).status, path).toBe(404);
    }
  });

  test("/e/ is a 404 while Purrtrait tables can't be dealt", async () => {
    for (const mf of [await start({ games: "tiles" }), await start({ tv: false })]) {
      expect((await mf.dispatchFetch(`${BASE}/e/BCDFG?near=BCDFGHJK`, { redirect: "manual" })).status).toBe(404);
    }
  });

  test("the association lists /e/* only with PURRTRAIT_APPLINKS on", async () => {
    const components = async (mf: Miniflare) =>
      ((await (await mf.dispatchFetch(`${BASE}/.well-known/apple-app-site-association`)).json()) as { applinks: { details: { components: { "/": string }[] }[] } }).applinks.details[0]?.components.map(
        (c) => c["/"],
      );
    expect(await components(await start())).not.toContain("/e/*");
    expect(await components(await start({ purrtraitAppLinks: true }))).toEqual(["/j/*", "/p/*", "/e/*"]);
    // Not while Purrtrait can't be dealt, whatever the flag says.
    expect(await components(await start({ purrtraitAppLinks: true, games: "tiles" }))).not.toContain("/e/*");
  });
});

describe("a drawing is never stored (design §6.5, §8.1)", { timeout: 30_000 }, () => {
  const stored = async (mf: Miniflare, code: string) => (await (await mf.dispatchFetch(`${BASE}/__test/room-storage?code=${code}`)).json()) as Stored;

  /** Every string and every key in what the room stored, its SQL columns' JSON opened up. */
  function contents(dump: Stored): { strings: Set<string>; keys: Set<string>; inkLike: unknown[][] } {
    const strings = new Set<string>();
    const keys = new Set<string>();
    const inkLike: unknown[][] = [];
    const walk = (v: unknown): void => {
      if (typeof v === "string") {
        strings.add(v);
        if (/^[[{]/.test(v)) {
          try {
            walk(JSON.parse(v));
          } catch {
            // Not JSON: a plain string, already kept.
          }
        }
      } else if (Array.isArray(v)) {
        if (["s", "p", "u", "c"].includes(v[0] as string) && v.slice(1).every((n) => typeof n === "number")) inkLike.push(v);
        v.forEach(walk);
      } else if (v !== null && typeof v === "object") {
        for (const [k, inner] of Object.entries(v)) {
          keys.add(k);
          walk(inner);
        }
      }
    };
    walk(dump.kv);
    walk(dump.sql);
    return { strings, keys, inkLike };
  }

  test("storage after a full game holds no ink and no unrevealed word", async () => {
    const mf = await start({ devSpeed: 10 });
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const { code, screen } = await tvTable(mf, tv);
    const phones = [await sit(mf, code, screen, a, 0, newPerson("Alice", 1)), await sit(mf, code, screen, b, 1, newPerson("Bo", 2))];
    phones[0]?.send({ t: "start" });
    const words = new Set(WORDS.map((w) => w.word));
    const revealed = new Set<string>();
    let midTurn: Stored | null = null;
    // Two seats, two rounds: four turns, each drawn and guessed.
    for (let turn = 0; turn < 4; turn++) {
      const s = await screen.until((m) => m.room.purrtrait?.phase === "choosing" && m.room.purrtrait.turn.endsWith(`:${turn}`));
      const drawer = s.room.purrtrait?.drawer as number;
      const phone = phones[drawer] as Client;
      phone.send({ t: "act", seat: drawer, action: { type: "choose", level: turn % 2 === 0 ? "tricky" : "easy" } });
      const drawing = await phone.until((m) => m.room.purrtrait?.phase === "drawing" && m.room.purrtrait.youDraw === true);
      const key = drawing.room.purrtrait?.turn as string;
      const strokes: InkOp[][] = [[["s", 0, turn, 1, 384, 300, 40, 0, 30, 30]], [["p", 0, 2, 2, -5, 9]], [["s", 1, 3, 2, 100, 100, 7, 7]], [["u", 1]]];
      for (const ops of strokes) phone.send({ t: "ink", seat: drawer, turn: key, ops });
      // The TV has the whole drawing: every message was taken and relayed.
      await eventually(() => screen.received.filter((m) => m.t === "ink" && m.turn === key).length, (n) => n === strokes.length);
      // While the drawing is live it is in the room's memory, and nowhere in its storage.
      if (turn === 0) {
        midTurn = await stored(mf, code);
        const { strings, keys, inkLike } = contents(midTurn);
        expect(keys.has("ops")).toBe(false);
        expect(inkLike).toEqual([]);
        expect([...strings].filter((v) => words.has(v))).toEqual([]);
      }
      phone.send({ t: "act", seat: drawer, action: { type: "gotIt", seat: 1 - drawer } });
      const reveal = await screen.until((m) => m.room.purrtrait?.phase === "reveal" || m.room.purrtrait?.phase === "over");
      revealed.add(reveal.room.purrtrait?.last?.word as string);
    }
    await screen.until((m) => m.room.status === "over");
    const dump = await stored(mf, code);
    // The room did store its game (so the check reads real storage), with its revealed words.
    expect(midTurn).not.toBeNull();
    expect(Object.keys(dump.sql)).toContain("room");
    const { strings, keys, inkLike } = contents(dump);
    expect(strings.has("purrtrait")).toBe(true);
    expect(keys.has("ops")).toBe(false);
    expect(inkLike).toEqual([]);
    const storedWords = [...strings].filter((v) => words.has(v));
    expect(storedWords.length).toBeGreaterThan(0);
    for (const word of storedWords) expect(revealed.has(word), word).toBe(true);
  });
});

describe("the privacy policy follows the flag (design §8.2)", { timeout: 30_000 }, () => {
  test("/privacy says what happens to a drawing only while Purrtrait tables can be dealt", async () => {
    const page = async (mf: Miniflare) => (await mf.dispatchFetch(`${BASE}/privacy`)).text();
    expect(await page(await start())).toContain("keeps them only until the turn ends");
    expect(await page(await start({ games: "tiles" }))).not.toContain("Purrtrait");
    expect(await page(await start({ tv: false }))).not.toContain("Purrtrait");
  });
});
