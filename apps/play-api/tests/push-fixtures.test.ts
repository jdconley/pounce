import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { plusPush } from "../src/consent/pages";
import { GOING_QUIET, freshStartBody } from "../src/notify/copy";
import { apnsBody } from "../src/notify/payload";
import { answeredPush, nudgePush, playAgainPush, pouncePush, statusPush, yourMovePush } from "../src/notify/pushes";

import type { Outgoing } from "../src/notify/types";

/**
 * Sample APNs bodies for every push the server sends (§12.5, §12.7), for the
 * app's notification tests (PR 5's app half). Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/push-fixtures.test.ts`.
 */
const write = process.env.UPDATE_FIXTURES === "1";

const mia = { name: "Mia", cat: 2 };
const jd = { name: "JD", cat: 1 };
const streak = { pair: "pr_3f9cAAAAAAAAAAAAAAAAAA", count: 12, me: false, them: true, naps: 1, myMove: ["GH2VD"], theirMove: [] };
const pair = streak.pair;
const pounceId = "pc_7QkAAAAAAAAAAAAAAAAAAA";

const reminder = (kind: "reminder" | "last_chance", body: string): Outgoing => ({
  kind,
  title: "JD",
  body,
  code: "GH2VD",
  thread: `pair:${pair}`,
  collapse: `${kind}:${pair}`,
  streak,
});

function samples(): { name: string; level: "active" | "passive"; push: Outgoing }[] {
  return [
    { name: "your_move", level: "active", push: yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: mia, completesToday: false, streak }) },
    { name: "your_move-quiet", level: "passive", push: yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: mia, completesToday: true, streak }) },
    { name: "reminder", level: "active", push: reminder("reminder", "The cats are on the rug. Your move at Couch Cats.") },
    { name: "last_chance", level: "active", push: reminder("last_chance", "One turn tonight keeps 12 days going.") },
    {
      name: "fresh_start",
      level: "active",
      push: { kind: "fresh_start", title: "JD", body: freshStartBody("Mia", false), thread: `pair:${pair}`, collapse: `fresh_start:${pair}`, streak: { ...streak, count: 0 } },
    },
    { name: "going_quiet", level: "active", push: { kind: "going_quiet", title: "JD", body: GOING_QUIET, thread: `pair:${pair}`, collapse: `going_quiet:${pair}` } },
    { name: "pounce-table", level: "active", push: pouncePush({ id: pounceId, pair, to: "JD", from: mia, target: { table: "GH2VD", name: "Couch Cats" }, streak }) },
    { name: "pounce-new", level: "active", push: pouncePush({ id: pounceId, pair, to: "JD", from: mia, target: "new", streak }) },
    { name: "pounce-pick-quiet", level: "passive", push: pouncePush({ id: pounceId, pair, to: "JD", from: mia, target: "pick", streak }) },
    { name: "pounce_answered-play", level: "passive", push: answeredPush({ id: pounceId, pair, to: "Mia", who: jd, answer: "play", code: "NWCDF" }) },
    { name: "pounce_answered-later", level: "passive", push: answeredPush({ id: pounceId, pair, to: "Mia", who: jd, answer: "later", code: null }) },
    { name: "pounce_answered-no", level: "passive", push: answeredPush({ id: pounceId, pair, to: "Mia", who: jd, answer: "no", code: null }) },
    { name: "nap", level: "passive", push: statusPush({ kind: "nap", pair, title: "Couch Cats", count: 12, streak }) },
    { name: "winback", level: "passive", push: statusPush({ kind: "winback", pair, title: "Couch Cats", count: 12, streak }) },
    { name: "paused", level: "passive", push: statusPush({ kind: "paused", pair, title: "Couch Cats", count: 3, who: mia, streak }) },
    { name: "milestone", level: "active", push: statusPush({ kind: "milestone", pair, title: "Couch Cats", count: 30, streak: { ...streak, count: 30 } }) },
    { name: "play_again", level: "active", push: playAgainPush({ code: "NWCDF", table: "Couch Cats", who: mia }) },
    { name: "nudge", level: "active", push: nudgePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: mia }) },
    { name: "consent", level: "active", push: plusPush("k_demoMochiAAAAAAAAAAAAAA", "Mochi") },
  ];
}

test("push payload fixtures match the server", () => {
  const data = samples().map(({ name, level, push }) => ({ name, collapseId: push.collapse, priority: level === "active" ? 10 : 5, body: apnsBody(push, level, 2) }));
  const path = new URL("../fixtures/push/payloads.json", import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
});
