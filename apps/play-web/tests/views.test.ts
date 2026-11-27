import { beforeEach, describe, expect, test } from "vitest";

import { store } from "../src/lib/kv";
import { carryView, setView, showController, showSwitch, viewAfterLayDown, viewOf } from "../src/store/views";

import type { RoomView } from "@pounce/play-api/protocol";

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

  test("Play again carries the view to the new table", () => {
    setView("OLD01", "table");
    carryView("OLD01", "NEW01");
    expect(viewOf("NEW01")).toBe("table");
    setView("OLD02", "cards");
    setView("NEW02", "table");
    carryView("OLD02", "NEW02");
    expect(viewOf("NEW02")).toBe("cards");
    // Never chosen: nothing is written for the new table.
    carryView("OLD03", "NEW03");
    expect(Object.keys(store.json<Record<string, string>>("pounce.views")!)).not.toContain("NEW03");
  });

  test("a table set again counts as the newest", () => {
    for (let i = 0; i < 30; i++) setView(`T${i}`, "table");
    setView("T0", "table");
    setView("NEW", "table");
    expect(viewOf("T0")).toBe("table");
    expect(viewOf("T1")).toBe("cards");
  });
});

describe("the controller or the full table", () => {
  /** A table with seat 0 this device's (or nobody's), and a TV showing it (or not). */
  const room = (opts: { screen?: boolean; seated?: boolean }): RoomView =>
    ({
      code: "BCDFG",
      ...(opts.screen ? { screen: true } : {}),
      seats: [
        { kind: "human", yours: opts.seated ?? true, person: { id: "a", name: "Mo", cat: 1 } },
        { kind: "human", yours: false, person: { id: "b", name: "Ava", cat: 2 } },
      ],
    }) as unknown as RoomView;

  test("a seated phone shows the controller while a TV shows the table and it is on Cards", () => {
    expect(showController(room({ screen: true }), "cards")).toBe(true);
  });

  test("Table is the full table, TV or not", () => {
    expect(showController(room({ screen: true }), "table")).toBe(false);
  });

  test("with no TV every phone shows the full table, whatever the switch says", () => {
    expect(showController(room({}), "cards")).toBe(false);
    expect(showSwitch(room({}))).toBe(false);
  });

  test("a phone with no seat (watching) shows the full table and no switch", () => {
    expect(showController(room({ screen: true, seated: false }), "cards")).toBe(false);
    expect(showSwitch(room({ screen: true, seated: false }))).toBe(false);
  });

  test("the switch shows in both views while the TV is on", () => {
    expect(showSwitch(room({ screen: true }))).toBe(true);
  });

  test("a phone on Table when the TV comes back stays on Table", () => {
    setView("BCDFG", "table");
    expect(showController(room({}), viewOf("BCDFG"))).toBe(false);
    expect(showController(room({ screen: true }), viewOf("BCDFG"))).toBe(false);
    setView("BCDFG", "cards");
    expect(showController(room({ screen: true }), viewOf("BCDFG"))).toBe(true);
  });

  test("laying down on Cards turns this phone to the Table, for its groups and the hits", () => {
    expect(viewAfterLayDown(room({ screen: true }), "cards", 0)).toBe("table");
  });

  test("someone else laying down changes nothing, and Table stays Table", () => {
    expect(viewAfterLayDown(room({ screen: true }), "cards", 1)).toBe("cards");
    expect(viewAfterLayDown(room({ screen: true }), "table", 0)).toBe("table");
  });

  test("with no TV there is no switch to turn", () => {
    expect(viewAfterLayDown(room({}), "cards", 0)).toBe("cards");
  });
});
