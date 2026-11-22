#!/usr/bin/env node
/**
 * Daily Dish cross-platform check: the API client. Through the logging proxy, as plain HTTP.
 *
 *   node api.mjs play <plan.json> <game>   one new person plays the plan's move list, paced like a person
 *   node api.mjs cheat <plan.json> <game>  the anti-cheat probes for that game
 *   node api.mjs tv <plan.json> <log> <clients>  links the board to each TV in <clients> (comma
 *       separated, as the proxy names them, e.g. appletv,web) by the code each last asked the
 *       server for, then plays every game's plan with Show on TV on, so each TV can watch it
 *
 * Prints JSON lines: what was sent and what came back.
 */
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

const BASE = process.env.CROSSCHECK_BASE ?? "http://127.0.0.1:8819";
const [mode, planFile, game] = process.argv.slice(2);
const plans = JSON.parse(readFileSync(planFile, "utf8")).plans;
const plan = mode === "tv" ? plans[0] : plans.find((p) => p.game === game);
if (!plan) throw new Error(`no plan for ${game}`);

const say = (o) => console.log(JSON.stringify(o));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(",")}]`;
  if (v && typeof v === "object") return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(",")}}`;
  return JSON.stringify(v);
}
const hash = (v) => createHash("sha256").update(canon(v)).digest("hex").slice(0, 16);

async function http(token, method, path, body, client = "api") {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "content-type": "application/json",
      "x-pounce-games": "tiles,dish",
      "x-crosscheck-client": client,
      "cf-connecting-ip": `10.9.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`,
    },
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text.slice(0, 200); }
  return { status: res.status, json };
}

/** A new device with `names.length` people on it, all in America/New_York (the Mac's zone). */
async function device(names) {
  const minted = await http(null, "POST", "/v1/devices");
  const token = minted.json.token;
  const people = names.map((name, i) => ({ id: randomUUID(), name, cat: i + 1, key: randomBytes(32).toString("base64url") }));
  const prof = await http(token, "PUT", "/v1/devices/me/profile", { timeZone: "America/New_York", ageBand: "adult", people });
  if (prof.status !== 200) throw new Error(`profile ${prof.status} ${JSON.stringify(prof.json)}`);
  return { token, people };
}

const start = (d, person, g = game) => http(d.token, "POST", `/v1/daily/${g}/start?person=${person.id}`);
const moves = (d, person, run, body) => http(d.token, "POST", `/v1/daily/runs/${run}/moves?person=${person.id}`, body);

if (mode === "play") {
  const d = await device(["Crosscheck Api"]);
  const me = d.people[0];
  const s = await start(d, me);
  say({ step: "start", status: s.status, date: s.json.date, number: s.json.number, level: s.json.level, puzzleHash: hash(s.json.puzzle), planHash: plan.puzzleHash });
  // Paced like a person: the whole list over the game's floor plus a margin, one batch a second.
  const gap = plan.paceMs;
  const t0 = Date.now();
  let seq = 0;
  let result = null;
  const sent = [];
  while (seq < plan.moves.length && !result) {
    const due = Math.min(plan.moves.length, Math.floor((Date.now() - t0) / gap) + 1);
    if (due <= seq) { await sleep(200); continue; }
    const batch = plan.moves.slice(seq, game === "sniff" ? seq + 1 : due);
    // Every batch also carries a forged result: the server reads none of it.
    const a = await moves(d, me, s.json.run, { from: seq, moves: batch, result: { outcome: "solved", timeMs: 1, points: 99999, guesses: 1 }, timeMs: 1, points: 99999 });
    if (!a.json.ok) { say({ step: "refused", a: a.json }); process.exit(1); }
    sent.push(...batch);
    seq = a.json.seq;
    result = a.json.result;
    if (!result) await sleep(game === "sniff" ? gap : 1000);
  }
  say({ step: "end", movesHash: hash(sent), planMovesHash: plan.movesHash, result });
  const board = await http(d.token, "GET", `/v1/daily/board?person=${me.id}`);
  say({ step: "board", rows: board.json.games?.find((g) => g.game === game)?.rows });
}

