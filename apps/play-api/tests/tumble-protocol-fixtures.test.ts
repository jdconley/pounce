import { readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { parseClientMessage } from "../src/protocol";
import { contents, newBox, receiveJunk, setDown, type Box } from "../src/tumble/box";
import { fromText } from "../src/tumble/codec";
import { toyAt } from "../src/tumble/queue";

import type { Seed } from "../src/rules/rng";
import type { TumbleClient, TumbleServer } from "../src/tumble/wire";

/**
 * Toy Tumble's wire samples (`docs/live-protocol.md`), for the Swift client and the web player:
 * they decode every server sample and encode every client sample, by `name`. The boxes are real
 * engine boxes. Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run tests/tumble-protocol-fixtures.test.ts`.
 */
type Sample<M> = { name: string; message: M };

const write = process.env.UPDATE_FIXTURES === "1";

function check(file: string, data: unknown): void {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}

const ROUND: Seed = [11, 22, 33, 44];

/** A box a few toys into a round, with a trick on it and junk waiting. */
function midRound(): Box {
  let box: Box = { ...newBox([5, 6, 7, 8]), ...fromText(["...1........", "33.1.22.....", "33.1222.5555"], ["", "....a.......", ""]) };
  const n = box.next;
  const toy = toyAt(ROUND, n);
  for (let x = 0; x < 12; x++) {
    for (let y = 0; y < 18; y++) {
      const r = setDown(box, ROUND, n, 0, x, y, []);
      if (!("error" in r)) {
        box = r.box;
        return receiveJunk(box, { id: 3, rows: 2, gap: 9 });
      }
    }
  }
  throw new Error(`no place for ${toy}`);
}

test("client samples parse to exactly themselves", () => {
  const client: Sample<TumbleClient>[] = [
    { name: "tumble-move", message: { t: "tumble", r: 2, ev: [["m", 14, 1, 5, 9]] } },
    { name: "tumble-set-down", message: { t: "tumble", r: 2, ev: [["m", 14, 1, 5, 3], ["l", 14, 1, 5, 3, 41250, []]] } },
    { name: "tumble-set-down-landing", message: { t: "tumble", r: 2, ev: [["l", 15, 0, 0, 0, 43010, [7, 8]]] } },
    { name: "tumble-ack", message: { t: "tumble", r: 2, ev: [["a", 31]] } },
    { name: "tumble-use", message: { t: "tumble", r: 2, ev: [["u", 0, 3]] } },
    { name: "tumble-sync-request", message: { t: "tumble", r: 2, ev: [] } },
  ];
  for (const { message } of client) expect(parseClientMessage(JSON.stringify(message))).toEqual(message);
  check("tumble-client-messages.json", client);
});

test("server samples", () => {
  const box = midRound();
  const other = { ...newBox([1, 1, 1, 1]), ...fromText(["5555........"]) };
  const shifts = Array.from({ length: 22 }, (_, y) => [0, 1, -2, 2, -1][y % 5] as number);
  const server: Sample<TumbleServer>[] = [
    { name: "tumble-relay", message: { t: "tumble", r: 2, s: 1, q: 88, ev: [["m", 14, 1, 5, 9], ["l", 14, 1, 5, 3, 41250, []]] } },
    { name: "hit-junk", message: { t: "tumbleHit", r: 2, id: 31, from: 0, to: 1, k: "junk", x: { rows: 2, gap: 7 } } },
    { name: "hit-hairball", message: { t: "tumbleHit", r: 2, id: 32, from: 0, to: 2, k: "hairball", x: { gap: 4 } } },
    { name: "hit-swipe", message: { t: "tumbleHit", r: 2, id: 33, from: 2, to: 0, k: "swipe", x: { shifts } } },
    { name: "hit-catnip", message: { t: "tumbleHit", r: 2, id: 34, from: 1, to: 0, k: "catnip" } },
    { name: "hit-scoop", message: { t: "tumbleHit", r: 2, id: 35, from: 1, to: 1, k: "scoop" } },
    { name: "hit-settle", message: { t: "tumbleHit", r: 2, id: 36, from: 1, to: 1, k: "settle" } },
    { name: "hit-nap", message: { t: "tumbleHit", r: 2, id: 37, from: 0, to: 0, k: "nap" } },
    { name: "hit-bath", message: { t: "tumbleHit", r: 2, id: 38, from: 2, to: 2, k: "bath" } },
    { name: "hit-swap", message: { t: "tumbleHit", r: 2, id: 39, from: 0, to: 1, k: "swap", x: contents(other) } },
    { name: "hit-napped", message: { t: "tumbleHit", r: 2, id: 40, from: 1, to: 0, k: "napped" } },
    {
      name: "tumble-sync",
      message: {
        t: "tumbleSync",
        r: 2,
        boxes: [
          { s: 0, box, q: 41, waitingLeft: [1250], catnipLeft: 0, napLeft: 6400, status: "ok" },
          { s: 1, box: other, q: 12, waitingLeft: [], catnipLeft: 3000, napLeft: 0, status: "lag" },
        ],
      },
    },
    { name: "tumble-seat-lag", message: { t: "tumbleSeat", r: 2, s: 1, st: "lag" } },
    { name: "tumble-seat-ok", message: { t: "tumbleSeat", r: 2, s: 1, st: "ok" } },
  ];
  check("tumble-server-messages.json", server);
});
