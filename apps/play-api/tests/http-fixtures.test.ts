import { readFileSync, writeFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { createTables, listTables, upsertTable } from "../src/room/tables";
import { newPair, report, view } from "../src/streaks/pair-core";
import { ownView, recordTurn } from "../src/streaks/personal";
import { trophies } from "../src/streaks/trophies";

import { BASE, bundle, call, mint, newPerson, profile, table, takeTurn, tokenOf, worker, type Client, type Sent } from "./play-helpers";
import { storage } from "./sqlite-storage";

import type { MeState } from "../src/players/player";
import type { PounceView } from "../src/pounce/limits";
import type { ServerMessage } from "../src/protocol";
import type { Miniflare } from "miniflare";

/**
 * The HTTP bodies an app decodes, as samples for the Swift client (PounceKit), the way
 * `fixtures/protocol` holds the socket's. Version 1.0 reads every one of them, and none had a
 * sample before.
 *
 * Each sample is built from the server's own code with fixed inputs, so it is the same bytes
 * every run and can be pinned (`tests/fixtures-pinned.test.ts`): the tables list through its
 * real SQL, the streaks and the trophy room through the pure builders behind them, and the two
 * with no pure builder (synced state, pounce answers) as literals held to the server's types.
 *
 * A sample built beside the server could drift from what the server sends. So the last suite
 * here asks the real Worker for each body and checks that the sample covers it: every key the
 * server sent is in the sample, with the same kind of value. A key added to one of these
 * payloads fails that check until the sample, and its pin, are changed on purpose.
 *
 * Regenerate with `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/http-fixtures.test.ts`.
 */
const write = process.env.UPDATE_FIXTURES === "1";
const FILES = ["tables", "streaks", "trophies", "state", "pounces"] as const;
type Name = (typeof FILES)[number];

const path = (name: Name) => new URL(`../fixtures/http/${name}.json`, import.meta.url);

const PA = "p_AAAAAAAAAAAAAAAAAAAAAA";
const PB = "p_BBBBBBBBBBBBBBBBBBBBBB";
const ZONE = "America/Los_Angeles";
const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const day = (h: number) => Date.UTC(2026, 10, 4, h);

/** `GET /v1/devices/me/tables`, read back through the list's own SQL: a table in play, a finished one that was dealt again, and a row from before lists had names or seats. */
function tablesBody(): unknown {
  const sql = storage(new DatabaseSync(":memory:"));
  createTables(sql);
  const seats = [
    { kind: "human" as const, person: { id: ALICE, name: "Alice", cat: 0 }, yours: true as const },
    { kind: "human" as const, person: { id: BOB, name: "Bob", cat: 3 } },
    { kind: "bot" as const },
  ];
  upsertTable(sql, { code: "BCDFG", name: "Couch Cats", status: "playing", yourTurn: true, updatedAt: day(18), seats, movedAt: day(17) });
  upsertTable(sql, { code: "GH2VD", name: "Taco Night", status: "over", yourTurn: false, updatedAt: day(12), next: "NWCDF", seats: seats.slice(0, 2) });
  upsertTable(sql, { code: "KLMNP", status: "lobby", yourTurn: false, updatedAt: day(9) });
  return { tables: listTables(sql) };
}

const DAY_MS = 24 * 60 * 60 * 1000;
/** The last moment of the samples: the third evening. */
const NOW = day(18) + 2 * DAY_MS;

/** Alice and Bob's pair after a turn each on three days running: a streak of three, with the gift that brings. */
function pairOf() {
  const pair = newPair(
    "pair_3f9cAAAAAAAAAAAAAAAAAA",
    [
      { id: PA, name: "Alice", cat: 0, zone: ZONE, quietStart: 1320 },
      { id: PB, name: "Bob", cat: 3, zone: ZONE, quietStart: 1320 },
    ],
    day(16),
    [1, 2, 3, 4],
  );
  for (const later of [0, DAY_MS, 2 * DAY_MS]) {
    report(pair, { code: "BCDFG", at: day(17) + later, by: PA, holder: PB, over: false }, day(17) + later);
    report(pair, { code: "BCDFG", at: day(18) + later, by: PB, holder: PA, over: false }, day(18) + later);
  }
  return pair;
}

function own() {
  let mine = recordTurn(null, day(17), ZONE, day(17));
  for (const later of [DAY_MS, 2 * DAY_MS]) mine = recordTurn(mine, day(17) + later, ZONE, day(17) + later);
  return ownView(mine, ZONE, NOW);
}

/** The pairs as both routes list them (`myStreaks`): one you pounced (unanswered), one that pounced you at a table and holds the move, and one that asked for a new game. */
function connections() {
  const mine = view(pairOf(), PA, NOW);
  const sent = { sent: true, resting: true, quiet: false, answer: null, code: null, waiting: null } satisfies PounceView;
  const waiting = { sent: false, resting: false, quiet: true, answer: "play", code: "NWCDF", waiting: { id: "pc_AAAAAAAAAAAAAAAAAAAAAA", target: { table: "BCDFG" } } } satisfies PounceView;
  const asked = { sent: false, resting: false, quiet: false, answer: "later", code: null, waiting: { id: "pc_CCCCCCCCCCCCCCCCCCCCCC", target: "new" } } satisfies PounceView;
  return [
    { ...mine, pounce: sent, pinned: true },
    { ...mine, pair: "pair_7b2dBBBBBBBBBBBBBBBBBB", myMove: [], theirMove: ["GH2VD"], pounce: waiting, pinned: false },
    { ...mine, pair: "pair_5c8eDDDDDDDDDDDDDDDDDD", pounce: asked, pinned: false },
  ];
}

/** `GET /v1/me/streaks`: your own streak, those pairs, and a pair you left. */
function streaksBody(): unknown {
  return { own: own(), pairs: connections(), left: [{ pair: "pair_9e1fCCCCCCCCCCCCCCCCCC", partner: { name: "Mo", cat: 5 } }] };
}

/** `GET /v1/me/trophies`, from the builder the route uses. */
function trophiesBody(): unknown {
  return trophies({ me: PA, own: own(), pairBest: 3, pairs: [pairOf()], connections: connections() });
}

/** `GET /v1/me/state`: synced settings, the tutorial and archive registers, a household person and the profile. */
function stateBody(): unknown {
  return {
    settings: { sound: { v: false, at: day(17) }, haptics: { v: true, at: day(16) } },
    tutorial: { done: { v: true, at: day(16) } },
    archive: { GH2VD: { v: true, at: day(18) } },
    people: [{ personId: BOB, playerId: PB, name: "Bob", cat: 3 }],
    profile: { name: "Alice", cat: 0, at: day(16) },
  } satisfies MeState;
}

/** The pounce routes' answers: `POST /v1/pounces` by push and by link, `POST …/answer` with and without a table, and `GET /v1/pounces/links/{token}`. */
function pouncesBody(): unknown {
  return {
    created: { id: "pc_AAAAAAAAAAAAAAAAAAAAAA" },
    createdLink: { id: "pc_BBBBBBBBBBBBBBBBBBBBBB", link: "https://play.conleychaos.com/p/AAAAAAAAAAAAAAAAAAAAAA" },
    answeredPlay: { code: "NWCDF" },
    answeredLater: {},
    link: { id: "pc_BBBBBBBBBBBBBBBBBBBBBB", from: { name: "Alice", cat: 0 }, target: "new" },
  };
}

const BUILDERS: Record<Name, () => unknown> = { tables: tablesBody, streaks: streaksBody, trophies: trophiesBody, state: stateBody, pounces: pouncesBody };

const sample = (name: Name): unknown => JSON.parse(readFileSync(path(name), "utf8"));

describe("the HTTP samples", () => {
  test.each(FILES)("fixtures/http/%s.json is what the server's own code builds", (name) => {
    const text = JSON.stringify(BUILDERS[name](), null, 2) + "\n";
    if (write) writeFileSync(path(name), text);
    expect(readFileSync(path(name), "utf8")).toBe(text);
  });

  test("none of them names another game, a seed or anything else that is the server's alone", () => {
    for (const name of FILES) {
      const text = readFileSync(path(name), "utf8");
      for (const word of ['"game"', "tiles", '"seed"', '"rng"', "deviceToken"]) expect(text.includes(word), `${name}: ${word}`).toBe(false);
    }
  });
});

/** The kind of a JSON value, keys and all; null is "nothing known yet". */
type Shape =
  | { kind: "null" }
  | { kind: "string" | "number" | "boolean" }
  | { kind: "array"; of: Shape }
  | { kind: "object"; keys: Record<string, Shape> }
  /** A place that holds more than one kind of value (a pounce's target is a word or a table). */
  | { kind: "either"; of: Shape[] };

function merge(a: Shape, b: Shape): Shape {
  if (a.kind === "null") return b;
  if (b.kind === "null") return a;
  if (a.kind === "array" && b.kind === "array") return { kind: "array", of: merge(a.of, b.of) };
  if (a.kind === "object" && b.kind === "object") {
    const keys = { ...a.keys };
    for (const [k, v] of Object.entries(b.keys)) keys[k] = k in keys ? merge(keys[k] as Shape, v) : v;
    return { kind: "object", keys };
  }
  if (a.kind === b.kind) return a;
  const alternatives = [...(a.kind === "either" ? a.of : [a]), ...(b.kind === "either" ? b.of : [b])];
  return { kind: "either", of: alternatives.filter((x, i) => alternatives.findIndex((y) => y.kind === x.kind) === i) };
}

function shapeOf(value: unknown): Shape {
  if (value === null) return { kind: "null" };
  if (Array.isArray(value)) return { kind: "array", of: value.map(shapeOf).reduce(merge, { kind: "null" }) };
  if (typeof value === "object") return { kind: "object", keys: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, shapeOf(v)])) };
  return { kind: typeof value as "string" | "number" | "boolean" };
}

