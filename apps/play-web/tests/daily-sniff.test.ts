// @vitest-environment happy-dom
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { h, render } from "preact";
import { describe, expect, test } from "vitest";

import { emptyBoard, isOver, isSolved, keys, reveal, refused, submit, typeLetter, deleteLetter } from "../src/daily/sniff/board";
import { SniffTrail } from "../src/daily/sniff/trail";
import SniffWatch from "../src/daily/sniff/watch";

import type { RunEvent, RunSession, StartAnswer } from "../src/daily/client";
import type { Guess, Mark, SniffMove, SniffPublic, SniffReveal, SniffView } from "@pounce/play-api/daily/sniff/types";

const allowed = (w: string) => ["plant", "crane", "kitty", "dummy"].includes(w);
const g = (word: string, marks: string): Guess => ({ word, marks: marks.split(" ") as Mark[] });
const typed = (word: string) => [...word].reduce(typeLetter, emptyBoard());

describe("Sniff's board as typed", () => {
  test("typing stops at five letters, lowercases, and skips non-letters", () => {
    expect(typed("PLANTS").draft).toBe("plant");
    expect(typeLetter(typed("pla"), "1").draft).toBe("pla");
    let b = typed("pl");
    for (let i = 0; i < 4; i++) b = deleteLetter(b);
    expect(b.draft).toBe("");
  });

  test("submit: short, then unknown, then sent; busy while waiting", () => {
    expect(submit(typed("pla"), allowed).outcome).toBe("short");
    const unknown = submit(typed("plazz"), allowed);
    expect(unknown.outcome).toBe("unknown");
    expect(unknown.board.guesses).toEqual([]);
    const sent = submit(typed("plant"), allowed);
    expect(sent).toMatchObject({ outcome: "send", word: "plant" });
    expect(sent.board.pending).toBe("plant");
    expect(typeLetter(sent.board, "x").draft).toBe("plant");
    expect(deleteLetter(sent.board).draft).toBe("plant");
    expect(submit(sent.board, allowed).outcome).toBe("busy");
  });

  test("a reveal adds the guess and clears the row; a refusal keeps it", () => {
    const sent = submit(typed("crane"), allowed).board;
    const after = reveal(sent, { ...g("crane", "none none spot spot none") });
    expect(after.guesses).toHaveLength(1);
    expect(after.draft).toBe("");
    expect(after.pending).toBeNull();
    const back = refused(sent);
    expect(back.pending).toBeNull();
    expect(back.draft).toBe("crane");
  });

  test("solved or six guesses is over, and over takes no more", () => {
    const solved = reveal(emptyBoard(), { ...g("plant", "spot spot spot spot spot"), answer: "plant" });
    expect(isSolved(solved)).toBe(true);
    expect(isOver(solved)).toBe(true);
    expect(solved.answer).toBe("plant");
    expect(typeLetter(solved, "a").draft).toBe("");
    expect(submit(solved, allowed).outcome).toBe("over");
    let missed = emptyBoard();
    for (let i = 0; i < 6; i++) missed = reveal(missed, g("dummy", "none none none none none"));
    expect(isOver(missed)).toBe(true);
    expect(isSolved(missed)).toBe(false);
  });

  test("the keyboard keeps each letter's best mark", () => {
    const b = { ...emptyBoard(), guesses: [g("crate", "none none near none near"), g("plant", "none none spot none none")] };
    expect(keys(b).a).toBe("spot");
    expect(keys(b).c).toBe("none");
    expect(keys(b).z).toBeUndefined();
  });
});

