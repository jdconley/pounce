import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { expect, test } from "vitest";

import { puzzleVectors, rulesVectors } from "./vectors";

const dir = fileURLToPath(new URL("../../../fixtures/daily/nine-lives/", import.meta.url));

function check(name: string, value: unknown): void {
  const path = `${dir}${name}`;
  const json = `${JSON.stringify(value, null, 1)}\n`;
  if (process.env.UPDATE_VECTORS === "1") {
    mkdirSync(dir, { recursive: true });
    writeFileSync(path, json);
  }
  expect(JSON.parse(readFileSync(path, "utf8"))).toEqual(JSON.parse(json));
}

test("the rules vectors match the rules", () => {
  check("rules.json", rulesVectors());
});

test("the puzzle vectors match the maker", () => {
  check("puzzles.json", puzzleVectors());
}, 60_000);
