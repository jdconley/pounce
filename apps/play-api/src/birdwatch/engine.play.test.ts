import { describe, expect, test } from "vitest";

import { bell, errorOf, feather, fish, inPlay, mouse, ok } from "../../tests/birdwatch-helpers";

import { BIRD } from "./cards";
import { applyAction, playable, trickWinner, type BirdState, type TrickCard } from "./engine";
import { RULE_SETS } from "./rules";

/** Seat 0 has led `lead`; seat 1 holds `hand`. */
function led(lead: number, hand: number[], rules: "official" | "tucker" | "friesen" = "official"): BirdState {
  const s = inPlay({ rules, hands: [[lead, feather(6)], hand, [bell(9), bell(11)], [mouse(6), mouse(7)]], trump: "fish" });
  return ok(applyAction(s, 0, { type: "play", card: lead })).state;
}

describe("following suit", () => {
  test("you must follow the suit that was led if you can", () => {
    const s = led(mouse(10), [mouse(5), bell(7)], "friesen");
    expect(playable(s, 1)).toEqual([mouse(5)]);
    expect(errorOf(applyAction(s, 1, { type: "play", card: bell(7) }))).toBe("must_follow");
    expect(errorOf(applyAction(s, 1, { type: "play", card: bell(12) }))).toBe("not_your_card");
    expect(errorOf(applyAction(s, 2, { type: "play", card: bell(9) }))).toBe("not_your_turn");
  });

  test("you may play anything when you can't, trump included", () => {
    expect(playable(led(mouse(10), [fish(5), bell(7)]), 1)).toEqual([fish(5), bell(7)]);
  });

  test("the lead may be any card", () => {
    const s = inPlay({ hands: [[fish(5), mouse(9), BIRD], [bell(5)], [bell(6)], [bell(7)]] });
    expect(playable(s, 0)).toEqual([fish(5), mouse(9), BIRD]);
    expect(playable(s, 1)).toEqual([]);
  });

  test.each(["official", "tucker"] as const)("%s: the Bird may go on anything, even when you could follow", (rules) => {
    expect(playable(led(mouse(10), [mouse(5), bell(7), BIRD], rules), 1)).toEqual([mouse(5), BIRD]);
  });

  test("friesen: the Bird is only a trump, so it can't go on a suit you can follow", () => {
    expect(playable(led(mouse(10), [mouse(5), bell(7), BIRD], "friesen"), 1)).toEqual([mouse(5)]);
    // Can't follow: anything, the Bird included.
    expect(playable(led(mouse(10), [bell(7), BIRD], "friesen"), 1)).toEqual([bell(7), BIRD]);
  });

  test.each(["official", "tucker", "friesen"] as const)("%s: trump led and the Bird your only trump, you must play it", (rules) => {
    expect(playable(led(fish(10), [mouse(5), BIRD], rules), 1)).toEqual([BIRD]);
  });

  test.each(["official", "friesen"] as const)("%s: leading the Bird leads trump", (rules) => {
    const s = inPlay({ rules, hands: [[BIRD, bell(6)], [fish(5), mouse(7)], [bell(9)], [mouse(6)]], trump: "fish" });
    expect(playable(ok(applyAction(s, 0, { type: "play", card: BIRD })).state, 1)).toEqual([fish(5)]);
  });
});

describe("who takes a trick", () => {
  const rules = RULE_SETS.tucker;
  const trick = (...cards: number[]): TrickCard[] => cards.map((card, seat) => ({ seat, card }));

  test("the highest card of the suit led, with no trump in it", () => {
    expect(trickWinner(trick(mouse(10), mouse(14), bell(14), mouse(5)), "fish", rules)).toBe(1);
  });

  test("any trump beats the suit led, and the highest trump wins", () => {
    expect(trickWinner(trick(mouse(10), mouse(14), fish(5), bell(14)), "fish", rules)).toBe(2);
    expect(trickWinner(trick(mouse(10), fish(14), fish(5), fish(1)), "fish", rules)).toBe(3);
  });

  test("the Bird beats everything, led or not", () => {
    expect(trickWinner(trick(fish(1), BIRD, fish(14)), "fish", rules)).toBe(1);
    expect(trickWinner(trick(BIRD, fish(1), fish(14)), "fish", rules)).toBe(0);
  });

  test("a 1 is the highest of its suit in tucker and friesen", () => {
    expect(trickWinner(trick(bell(14), bell(1)), "fish", RULE_SETS.friesen)).toBe(1);
  });

  test("the winner of a trick scores its counters and leads the next", () => {
    let s = inPlay({ hands: [[mouse(10), bell(6)], [mouse(14), bell(7)], [fish(5), bell(8)], [mouse(5), bell(9)]], trump: "fish" });
    for (const [seat, card] of [[0, mouse(10)], [1, mouse(14)], [2, fish(5)]] as const) s = ok(applyAction(s, seat, { type: "play", card })).state;
    const { state, events } = ok(applyAction(s, 3, { type: "play", card: mouse(5) }));
    expect(events).toEqual([
      { kind: "played", seat: 3, card: mouse(5) },
      {
        kind: "trick",
        winner: 2,
        cards: [{ seat: 0, card: mouse(10) }, { seat: 1, card: mouse(14) }, { seat: 2, card: fish(5) }, { seat: 3, card: mouse(5) }],
        points: 30,
      },
      { kind: "turn", seat: 2 },
    ]);
    expect([state.points, state.tricks, state.leader, state.trick]).toEqual([[0, 0, 30, 0], [0, 0, 1, 0], 2, []]);
    expect(state.lastTrick?.winner).toBe(2);
    expect(state.played).toEqual([mouse(10), mouse(14), fish(5), mouse(5)]);
  });
});

describe("five players: the partner", () => {
  test("playing the called card tells everyone who the partner is", () => {
    const hands = [[bell(6), bell(7)], [bell(8), bell(9)], [mouse(14), mouse(5)], [bell(11), bell(12)], [bell(13), feather(6)]];
    const s = inPlay({ seats: 5, hands, trump: "fish", over: { called: mouse(14), holder: 2 } });
    let t = ok(applyAction(s, 0, { type: "play", card: bell(6) })).state;
    t = ok(applyAction(t, 1, { type: "play", card: bell(8) })).state;
    expect(t.partner).toBeNull();
    const { state, events } = ok(applyAction(t, 2, { type: "play", card: mouse(14) }));
    expect(events.slice(0, 2)).toEqual([{ kind: "played", seat: 2, card: mouse(14) }, { kind: "partner", seat: 2 }]);
    expect(state.partner).toBe(2);
  });
});
