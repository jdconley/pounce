import { describe, expect, test } from "vitest";

import { asAppSocket } from "./browser-socket";

const socket = (query: string) =>
  new Request(`https://play.conleychaos.com/v1/rooms/BCDFG/ws${query}`, {
    headers: { upgrade: "websocket", "sec-websocket-protocol": "pounce, pounce.token.abc" },
  });

describe("asAppSocket", () => {
  test("keeps only role=screen of the query, and moves games and the token to headers", () => {
    const out = asAppSocket(socket("?role=screen&x=1&games=tiles"));
    expect(new URL(out.url).search).toBe("?role=screen");
    expect(out.headers.get("x-pounce-games")).toBe("tiles");
    expect(out.headers.get("authorization")).toBe("Bearer abc");
  });

  test("any other role is dropped with the rest", () => {
    expect(new URL(asAppSocket(socket("?role=other")).url).search).toBe("");
    expect(new URL(asAppSocket(socket("")).url).search).toBe("");
  });
});

describe("asAppSocket on the Daily Dish's board socket", () => {
  const board = (query: string) =>
    new Request(`https://play.conleychaos.com/v1/daily/board/ws${query}`, {
      headers: { upgrade: "websocket", "sec-websocket-protocol": "pounce, pounce.token.abc" },
    });

  test("keeps the person or the board token, and nothing else", () => {
    expect(new URL(asAppSocket(board("?person=p1&x=1")).url).search).toBe("?person=p1");
    expect(new URL(asAppSocket(board(`?board=${"A".repeat(22)}&games=tiles`)).url).search).toBe(`?board=${"A".repeat(22)}`);
    expect(new URL(asAppSocket(board(`?person=${"x".repeat(201)}`)).url).search).toBe("");
  });

  test("a room socket still drops them", () => {
    expect(new URL(asAppSocket(socket("?person=p1&board=b")).url).search).toBe("");
  });
});