if (mode === "cheat") {
  const fam = await device(["Mom", "Kid"]); // one iPad, two people
  const [mom, kid] = fam.people;
  const other = await device(["Stranger"]);
  const [stranger] = other.people;
  const s = await start(fam, mom);
  const run = s.json.run;
  const first = plan.moves[0];

  // 1. A forged result, score, time and outcome in the body: ignored, the run goes on unsolved.
  const forged = await moves(fam, mom, run, {
    from: 0, moves: [first],
    result: { outcome: "solved", timeMs: 1, points: 99999, guesses: 1, tooFast: false },
    outcome: "solved", score: 99999, points: 99999, timeMs: 1, seq: 999, progress: 1,
  });
  say({ probe: "forged-fields", status: forged.status, answer: forged.json, pass: forged.json.ok === true && forged.json.seq === 1 && forged.json.result === null });

  // 1b. No route takes a score: every guess at one is a 404.
  const guesses = [
    ["POST", `/v1/daily/runs/${run}/result`], ["POST", `/v1/daily/runs/${run}/score`], ["PUT", `/v1/daily/runs/${run}`],
    ["POST", `/v1/daily/runs/${run}`], ["PATCH", `/v1/daily/runs/${run}`], ["POST", `/v1/daily/${game}/result`],
    ["POST", `/v1/daily/${game}/score`], ["POST", "/v1/daily/board"], ["PUT", "/v1/daily/board"], ["POST", "/v1/daily/stats"],
    ["PUT", `/v1/daily/runs/${run}/moves`],
  ];
  const routes = [];
  for (const [m, p] of guesses) {
    const r = await http(fam.token, m, `${p}?person=${mom.id}`, { outcome: "solved", timeMs: 1, points: 99999 });
    routes.push(`${m} ${p.replace(run, "{run}")} ${r.status}`);
  }
  say({ probe: "no-score-route", routes, pass: routes.every((r) => r.endsWith(" 404")) });

  // 2. A resend of the same batch from the same `from` is the same answer and changes nothing; a
  //    different batch from an old `from` is refused.
  const again = await moves(fam, mom, run, { from: 0, moves: [first] });
  say({ probe: "resend-same", answer: again.json, pass: again.json.ok === true && again.json.seq === 1 });
  const replay = await moves(fam, mom, run, { from: 0, moves: [plan.moves[1] ?? first] });
  say({ probe: "replayed-from", answer: replay.json, pass: replay.json.ok === false && replay.json.error === "stale" && replay.json.seq === 1 });

  // 3. Over the spacing budget: from the start, at most 10 moves at once (Sniff: guesses 500 ms apart).
  const burst = game === "sniff" ? plan.moves.slice(1, 3) : plan.moves.slice(1, 13);
  const soon = await moves(fam, mom, run, { from: 1, moves: burst });
  say({ probe: "too-soon", sent: burst.length, answer: soon.json, pass: soon.json.ok === false && soon.json.error === "too_soon" && soon.json.seq === 1 });

  // 4. Someone else's run, from another device: moves, hint, give up and Show on TV all say 404.
  const foreign = [];
  for (const [m, a, b] of [["POST", "moves", { from: 1, moves: [plan.moves[1]] }], ["POST", "hint", { hints: 0 }], ["POST", "giveup", undefined], ["PUT", "tv", { on: true }]]) {
    const r = await http(other.token, m, `/v1/daily/runs/${run}/${a}?person=${stranger.id}`, b);
    foreign.push(`${a} ${r.status} ${JSON.stringify(r.json)}`);
  }
  say({ probe: "foreign-run", foreign, pass: foreign.every((f) => f.split(" ")[1] === "404") });
  //    ...and that device can't speak for Mom.
  const asMom = await http(other.token, "POST", `/v1/daily/runs/${run}/moves?person=${mom.id}`, { from: 1, moves: [plan.moves[1]] });
  say({ probe: "not-their-person", status: asMom.status, answer: asMom.json, pass: asMom.status === 403 });

  // 5. Mom's run can't be finished by Kid on the same iPad: every remaining move as Kid is a 404.
  const rest = plan.moves.slice(1);
  await sleep(game === "sniff" ? 600 : 2500);
  const asKid = await moves(fam, kid, run, { from: 1, moves: game === "sniff" ? rest.slice(0, 1) : rest.slice(0, 10) });
  const kidGiveUp = await http(fam.token, "POST", `/v1/daily/runs/${run}/giveup?person=${kid.id}`);
  say({ probe: "other-person-finish", moves: [asKid.status, asKid.json], giveup: [kidGiveUp.status, kidGiveUp.json], pass: asKid.status === 404 && kidGiveUp.status === 404 });
  //    Kid's own start is Kid's own run, not Mom's.
  const kidStart = await start(fam, kid);
  say({ probe: "kid-own-run", sameRun: kidStart.json.run === run, kidSeq: kidStart.json.seq, pass: kidStart.json.run !== run && kidStart.json.seq === 0 });

  // 6. Mom's run is where it was: seq 1, no result; the board shows her playing, nobody solved.
  const mine = await start(fam, mom);
  const board = await http(fam.token, "GET", `/v1/daily/board?person=${mom.id}`);
  const rows = board.json.games?.find((g) => g.game === game)?.rows ?? [];
  say({ probe: "unchanged", seq: mine.json.seq, result: mine.json.result, rows, pass: mine.json.run === run && mine.json.seq === 1 && mine.json.result === null && rows.every((r) => r.result === null) });
}