/** Everything in `live` that `sample` doesn't cover: a key it lacks, or a value of another kind. */
function uncovered(live: Shape, sampled: Shape, at: string): string[] {
  if (live.kind === "null") return [];
  if (sampled.kind === "null") return [`${at}: the sample has only null here`];
  if (sampled.kind === "either") {
    const same = sampled.of.find((one) => one.kind === live.kind);
    return same ? uncovered(live, same, at) : [`${at}: ${live.kind} is none of the kinds in the sample`];
  }
  if (live.kind !== sampled.kind) return [`${at}: ${live.kind} in the server's answer, ${sampled.kind} in the sample`];
  if (live.kind === "array" && sampled.kind === "array") return uncovered(live.of, sampled.of, `${at}[]`);
  if (live.kind === "object" && sampled.kind === "object") {
    return Object.entries(live.keys).flatMap(([k, v]) => (k in sampled.keys ? uncovered(v, sampled.keys[k] as Shape, `${at}.${k}`) : [`${at}.${k}: not in the sample`]));
  }
  return [];
}

describe("the shape check itself", () => {
  const covered = (live: unknown, sampled: unknown) => uncovered(shapeOf(live), shapeOf(sampled), "$");

  test("passes a body the sample covers, however much more the sample holds", () => {
    expect(covered({ a: 1, b: null, c: [{ x: "s" }] }, { a: 2, b: { deep: true }, c: [{ x: "t", y: 1 }, { x: "u" }], d: false })).toEqual([]);
    expect(covered({ list: [] }, { list: [1, 2] })).toEqual([]);
  });

  test("names a key the sample lacks, at any depth", () => {
    expect(covered({ a: 1, game: "tiles" }, { a: 1 })).toEqual(["$.game: not in the sample"]);
    expect(covered({ c: [{ x: "s", gameId: "tiles" }] }, { c: [{ x: "t" }] })).toEqual(["$.c[].gameId: not in the sample"]);
  });

  test("a place that holds either of two kinds takes both, and nothing else", () => {
    const sampled = { targets: [{ target: "new" }, { target: { table: "BCDFG" } }] };
    expect(covered({ targets: [{ target: "pick" }] }, sampled)).toEqual([]);
    expect(covered({ targets: [{ target: { table: "GH2VD" } }] }, sampled)).toEqual([]);
    expect(covered({ targets: [{ target: 7 }] }, sampled)).toEqual(["$.targets[].target: number is none of the kinds in the sample"]);
    expect(covered({ targets: [{ target: { table: "GH2VD", game: "tiles" } }] }, sampled)).toEqual(["$.targets[].target.game: not in the sample"]);
  });

  test("names a value of another kind, and a place the sample only ever has null", () => {
    expect(covered({ a: "1" }, { a: 1 })).toEqual(["$.a: string in the server's answer, number in the sample"]);
    expect(covered({ a: { b: 1 } }, { a: null })).toEqual(["$.a: the sample has only null here"]);
  });
});

