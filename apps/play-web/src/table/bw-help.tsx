/**
 * How to play Birdwatch, one page per rule set (design §5.8), in our own words from §4. The one
 * place for a few sentences; the table itself teaches with one tip at a time.
 */
import { useState } from "preact/hooks";

import { Sheet } from "../ui/common";

import { RULE_COPY, RULES_ORDER, type RuleSetId } from "./bw-model";

const POINTS: Record<RuleSetId, string> = {
  official: "Points: 5s are 5, 10s and 14s are 10, the Bird is 20. 120 a hand.",
  tucker: "Points: 5s are 5, 10s and 14s are 10, 1s are 15, the Bird is 20. 180 a hand.",
  friesen: "Points: 5s are 5, 10s and 14s are 10, 1s are 15, the Bird is 20. 180 a hand.",
};

const BIRD: Record<RuleSetId, string> = {
  official: "No 1s. The Bird is top trump and plays any time.",
  tucker: "1s rank above 14. The Bird is top trump and plays any time.",
  friesen: "1s rank above 14. The Bird is top trump but follows suit like any trump.",
};

const TARGET: Record<RuleSetId, number> = { official: 300, tucker: 500, friesen: 500 };

/** The tips for one rule set, in order. */
export function howToPlay(rules: RuleSetId): string[] {
  return [
    "Bid on the points your side will take. The high bid takes the feeder and names trump.",
    "Follow the suit led if you can. The highest trump wins, else the highest card of the suit led.",
    BIRD[rules],
    POINTS[rules],
    "Make your bid to score what you took. Miss it and lose the bid.",
    "With 5 players, the bid winner calls a card. Whoever holds it is their secret partner.",
    `First side to ${TARGET[rules]} wins.`,
  ];
}

export function BwHowTo(props: { rules: RuleSetId; onClose: () => void }) {
  const [rules, setRules] = useState(props.rules);
  return (
    <Sheet title="How to play" onClose={props.onClose}>
      <div class="bw-pills small" role="radiogroup" aria-label="Rules">
        {RULES_ORDER.map((r) => (
          <button type="button" role="radio" aria-checked={r === rules} class={`bw-pill ${r === rules ? "on" : ""}`} onClick={() => setRules(r)}>
            {RULE_COPY[r].name}
          </button>
        ))}
      </div>
      <ol class="bw-howto">
        {howToPlay(rules).map((t) => (
          <li>{t}</li>
        ))}
      </ol>
    </Sheet>
  );
}
