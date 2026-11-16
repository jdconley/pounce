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