describe("the trail", () => {
  test("marks are shapes: a filled paw, an outlined paw, or none", () => {
    const host = document.createElement("div");
    render(h(SniffTrail, { board: { ...emptyBoard(), guesses: [g("otter", "none near spot none none")] } }), host);
    const tags = [...host.querySelectorAll(".sniff-tag")];
    expect(tags).toHaveLength(30);
    const [o, t1, t2] = tags as HTMLElement[];
    expect(t2!.dataset.mark).toBe("spot");
    expect(t2!.querySelector(".paw.filled")).not.toBeNull();
    expect(t1!.dataset.mark).toBe("near");
    expect(t1!.querySelector(".paw.outlined")).not.toBeNull();
    expect(o!.dataset.mark).toBe("none");
    expect(o!.querySelector(".paw")).toBeNull();
    expect(t2!.getAttribute("aria-label")).toBe("T, right spot");
  });

  test("the watch view shows the answer under a missed run", () => {
    const host = document.createElement("div");
    const guesses = Array.from({ length: 6 }, () => g("dummy", "none none none none none"));
    render(h(SniffWatch, { puzzle: { letters: 5, tries: 6 }, state: { guesses, answer: "kitty" } }), host);
    expect(host.querySelectorAll(".sniff-tag[data-mark=answer]")).toHaveLength(5);
    expect(host.textContent).toContain("K");
  });
});