describe("the real Worker's answers are covered by the samples", { timeout: 60_000 }, () => {
  let script = "";
  const sent: Sent[] = [];
  const open: Miniflare[] = [];

  beforeAll(async () => {
    script = await bundle("./pounce-entry.ts");
  });

  afterEach(async () => {
    await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  });

  test("tables, streaks, trophies, state and pounces: no key the samples lack, no value of another kind", async () => {
    // Production's flags, and no `GAMES`: what an app from before the second game is answered.
    const mf = await worker(script, { sent, links: true, trophy: true });
    open.push(mf);
    const phone = await mint(mf);
    const tablet = await mint(mf);
    const jd = newPerson("JD", 1);
    const mia = newPerson("Mia", 2);
    await profile(mf, phone, [jd], { apns: tokenOf(1) });
    await profile(mf, tablet, [mia], { apns: tokenOf(2) });
    const t = await table(mf, [
      [phone, jd],
      [tablet, mia],
    ]);
    await takeTurn(t.clients);
    await takeTurn(t.clients);
    const streak = await (t.clients[0] as Client).find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");

    const body = async (res: Promise<Response>, status = 200): Promise<unknown> => {
      const r = await res;
      expect(r.status).toBe(status);
      return r.json();
    };
    const check = (name: Name, live: unknown, part?: string) => {
      const whole = sample(name) as Record<string, unknown>;
      expect(uncovered(shapeOf(live), shapeOf(part ? whole[part] : whole), part ? `${name}.${part}` : name)).toEqual([]);
    };

    check("tables", await body(call(mf, phone, "GET", "/v1/devices/me/tables")));
    check("streaks", await body(call(mf, phone, "GET", `/v1/me/streaks?person=${jd.id}`)));
    check("trophies", await body(call(mf, phone, "GET", `/v1/me/trophies?person=${jd.id}`)));
    expect((await call(mf, phone, "PATCH", `/v1/me/state?person=${jd.id}`, { settings: { sound: { v: false, at: 5 } }, tutorial: { done: { v: true, at: 6 } } })).status).toBe(204);
    check("state", await body(call(mf, phone, "GET", `/v1/me/state?person=${jd.id}`)));

    // A pounce by push: its answer to the sender, how both lists show it, and the partner's Play.
    const created = (await body(call(mf, phone, "POST", `/v1/pounces?person=${jd.id}`, { to: streak.pair, target: "new" }), 201)) as { id: string };
    check("pounces", created, "created");
    check("streaks", await body(call(mf, phone, "GET", `/v1/me/streaks?person=${jd.id}`)));
    check("streaks", await body(call(mf, tablet, "GET", `/v1/me/streaks?person=${mia.id}`)));
    check("pounces", await body(call(mf, tablet, "POST", `/v1/pounces/${created.id}/answer?person=${mia.id}`, { answer: "play" })), "answeredPlay");
    check("streaks", await body(call(mf, phone, "GET", `/v1/me/streaks?person=${jd.id}`)));
    check("tables", await body(call(mf, tablet, "GET", "/v1/devices/me/tables")));

    // A pounce by link, and the link as whoever opens it reads it.
    const linked = (await body(call(mf, phone, "POST", `/v1/pounces?person=${jd.id}`, { target: "new" }), 201)) as { id: string; link: string };
    check("pounces", linked, "createdLink");
    const token = linked.link.split("/").at(-1) as string;
    check("pounces", await body(call(mf, tablet, "GET", `/v1/pounces/links/${token}`)), "link");
    expect((await mf.dispatchFetch(`${BASE}/healthz`)).status).toBe(200);
  });
});
