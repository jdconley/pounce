import { describe, expect, it } from "vitest";

import { sharePage } from "./links";

const ORIGIN = "https://play.conleychaos.com";
const NOTE = "Update Pounce, then tap this link again.";

describe("the invite page while a newer game is on", () => {
  it("says what to do when the app can't find the table", async () => {
    const html = await sharePage("BCDFG", {}, ORIGIN, true).text();
    expect(html).toContain("Pounce can't find this table? It may be a newer game.");
    expect(html).toContain(NOTE);
    // Everything the page already said is still there.
    expect(html).toContain("Join the game");
    expect(html).toContain("tap Join and enter the code BCDFG");
  });

  it("says nothing of it otherwise: the page is what it always was", async () => {
    const plain = await sharePage("BCDFG", {}, ORIGIN).text();
    expect(plain).not.toContain(NOTE);
    expect(await sharePage("BCDFG", {}, ORIGIN, false).text()).toBe(plain);
  });

  it("differs from the plain page by that one paragraph only", async () => {
    const plain = await sharePage("BCDFG", {}, ORIGIN).text();
    const noted = await sharePage("BCDFG", {}, ORIGIN, true).text();
    expect(noted.replace(/<p>Pounce can't find this table\?[^<]*<\/p>\n/, "")).toBe(plain);
  });

  it("is the same for every code: the page never looks a table up", async () => {
    const a = await sharePage("BCDFG", {}, ORIGIN, true).text();
    const b = await sharePage("GFDCB", {}, ORIGIN, true).text();
    expect(a.replaceAll("BCDFG", "GFDCB")).toBe(b);
  });

  it("a code that can't be one still gets the dead link page", async () => {
    const html = await sharePage("nope", {}, ORIGIN, true).text();
    expect(html).not.toContain(NOTE);
  });
});