describe("Sniff's web files", () => {
  /** Every file `file` loads statically (not type-only imports, which the build erases). */
  function staticGraph(file: string, seen = new Set<string>()): Set<string> {
    if (seen.has(file)) return seen;
    seen.add(file);
    for (const m of readFileSync(file, "utf8").matchAll(/^\s*(?:import|export)\s(?!type\s)[^;]*?from\s+"(\.[^"]+)"/gm)) {
      const base = join(dirname(file), m[1]!);
      const found = [".tsx", ".ts"].map((ext) => base + ext).find((p) => readdirSync(dirname(p)).includes(p.slice(dirname(p).length + 1)));
      if (found) staticGraph(found, seen);
    }
    return seen;
  }

  test("the TV's watch view loads alone: no play screen, keyboard or sound", () => {
    const dir = join(dirname(fileURLToPath(import.meta.url)), "../src/daily/sniff");
    const graph = [...staticGraph(join(dir, "watch.tsx"))].map((p) => p.slice(dir.length + 1));
    expect(graph).toContain("trail.tsx");
    for (const heavy of ["sniff.tsx", "keys.tsx", "dish.tsx", "demo.tsx"]) expect(graph).not.toContain(heavy);
  });

  test("never import the answers or the server module", () => {
    const dir = join(dirname(fileURLToPath(import.meta.url)), "../src/daily/sniff");
    for (const file of readdirSync(dir).filter((f) => /\.tsx?$/.test(f))) {
      const source = readFileSync(join(dir, file), "utf8");
      const imports = [...source.matchAll(/\bfrom\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']/g)].map((m) => m[1] ?? m[2]);
      for (const spec of imports.filter((s) => s!.startsWith("@pounce/play-api"))) {
        expect(spec, file).toMatch(/^@pounce\/play-api\/daily\/(module|sniff\/(types|keyboard|allowed-check))$/);
      }
    }
  });
});

describe("the demo", () => {
  test("its script is the server's own repeated-letter run", async () => {
    const { DEMO_ANSWER, DEMO_SCRIPT, demoReveal } = await import("../src/daily/sniff/demo");
    const file = join(dirname(fileURLToPath(import.meta.url)), "../../play-api/fixtures/daily/sniff/runs.json");
    const run = (JSON.parse(readFileSync(file, "utf8")) as { runs: { answer: string; answers: { reveal?: unknown }[] }[] }).runs[1]!;
    expect(DEMO_ANSWER).toBe(run.answer);
    expect(DEMO_SCRIPT).toEqual(run.answers.filter((a) => a.reveal).map((a) => a.reveal));
    expect(demoReveal("crane").marks).toEqual(["none", "none", "none", "none", "none"]);
  });
});

describe("Sniff in the Dish's host", () => {
  type Sent = { move: unknown; options: unknown };
  type Listener = (e: RunEvent<SniffView, SniffReveal>) => void;

  function fakeSession(state: SniffView, answer: (word: string) => SniffReveal | null) {
    const sent: Sent[] = [];
    const listeners: Listener[] = [];
    const session = {
      start: { puzzle: { letters: 5, tries: 6 }, state } as StartAnswer<SniffPublic, SniffView>,
      game: "sniff",
      result: null,
      hints: 0,
      send: (move: SniffMove, options?: unknown) => {
        sent.push({ move, options });
        return Promise.resolve(answer(move.word));
      },
      flush: () => Promise.resolve(),
      hint: () => Promise.resolve(null),
      giveUp: () => Promise.resolve(null),
      subscribe: (l: Listener) => {
        listeners.push(l);
        return () => listeners.splice(listeners.indexOf(l), 1);
      },
      serverNow: () => 0,
      elapsedMs: () => 0,
    } as unknown as RunSession<SniffPublic, SniffView, SniffMove, SniffReveal>;
    return { session, sent, emit: (e: RunEvent<SniffView, SniffReveal>) => listeners.forEach((l) => l(e)) };
  }

  const settle = () => new Promise((done) => setTimeout(done, 60));
  const press = async (key: string) => {
    window.dispatchEvent(new KeyboardEvent("keydown", { key }));
    await settle();
  };
  const word = async (w: string) => {
    for (const k of w) await press(k);
    await press("Enter");
  };

  test("draws the server's state, sends each guess urgently, and shows its marks", async () => {
    const { default: sniff } = await import("../src/daily/sniff/dish");
    const host = document.createElement("div");
    document.body.append(host);
    const fake = fakeSession({ guesses: [g("crate", "none none spot none none")] }, (w) => ({ ...g(w, "spot spot spot spot spot"), answer: w }));
    render(h(sniff.Screen, { session: fake.session, playing: true }), host);
    await settle();
    expect(host.querySelectorAll(".sniff-tag[data-mark=none]")).toHaveLength(4);
    await word("plant");
    expect(fake.sent).toEqual([{ move: { k: "guess", word: "plant" }, options: { urgent: true } }]);
    expect(host.querySelectorAll(".sniff-tag[data-mark=spot]")).toHaveLength(6);
    render(null, host);
    host.remove();
  });

  test("an unknown word is never sent", async () => {
    const { default: sniff } = await import("../src/daily/sniff/dish");
    const host = document.createElement("div");
    document.body.append(host);
    const fake = fakeSession({ guesses: [] }, () => null);
    render(h(sniff.Screen, { session: fake.session, playing: true }), host);
    await settle();
    await word("zzzzz");
    expect(fake.sent).toEqual([]);
    expect(host.textContent).toContain("Not a word");
    render(null, host);
    host.remove();
  });

  test("a resync redraws from the server's state", async () => {
    const { default: sniff } = await import("../src/daily/sniff/dish");
    const host = document.createElement("div");
    document.body.append(host);
    const fake = fakeSession({ guesses: [] }, () => null);
    render(h(sniff.Screen, { session: fake.session, playing: true }), host);
    await settle();
    fake.emit({ kind: "resync", seq: 2, state: { guesses: [g("crane", "near none none none none"), g("slate", "none none none none near")] } });
    await settle();
    expect(host.querySelectorAll(".sniff-tag[data-mark=near]")).toHaveLength(2);
    // The same seq again still redraws.
    fake.emit({ kind: "resync", seq: 2, state: { guesses: [g("crane", "near none none none none")] } });
    await settle();
    expect(host.querySelectorAll(".sniff-tag[data-mark=near]")).toHaveLength(1);
    render(null, host);
    host.remove();
  });

  test("once the run is over, keys do nothing", async () => {
    const { default: sniff } = await import("../src/daily/sniff/dish");
    const host = document.createElement("div");
    document.body.append(host);
    const fake = fakeSession({ guesses: [] }, () => null);
    render(h(sniff.Screen, { session: fake.session, playing: false }), host);
    await settle();
    await word("plant");
    expect(fake.sent).toEqual([]);
    expect(host.querySelector(".sniff-tag[data-mark=typed]")).toBeNull();
    expect([...host.querySelectorAll<HTMLButtonElement>(".sniff-key")].every((b) => b.disabled)).toBe(true);
    render(null, host);
    host.remove();
  });

  test("share gives paws by row and never a letter", async () => {
    const { default: sniff } = await import("../src/daily/sniff/dish");
    const state: SniffView = { guesses: [g("otter", "none near spot none none"), g("kitty", "spot spot spot spot spot")], answer: "kitty" };
    const grid = sniff.share!(state, {} as never);
    expect(grid).toEqual([
      ["none", "half", "full", "none", "none"],
      ["full", "full", "full", "full", "full"],
    ]);
    expect(JSON.stringify(grid)).not.toMatch(/kitty|otter/);
  });
});
