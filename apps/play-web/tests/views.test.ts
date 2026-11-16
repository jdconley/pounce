import { beforeEach, describe, expect, test } from "vitest";

import { store } from "../src/lib/kv";
import { setView, viewOf } from "../src/store/views";

beforeEach(() => store.remove("pounce.views"));

describe("the Cards or Table view, kept per table", () => {
  test("a table shows Cards until it is changed", () => {
    expect(viewOf("BCDFG")).toBe("cards");
    setView("BCDFG", "table");
    expect(viewOf("BCDFG")).toBe("table");
    expect(viewOf("HJKLM")).toBe("cards");
    setView("BCDFG", "cards");
    expect(viewOf("BCDFG")).toBe("cards");
  });

  test("only the newest 30 tables are kept", () => {
    for (let i = 0; i < 32; i++) setView(`T${i}`, "table");
    expect(viewOf("T0")).toBe("cards");
    expect(viewOf("T1")).toBe("cards");
    expect(viewOf("T2")).toBe("table");
    expect(viewOf("T31")).toBe("table");
    expect(Object.keys(store.json<Record<string, string>>("pounce.views")!)).toHaveLength(30);
  });

  test("a table set again counts as the newest", () => {
    for (let i = 0; i < 30; i++) setView(`T${i}`, "table");
    setView("T0", "table");
    setView("NEW", "table");
    expect(viewOf("T0")).toBe("table");
    expect(viewOf("T1")).toBe("cards");
  });
});
