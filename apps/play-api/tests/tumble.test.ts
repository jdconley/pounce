import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { newBox } from "../src/tumble/box";
import { restingY } from "../src/tumble/box";
import { toyAt } from "../src/tumble/queue";

import { BASE, bundle, call, connect, mint, newPerson, worker, type Client, type Device, type Sent, type Snapshot } from "./play-helpers";

import type { TumbleView } from "../src/games/tumble";
import type { Seed } from "../src/rules/rng";
import type { ClientEvent, TumbleRelay, TumbleSync } from "../src/tumble/wire";
import type { Miniflare } from "miniflare";

/* Toy Tumble through the real Worker and room sockets: which apps get it, and a round's live stream. */

const GAMES = "cat-tower,tiles,birdwatch,tumble";
const app = (platform: string, version: string) => ({ "x-pounce-games": GAMES, "x-pounce-app": `platform=${platform}; version=${version}; build=1; protocol=1` });
const IOS_14 = app("ios", "1.4");
const IOS_13 = app("ios", "1.3");
const WEB = app("web", "900");

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

async function start(games: string, devSpeed?: number): Promise<Miniflare> {
  const mf = await worker(script, { sent, games, ...(devSpeed ? { devSpeed } : {}) });
  open.push(mf);
  return mf;
}

const create = (mf: Miniflare, device: Device, headers: Record<string, string>) => call(mf, device, "POST", "/v1/rooms", { game: "tumble" }, headers);
const tumbleOf = (s: Snapshot) => s.room.tumble as TumbleView;

describe("which apps get Toy Tumble", { timeout: 30_000 }, () => {
  test("with the flag as production has it, nobody can make a table", async () => {
    const mf = await start("tiles,birdwatch");
    const phone = await mint(mf);
    expect((await create(mf, phone, IOS_14)).status).toBe(400);
    expect((await create(mf, phone, WEB)).status).toBe(400);
  });

  test("with it on: an app from 1.4 and the web player, never an older app, whatever it lists", async () => {
    const mf = await start("tiles,birdwatch,tumble");
    const phone = await mint(mf);
    expect((await create(mf, phone, IOS_13)).status).toBe(400);
    expect((await create(mf, phone, app("tvos", "1.3"))).status).toBe(400);
    expect((await create(mf, phone, WEB)).status).toBe(201);
    const res = await create(mf, phone, IOS_14);
    expect(res.status).toBe(201);
    const { code } = (await res.json()) as { code: string };
    // A 1.3 app is told the table is a game it can't draw.
    const join = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, { headers: { authorization: `Bearer ${phone.token}`, upgrade: "websocket", ...IOS_13 } });
    expect(join.status).toBe(426);
    const c = await connect(mf, code, phone, IOS_14);
    expect(c.last?.room).toMatchObject({ gameId: "tumble", options: { cats: "easy" } });
  });

  test("a dev server lets an older app in", async () => {
    const mf = await start("tiles,birdwatch,tumble", 100);
    const phone = await mint(mf);
    expect((await create(mf, phone, IOS_13)).status).toBe(201);
  });
});

/** A legal set-down of seat `seat`'s first toy. */
function firstDrop(s: TumbleView, seat: number): ClientEvent {
  const box = newBox((s.trickSeeds as Seed[])[seat] as Seed);
  const toy = toyAt(s.roundSeed as Seed, box.next);
  for (let x = -2; x < 12; x++) {
    const y = restingY(box, toy, 0, x);
    if (y !== null) return ["l", box.next, 0, x, y, 500, []];
  }
  throw new Error("nowhere");
}

describe("a round through the room's sockets", { timeout: 60_000 }, () => {
  test("counts down, plays, relays a set-down to the other phone, and ticks", async () => {
    const mf = await start("tiles,birdwatch,tumble");
    const [phone, tablet] = [await mint(mf), await mint(mf)];
    const { code } = (await (await create(mf, phone, IOS_14)).json()) as { code: string };
    const a: Client = await connect(mf, code, phone, IOS_14);
    const b: Client = await connect(mf, code, tablet, WEB);
    for (const [c, seat, name] of [[a, 0, "Ada"], [b, 1, "Bo"]] as const) {
      const p = newPerson(name, seat + 1);
      c.send({ t: "claim", seat, person: { id: p.id, name: p.name, cat: p.cat } });
    }
    await a.until((s) => s.room.seats[1]?.kind === "human");
    a.send({ t: "start" });
    const counting = await a.until((s) => tumbleOf(s)?.status === "countdown");
    expect(tumbleOf(counting)).toMatchObject({ r: 1, wins: [0, 0] });
    const playing = await a.until((s) => tumbleOf(s)?.status === "playing", 6000);

    // Asking with nothing gets every box; a set-down reaches the other phone.
    a.send({ t: "tumble", r: 1, ev: [] });
    const sync = await a.find<TumbleSync>((m) => m.t === "tumbleSync");
    expect(sync.boxes.map((x) => x.s)).toEqual([0, 1]);
    a.send({ t: "tumble", r: 1, ev: [firstDrop(tumbleOf(playing), 0)] });
    const relay = await b.find<TumbleRelay>((m) => m.t === "tumble");
    expect(relay).toMatchObject({ r: 1, s: 0, q: 1 });
    expect(a.received.some((m) => m.t === "tumble")).toBe(false);

    // The round's clock runs: a quiet tablet is shown reconnecting.
    await a.find((m) => m.t === "tumbleSeat" && m.s === 1 && m.st === "lag");
  });
});