if (mode === "tv") {
  const [logFile, clients] = process.argv.slice(4);
  const wanted = clients.split(",");
  const d = await device(["Mom"]);
  const me = d.people[0];
  // Each TV's newest link code (its `POST /v1/screens`), as the proxy logged it.
  const codes = () => {
    const found = {};
    for (const line of readFileSync(logFile, "utf8").split("\n")) {
      if (!line) continue;
      const e = JSON.parse(line);
      if (e.method === "POST" && e.url.split("?")[0] === "/v1/screens" && e.res?.code && wanted.includes(e.client)) found[e.client] = e.res.code;
    }
    return found;
  };
  // A TV can ask for a code at launch and again when its link panel opens, so link only once
  // every TV has one and none has asked for a new one for 20 s.
  let seen = "";
  for (let quiet = 0; quiet < 20; quiet++) {
    const now = JSON.stringify(codes());
    if (now !== seen || Object.keys(codes()).length < wanted.length) quiet = -1;
    seen = now;
    await sleep(1000);
  }
  for (const [client, code] of Object.entries(codes())) {
    const linked = await http(d.token, "POST", `/v1/screens/link?person=${me.id}`, { code, board: true });
    say({ step: "link", client, status: linked.status });
  }
  // The order the Dish lists them in.
  for (const g of ["sniff", "nine-lives", "cat-nap", "box-fort"]) {
    const p = plans.find((x) => x.game === g);
    await sleep(4000);
    const s = await start(d, me, g);
    const on = await http(d.token, "PUT", `/v1/daily/runs/${s.json.run}/tv?person=${me.id}`, { on: true });
    say({ step: "start", game: g, puzzleHash: hash(s.json.puzzle), planHash: p.puzzleHash, tv: on.status });
    await sleep(8000); // the TVs press Watch
    let seq = 0;
    let result = null;
    while (!result) {
      const a = await moves(d, me, s.json.run, { from: seq, moves: p.moves.slice(seq, seq + 1) });
      if (!a.json.ok) { say({ step: "refused", game: g, a: a.json }); process.exit(1); }
      seq = a.json.seq;
      result = a.json.result;
      if (!result) await sleep(g === "sniff" ? 2500 : 700);
    }
    say({ step: "end", game: g, result });
    await sleep(15000); // the TVs show the result, then the board
  }
}

