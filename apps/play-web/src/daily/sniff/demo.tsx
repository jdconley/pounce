/**
 * Dev only: Sniff on local state, with no server, until the Dish's host runs it (phase B). The
 * demo referee answers with the server's own reveals for one run (`DEMO_SCRIPT`, copied from
 * `apps/play-api/fixtures/daily/sniff/runs.json` and checked against it by the tests); any other
 * word comes back plain. The top bar stands in for the host's.
 */
import { render } from "preact";

import "@fontsource/nunito/latin-900.css";
import "../../styles.css";

import { emptyBoard, type SniffBoard } from "./board";
import { SniffPlay } from "./sniff";
import SniffWatch from "./watch";

import type { Mark, SniffReveal } from "@pounce/play-api/daily/sniff/types";

const reveal = (word: string, marks: string, answer?: string): SniffReveal => ({
  word,
  marks: marks.split(" ") as Mark[],
  ...(answer ? { answer } : {}),
});

export const DEMO_ANSWER = "kitty";
export const DEMO_SCRIPT: SniffReveal[] = [
  reveal("tatty", "none none spot spot spot"),
  reveal("otter", "none near spot none none"),
  reveal("witty", "none spot spot spot spot"),
  reveal("bitty", "none spot spot spot spot"),
  reveal("ditty", "none spot spot spot spot"),
  reveal("kitty", "spot spot spot spot spot", DEMO_ANSWER),
];

export function demoReveal(word: string): SniffReveal {
  return DEMO_SCRIPT.find((r) => r.word === word) ?? reveal(word, "none none none none none");
}

function startBoard(name: string): SniffBoard {
  const guesses = DEMO_SCRIPT.map(({ word, marks }) => ({ word, marks }));
  switch (name) {
    case "mid":
      return { ...emptyBoard(), guesses: guesses.slice(0, 2) };
    case "solved":
      return { ...emptyBoard(), guesses, answer: DEMO_ANSWER };
    case "missed":
    case "watch":
      return { ...emptyBoard(), guesses: [...guesses.slice(0, 5), reveal("crane", "none none none none none")], answer: DEMO_ANSWER };
    default:
      return emptyBoard();
  }
}

const app = document.getElementById("app");
if (app) {
  const name = new URLSearchParams(location.search).get("board") ?? "fresh";
  const board = startBoard(name);
  const referee = (word: string) =>
    new Promise<SniffReveal>((done) => requestAnimationFrame(() => requestAnimationFrame(() => done(demoReveal(word)))));
  render(
    <div style={{ position: "fixed", inset: 0, display: "flex", flexDirection: "column", background: "var(--night)" }}>
      <h1 style={{ margin: "calc(var(--safe-top) + 10px) 0 0", textAlign: "center", fontFamily: "var(--round)", fontWeight: 900 }}>Sniff</h1>
      <div style={{ flex: "1 1 auto", minHeight: 0 }}>
        {name === "watch" ? <SniffWatch puzzle={{ letters: 5, tries: 6 }} state={{ guesses: board.guesses, answer: DEMO_ANSWER }} /> : <SniffPlay start={board} referee={referee} />}
      </div>
    </div>,
    app,
  );
}
