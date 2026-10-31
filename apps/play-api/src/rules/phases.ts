import { buildGroup, type Group, type Requirement } from "./groups";

import type { CardId } from "./cards";

const set = (size: number): Requirement => ({ kind: "set", size });
const run = (size: number): Requirement => ({ kind: "run", size });
const coat = (size: number): Requirement => ({ kind: "coat", size });

/** The 10 phases; index 0 = phase 1. */
export const PHASES: readonly (readonly Requirement[])[] = [
  [set(3), set(3)],
  [set(3), run(4)],
  [set(4), run(4)],
  [run(7)],
  [run(8)],
  [run(9)],
  [set(4), set(4)],
  [coat(7)],
  [set(5), set(2)],
  [set(5), set(3)],
];

/**
 * Validate a lay-down against a phase. `groups` must be in `PHASES[phaseIndex]`
 * order and share no cards. Returns the built groups, or null if anything is
 * invalid.
 */
export function matchPhase(
  phaseIndex: number,
  groups: { cards: CardId[]; runStart?: number }[],
): Group[] | null {
  const reqs = PHASES[phaseIndex];
  if (reqs === undefined || groups.length !== reqs.length) return null;
  const seen = new Set<CardId>();
  const built: Group[] = [];
  for (const [i, req] of reqs.entries()) {
    const g = groups[i] as { cards: CardId[]; runStart?: number };
    for (const id of g.cards) {
      if (seen.has(id)) return null;
      seen.add(id);
    }
    const group = buildGroup(req, g.cards, g.runStart);
    if (group === null) return null;
    built.push(group);
  }
  return built;
}
