import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { chooseAction } from "../src/bots/house-cat-birdwatch";
import { createRng } from "../src/rules/rng";

import { BASE, bundle, call, connect, mint, newPerson, worker, type Client, type Device, type Sent, type Snapshot } from "./play-helpers";

import type { BirdView } from "../src/birdwatch/view";
import type { Miniflare } from "miniflare";

/* Birdwatch through the real Worker and room sockets, and the apps that can't draw it kept out. */

/** What a 1.3 app sends with every request. */
const NEW_APP = { "x-pounce-games": "cat-tower,tiles,birdwatch" };
/** A 1.2 app draws the tile game but not Birdwatch. */
const TILES_APP = { "x-pounce-games": "cat-tower,tiles" };

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

async function start(games = "tiles,birdwatch"): Promise<Miniflare> {
  const mf = await worker(script, { sent, devSpeed: 100, games });
  open.push(mf);
  return mf;
}

const create = (mf: Miniflare, device: Device, headers: Record<string, string>) => call(mf, device, "POST", "/v1/rooms", { game: "birdwatch" }, headers);
const viewOf = (s: Snapshot) => s.room.birdwatch as BirdView;

async function birdRoom(mf: Miniflare, host: Device): Promise<string> {
  const res = await create(mf, host, NEW_APP);
  expect(res.status).toBe(201);
  return ((await res.json()) as { code: string }).code;
}

describe("creating a Birdwatch table", { timeout: 30_000 }, () => {
  test("with the flag as production has it, the server refuses it, whatever the app says", async () => {
    const mf = await start("tiles");
    const phone = await mint(mf);
    expect((await create(mf, phone, NEW_APP)).status).toBe(400);
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "tiles" }, NEW_APP)).status).toBe(201);
  });

  test("with it on, only for an app that lists it; one that doesn't is told there is no such table", async () => {
    const mf = await start();
    const phone = await mint(mf);
    expect((await create(mf, phone, TILES_APP)).status).toBe(400);
    const code = await birdRoom(mf, phone);
    const join = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
      headers: { authorization: `Bearer ${phone.token}`, upgrade: "websocket", ...TILES_APP },
    });
    expect(join.status).toBe(404);
    const c = await connect(mf, code, phone, NEW_APP);
    const { room } = c.last as Snapshot;
    expect(room).toMatchObject({ code, status: "lobby", game: null, gameId: "birdwatch", options: { rules: "official" } });
    expect(room.seats.map((s) => s.kind)).toEqual(["open", "open", "open", "open", "closed", "closed"]);
    // An app that can't draw it doesn't list it.
    const listed = async (headers: Record<string, string>) =>
      ((await (await call(mf, phone, "GET", "/v1/devices/me/tables", undefined, headers)).json()) as { tables: { code: string }[] }).tables.map((t) => t.code);
    expect(await listed(TILES_APP)).not.toContain(code);
  });
});

describe("a Birdwatch hand through the room's sockets", { timeout: 120_000 }, () => {
  test("a person and three House Cats: the rule set, a swap, a whole hand, then the person leaves and the table ends", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const code = await birdRoom(mf, phone);
    const me: Client = await connect(mf, code, phone, NEW_APP);
    const jd = newPerson("JD", 1);
    me.send({ t: "claim", seat: 0, person: { id: jd.id, name: jd.name, cat: jd.cat } });
    me.send({ t: "setOptions", options: { rules: "tucker" } });
    for (const seat of [1, 2, 3]) me.send({ t: "configure", seat, kind: "bot" });
    me.send({ t: "swapSeats", seats: [0, 2] });
    await me.until((s) => s.room.options?.rules === "tucker" && s.room.seats[2]?.kind === "human" && s.room.seats[0]?.kind === "bot");
    me.send({ t: "start" });
    await me.until((s) => s.room.status === "playing" && s.room.birdwatch !== undefined);

    const rng = createRng([3, 1, 4, 1]);
    let moves = 0;
    for (;;) {
      const snap = await me.until((s) => viewOf(s).hand > 1 || viewOf(s).status === "over" || viewOf(s).turn === 2, 20_000);
      const view = viewOf(snap);
      expect(Object.keys(view.hands)).toEqual(["2"]);
      expect(view.rules).toBe("tucker");
      if (view.hand > 1 || view.status === "over") break;
      const seq = snap.seq;
      me.send({ t: "act", seat: 2, action: chooseAction(view, 2, rng) });
      await me.until((s) => s.seq > seq);
      expect(me.received.filter((m) => m.t === "error")).toEqual([]);
      moves++;
    }
    expect(moves).toBeGreaterThan(0);
    const after = viewOf(me.last as Snapshot);
    expect(after.history.length).toBeGreaterThanOrEqual(1);
    expect(after.history[0]?.taken.reduce((a, b) => a + b)).toBe(180);
    const events = me.received.flatMap((m) => (m.t === "event" && m.event.kind === "birdwatch" ? [m.event.event.kind] : []));
    for (const kind of ["bid", "bidWon", "nest", "putBack", "trump", "played", "trick", "handOver", "dealt", "turn"]) expect(events).toContain(kind);

    me.send({ t: "act", seat: 2, action: { type: "forfeit" } });
    const over = await me.until((s) => s.room.status === "over");
    expect(over.room.seats[2]).toMatchObject({ kind: "bot", left: true, person: { name: "JD" } });
    expect(viewOf(over)).toMatchObject({ status: "over", endReason: "left" });
    expect(me.received.some((m) => m.t === "event" && m.event.kind === "houseCat" && m.event.seat === 2)).toBe(true);
  });
});
