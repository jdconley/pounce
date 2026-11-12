import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import { expect, test } from "vitest";

/**
 * Version 1.0 of the app decodes exactly these samples (PounceKit's tests read the same files),
 * and it decodes strictly. They are pinned by hash as they stood when the second game was wired
 * in, so nothing done for another game can change one byte of what a Cat Tower table sends: the
 * suites that generate them (`protocol-fixtures`, `push-fixtures`, `live-fixtures`, `http-fixtures`) check the
 * server still produces these bytes, and this checks nobody regenerated the files to match a
 * changed server.
 *
 * A change here is a change to what 1.0 receives. Add new samples to a new file instead (the
 * tile game's are `tiles-server-messages.json` and `tiles-client-messages.json`).
 */
const PINNED: Record<string, string> = {
  "protocol/client-messages.json": "13f43983d1aa66633ef8e82c000609b5604f5952ac52093d4b9d259d73c793bf",
  "protocol/server-messages.json": "b33837062fee1cc2f143bac5629f8fbfff60219f87bbf9465dddd5b27ee5d320",
  "protocol/streaks-client-messages.json": "a313a999554d4dd3eeb3de5a74fb28f39a349886d99d3d185872ecae84d8633d",
  "protocol/streaks-server-messages.json": "a084330216a80cc53bc032c1af746d3f54d6c6a7e76b3fc3c1b5a93e9c58d869",
  "push/live-activity.json": "5d57a563563b51de7d2b3b7cb1d4f32e419baa2b35400393f431eb4ab3c0e57e",
  "push/payloads.json": "48d7b87c1b338763b1ec6148f2ebc51c1b38c76e300e2508ac6637269a531676",
  "groups.json": "d9240a4a63b2518fd58a197684ae68b8c6e1abb86859045ac0464f11454a9a1b",
  // The HTTP bodies 1.0 decodes, sampled for the first time alongside the second game's wiring
  // (`tests/http-fixtures.test.ts` builds them and checks the real Worker's answers against them).
  "http/pounces.json": "052d726c2b8095d898553e8bea3dd95e274c8edbf6eede05f911f34716ce4c80",
  "http/state.json": "0a11ab2ee9155562d7d651046931d80db66e0ba70148373254e1d93f32c4de37",
  "http/streaks.json": "b5ae27a9ebba0af58b07dfd432a4b93c8888a3f4fabc00779e799e6edac47dd5",
  "http/tables.json": "9d954ddc509c5552c57bed4f551bb97b10c978d78267ec813d8da8671fdaeab1",
  "http/trophies.json": "f2a7e91b8d7f0296a55ef8eba68eb41a02d8b75a3fb951cc3a887a06b783253b",
};

test.each(Object.entries(PINNED))("fixtures/%s is byte for byte what version 1.0 decodes", (file, sha256) => {
  const bytes = readFileSync(new URL(`../fixtures/${file}`, import.meta.url));
  expect(createHash("sha256").update(bytes).digest("hex")).toBe(sha256);
});

test("no Cat Tower sample mentions another game", () => {
  for (const file of Object.keys(PINNED)) {
    const text = readFileSync(new URL(`../fixtures/${file}`, import.meta.url), "utf8");
    // In an HTTP body a `game` key is a table's game (the socket's `game` is Cat Tower's own view), and
    // the trophy room's catalog has a `progress` of its own (elsewhere the word is the tile game's live table).
    const words = ["gameId", '"tiles"', "progressKind", file.startsWith("http/") ? '"game"' : '"progress"'];
    for (const word of words) expect(text.includes(word), `${file}: ${word}`).toBe(false);
  }
});
