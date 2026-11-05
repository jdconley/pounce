import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { endBody, startAlert, startBody, updateBody, type LiveState } from "../src/live/live";
import { yourMoveBody } from "../src/notify/copy";

/**
 * Sample live table pushes (§11.3) for the app's tests: its `ActivityAttributes`
 * and `ContentState` must decode every body's `attributes` and `content-state`.
 * Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/live-fixtures.test.ts`.
 */
const write = process.env.UPDATE_FIXTURES === "1";
const NOW = Date.UTC(2026, 10, 5, 19, 30, 0);

const theirs: LiveState = {
  table: "Couch Cats",
  seats: [
    { cat: 1, phase: 3, name: "JD", bot: false, me: true },
    { cat: 2, phase: 4, name: "Mia", bot: false, me: false },
    { cat: 3, phase: 2, bot: true, me: false },
  ],
  turn: 1,
  mine: false,
  streak: { count: 12, me: false, them: true },
};
const mine: LiveState = { ...theirs, turn: 0, mine: true };
const over: LiveState = { ...theirs, turn: null, mine: false, streak: null };

function samples(): { name: string; priority: 5 | 10; body: Record<string, unknown> }[] {
  return [
    { name: "start-their-move", priority: 10, body: startBody("GH2VD", theirs, NOW, startAlert(theirs)) },
    { name: "start-my-move", priority: 10, body: startBody("GH2VD", mine, NOW, startAlert(mine)) },
    { name: "update-my-move", priority: 10, body: updateBody(mine, NOW, { title: "JD", body: yourMoveBody("Mia", "Couch Cats", false) }) },
    { name: "update-their-move", priority: 5, body: updateBody(theirs, NOW, null) },
    { name: "end", priority: 10, body: endBody(over, NOW) },
  ];
}

test("live table fixtures match the server", () => {
  const path = new URL("../fixtures/push/live-activity.json", import.meta.url);
  const text = JSON.stringify(samples(), null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
});
