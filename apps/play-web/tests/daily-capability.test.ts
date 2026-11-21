import { gamesListed } from "@pounce/play-api/games/index";
import { describe, expect, test } from "vitest";


import { Api } from "../src/net/api";
import { wsUrl } from "../src/net/socket";

/**
 * The web player has the Daily Dish, and says so (docs/daily-protocol.md "Say that the app has the
 * Dish"): `dish` in `X-Pounce-Games` on every call and in `games=` on every browser socket, so the
 * server sends this device the Dish's reminder. No table is a game called `dish`.
 *
 * The server reads it as `dishListed` in `daily/games.ts` does (that module pulls in the Worker, so
 * it isn't imported here): any comma-separated entry equal to `dish`, ignoring case and spaces.
 */
const dishListed = (header: string | null): boolean => (header ?? "").split(",").some((id) => id.trim().toLowerCase() === "dish");
describe("the web player says it has the Dish", () => {
  test("in X-Pounce-Games on every call", async () => {
    const seen: Headers[] = [];
    const api = new Api("https://play.conleychaos.com", async (_url, init) => {
      seen.push(new Headers(init?.headers));
      return new Response(JSON.stringify({ deviceId: "d", token: "v1.d.mac", tables: [] }), { status: 200 });
    }, "test.dish.device");
    await api.listTables();
    const header = seen.at(-1)!.get("x-pounce-games");
    expect(dishListed(header)).toBe(true);
    expect(header).toBe("cat-tower,tiles,dish");
  });

  test("in games= on every browser socket", () => {
    const games = new URL(wsUrl("https://play.conleychaos.com", "/v1/daily/board/ws")).searchParams.get("games");
    expect(dishListed(games)).toBe(true);
    expect(new URL(wsUrl("https://play.conleychaos.com", "/v1/rooms/BCDFG/ws")).searchParams.get("games")).toBe(games);
  });

  test("and still draws the same table games", () => {
    expect(gamesListed("cat-tower,tiles,dish")).toEqual(gamesListed("cat-tower,tiles"));
  });
});
