/**
 * The contract between the web player and the server: the web player's own client code
 * (src/net, src/store) against the real Worker and its rooms, in workerd (Miniflare) on a real
 * port, over a real WebSocket. A change to the protocol, the browser socket or the rules that
 * the web player doesn't follow fails here.
 */
import { build } from "esbuild";
import { Miniflare } from "miniflare";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

import { Api } from "../src/net/api";
import { RoomSocket, type SocketLike } from "../src/net/socket";
import { profileBody, makePerson } from "../src/store/identity";
import { practiceMessages } from "../src/store/lobby";
import { RoomStore, type Paced } from "../src/store/room";

import type { RoomView } from "@pounce/play-api/protocol";

let mf: Miniflare;
let base = "";

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("../../play-api/src/index.ts", import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  mf = new Miniflare({
    modules: true,
    script: built.outputFiles[0]?.text ?? "",
    compatibilityDate: "2026-08-01",
    host: "127.0.0.1",
    port: 0,
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
      LIMITS: { className: "Limiter", useSQLite: true },
      REPORTS: { className: "Reports", useSQLite: true },
    },
    // As production runs: the tile game on, link heartbeats and move ids on. DEV_SPEED makes the House Cat quick.
    bindings: { TOKEN_SECRET: "c".repeat(64), GAMES: "tiles", LINK: "on", DEV_SPEED: "50" },
  });
  base = (await mf.ready).origin;
});

afterAll(async () => {
  await mf?.dispose();
});

const factory = (url: string, protocols: string[]) => new WebSocket(url, protocols) as unknown as SocketLike;

async function until<T>(read: () => T | undefined | null | false, ms = 15_000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const value = read();
    if (value) return value as T;
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 25));
  }
}

async function seatedPractice(game: "cat-tower" | "tiles") {
  const api = new Api(base);
  const mia = makePerson("Mia", 1);
  const answer = await api.uploadProfile(profileBody({ owner: mia, others: [], band: "adult" }));
  expect(Object.keys(answer.players)).toEqual([mia.id]);
  const code = await api.createRoom(game);
  const socket = new RoomSocket({ code, origin: base, token: async () => (await api.credential()).token, factory });
  const store = new RoomStore({ code, token: async () => "", socket, setTimer: (fn) => setTimeout(fn, 0), clearTimer: (id) => clearTimeout(id as ReturnType<typeof setTimeout>) });
  const events: Paced[] = [];
  store.subscribe({ event: (e) => events.push(e) });
  store.start();
  const lobby = await until(() => store.state.truth);
  expect(lobby.status).toBe("lobby");
  expect(lobby.link?.ping).toBeGreaterThan(0);
  store.send({ t: "claim", seat: 0, person: { id: mia.id, name: mia.name, cat: mia.cat } });
  const seated = await until(() => (store.state.truth?.seats[0]?.yours ? store.state.truth : null));
  for (const m of practiceMessages(seated) ?? []) store.send(m);
  const playing = await until(() => (store.state.truth?.status === "playing" ? store.state.truth : null));
  return { api, code, store, events, playing };
}

describe("the web player against the real server", () => {
  test("Cat Tower: mint, profile, a table, the browser socket, practice, and a move that lands once", async () => {
    const { store, events, playing } = await seatedPractice("cat-tower");
    const view = (r: RoomView | null) => r?.game;
    expect(view(playing)?.hands[0]?.length).toBeGreaterThanOrEqual(10);
    // Wait for our turn (a Cucumber flipped first may skip us), then draw.
    await until(() => view(store.state.truth)?.turn === 0 && view(store.state.truth)?.step === "draw" && !store.state.pending, 30_000);
    const before = view(store.state.truth)!.hands[0]!.length;
    expect(store.act(0, { type: "draw", from: "deck" })).toBe(true);
    const drawn = await until(() =>
      events.find((e) => e.event.kind === "game" && e.event.event.kind === "drew" && e.event.event.seat === 0 && e.event.event.card !== undefined),
    );
    expect(drawn).toBeTruthy();
    const after = await until(() => (view(store.state.truth)?.hands[0]?.length === before + 1 ? store.state.truth : null));
    expect(after.link?.acks.length).toBeGreaterThan(0);
    expect(store.state.pending).toBeNull();
    store.stop();
  });

  test("Tuna Tiles: a tile table deals, and a draw is a whole turn", async () => {
    const { store, playing } = await seatedPractice("tiles");
    expect(playing.gameId).toBe("tiles");
    expect(playing.tiles?.racks[0]?.length).toBe(14);
    await until(() => store.state.truth?.tiles?.turn === 0 && !store.state.pending, 30_000);
    const turns = store.state.truth!.tiles!.turns;
    store.act(0, { type: "draw" });
    await until(() => (store.state.truth?.tiles?.turns ?? 0) > turns);
    expect(store.state.truth?.tiles?.racks[0]?.length).toBe(15);
    store.stop();
  });

  test("a code with no table ends as not found, read from the close code", async () => {
    const api = new Api(base);
    const socket = new RoomSocket({ code: "BCDFG", origin: base, token: async () => (await api.credential()).token, factory });
    const kinds: string[] = [];
    socket.on((e) => kinds.push(e.kind));
    socket.start();
    await until(() => kinds.includes("notFound"));
  });

  test("the server never holds the web player to an app minimum", async () => {
    const res = await fetch(`${base}/v1/app`);
    expect(res.status).toBe(200);
    const api = new Api(base);
    await expect(api.listTables()).resolves.toEqual([]);
  });
});
