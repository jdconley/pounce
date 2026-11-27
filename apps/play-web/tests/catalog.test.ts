import { readFileSync } from "node:fs";

import { GAMES, gameTitle } from "@pounce/play-api/games/index";
import { describe, expect, test } from "vitest";

import { CATALOG, GAME_IDS, RULE_NAMES, SHELF, rulesLine, titleOf } from "../src/lib/catalog";
import { PURRTRAIT_ON, TUMBLE_ON } from "../src/lib/env";
import { RULE_COPY } from "../src/table/bw-model";

/** Games the server deals that this player doesn't draw yet: each leaves the list when its web table lands. */
const NOT_YET: readonly string[] = [];

describe("Home's game shelf", () => {
  test("names and seats every game the server has, exactly as the server does", () => {
    expect(GAME_IDS).toEqual(Object.keys(GAMES).filter((id) => !NOT_YET.includes(id)));
    for (const id of GAME_IDS) {
      expect(CATALOG[id].title).toBe(gameTitle(id));
      expect(CATALOG[id].minSeats).toBe(GAMES[id].minSeats);
      expect(CATALOG[id].maxSeats).toBe(GAMES[id].maxSeats);
    }
    expect(titleOf("chess")).toBe(gameTitle("chess"));
  });

  test("has Toy Tumble and Purrtrait on the shelf when the build turns them on", () => {
    const shelf = ["cat-tower", "tiles", "birdwatch", ...(PURRTRAIT_ON ? ["purrtrait"] : []), ...(TUMBLE_ON ? ["tumble"] : [])];
    expect(SHELF).toEqual(shelf);
    expect(GAME_IDS).toContain("tumble");
    expect(GAME_IDS).toContain("purrtrait");
  });

  test("the deployed build turns Toy Tumble and Purrtrait on", () => {
    const ci = readFileSync(new URL("../../../.github/workflows/ci.yml", import.meta.url), "utf8");
    const deploy = ci.slice(ci.indexOf("\n  deploy-play-api:"));
    const build = deploy.slice(deploy.indexOf("- name: Build the web player"), deploy.indexOf("- name: Deploy"));
    expect(build).toContain("pnpm --filter @pounce/play-web build");
    expect(build).toMatch(/\n\s+WEB_TUMBLE: "on"\n/);
    expect(build).toMatch(/\n\s+WEB_PURRTRAIT: "on"\n/);
  });
});

describe("a table card's rule set", () => {
  test("names every Birdwatch rule set as the table does", () => {
    expect(RULE_NAMES).toEqual(Object.fromEntries(Object.entries(RULE_COPY).map(([id, c]) => [id, c.name])));
  });

  test("says a Birdwatch table's rules, and nothing for any other game or a rule set it doesn't know", () => {
    expect(rulesLine({ game: "birdwatch", options: { rules: "tucker" } })).toBe("Tucker rules");
    expect(rulesLine({ game: "birdwatch", options: { rules: "official" } })).toBe("Official rules");
    expect(rulesLine({ game: "birdwatch", options: { rules: "grandma" } })).toBeNull();
    expect(rulesLine({ game: "birdwatch" })).toBeNull();
    expect(rulesLine({ game: "tiles" })).toBeNull();
    expect(rulesLine({ options: { rules: "tucker" } })).toBeNull();
  });

  test("reads the server's own sample of a 1.3 app's tables list", () => {
    const { tables } = JSON.parse(readFileSync(new URL("../../play-api/fixtures/http/birdwatch-tables.json", import.meta.url), "utf8")) as {
      tables: { game?: string; options?: { rules?: string } }[];
    };
    expect(tables.map(rulesLine)).toEqual(["Tucker rules", "Official rules", null]);
  });
});
