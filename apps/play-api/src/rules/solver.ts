import { card, type Card, type CardId, type Coat } from "./cards";
import { canHit, buildGroup, type Group, type Requirement } from "./groups";
import { PHASES } from "./phases";

import type { Seat } from "./engine";

type LayGroup = { cards: CardId[]; runStart?: number };

/** A hand split into the pieces the solver works with. Cucumbers are dropped. */
type Pool = { naturals: Map<number, CardId[]>; yarn: CardId[] };

const MAX_VALUE = 12;

function toPool(ids: readonly CardId[]): Pool {
  const naturals = new Map<number, CardId[]>();
  const yarn: CardId[] = [];
  for (const id of ids) {
    const c = card(id);
    if (c.kind === "yarn") yarn.push(id);
    else if (c.kind === "number") {
      naturals.set(c.value, [...(naturals.get(c.value) ?? []), id]);
    }
  }
  return { naturals, yarn };
}

function without(ids: readonly CardId[], used: readonly CardId[]): CardId[] {
  return ids.filter((id) => !used.includes(id));
}

/**
 * Every group `req` can be built from `ids`, fewest Yarn first.
 *
 * Copies of one value are interchangeable for sets and runs, so each value
 * contributes its first copies only, and Yarn are taken from the front too.
 * That keeps the list small without losing any solution: a second group
 * enumerated from what is left sees the same copies, and the last group of a
 * phase takes a natural over a Yarn whenever it can because nothing competes
 * for it.
 */
function candidates(req: Requirement, ids: readonly CardId[]): LayGroup[] {
  const { naturals, yarn } = toPool(ids);
  const out: { yarns: number; group: LayGroup }[] = [];
  const add = (cards: CardId[], yarns: number, runStart?: number): void => {
    const group: LayGroup = runStart === undefined ? { cards } : { cards, runStart };
    if (buildGroup(req, cards, runStart) !== null) out.push({ yarns, group });
  };

  if (req.kind === "set") {
    for (const copies of naturals.values()) {
      for (let j = 1; j <= Math.min(copies.length, req.size); j++) {
        const pad = req.size - j;
        if (pad <= yarn.length) add([...copies.slice(0, j), ...yarn.slice(0, pad)], pad);
      }
    }
  } else if (req.kind === "coat") {
    for (const same of groupByCoat(naturals).values()) {
      const take = Math.min(same.length, req.size);
      const pad = req.size - take;
      if (pad <= yarn.length) add([...same.slice(0, take), ...yarn.slice(0, pad)], pad);
    }
  } else {
    for (let start = 1; start + req.size - 1 <= MAX_VALUE; start++) {
      const cards: CardId[] = [];
      let pad = 0;
      for (let value = start; value < start + req.size; value++) {
        const natural = naturals.get(value)?.[0];
        if (natural === undefined) pad++;
        else cards.push(natural);
      }
      if (pad <= yarn.length) add([...cards, ...yarn.slice(0, pad)], pad, start);
    }
  }
  return out.sort((a, b) => a.yarns - b.yarns).map((c) => c.group);
}

/**
 * A valid lay-down for `phaseIndex` from `hand`, groups in `PHASES` order and
 * ready for `matchPhase`, or null if none exists. Tries every candidate for
 * each group in turn on what the earlier groups left, preferring groups that
 * use fewer Yarn so Yarn stay available for later ones.
 */
export function findPhase(hand: CardId[], phaseIndex: number): LayGroup[] | null {
  const reqs = PHASES[phaseIndex];
  if (reqs === undefined) return null;
  const solve = (ids: readonly CardId[], index: number): LayGroup[] | null => {
    const req = reqs[index];
    if (req === undefined) return [];
    for (const group of candidates(req, ids)) {
      const rest = solve(without(ids, group.cards), index + 1);
      if (rest !== null) return [group, ...rest];
    }
    return null;
  };
  return solve(hand, 0);
}

/**
 * A heuristic for how close `hand` is to `phaseIndex`: the most hand cards
 * that can be assigned to the phase's groups, partial groups included. Each
 * group is scored by the natural cards it could hold (a set by the copies of
 * one value, a run by the distinct values in one window, a coat group by the
 * cards of one coat), choosing groups jointly so two groups never share a
 * card; Yarn then fill whatever slots are left. Cucumbers never count. It
 * only ranks hands for the bot and is not an exact distance to going down.
 */
export function phaseProgress(hand: CardId[], phaseIndex: number): number {
  const reqs = PHASES[phaseIndex];
  if (reqs === undefined) return 0;
  // counts[v] = copies of value v still unassigned; index 0 is unused.
  const counts = new Array<number>(MAX_VALUE + 1).fill(0);
  const coats = new Map<Coat, number>();
  let yarn = 0;
  for (const id of hand) {
    const c = card(id);
    if (c.kind === "yarn") yarn++;
    else if (c.kind === "number") {
      counts[c.value] = (counts[c.value] as number) + 1;
      coats.set(c.coat, (coats.get(c.coat) ?? 0) + 1);
    }
  }

  /** Most naturals groups `index`.. can hold; `counts` is borrowed and restored. */
  const best = (index: number): number => {
    const req = reqs[index];
    if (req === undefined) return 0;
    let top = 0;
    if (req.kind === "set") {
      top = best(index + 1);
      for (let value = 1; value <= MAX_VALUE; value++) {
        const have = counts[value] as number;
        for (let j = 1; j <= Math.min(have, req.size); j++) {
          counts[value] = have - j;
          top = Math.max(top, j + best(index + 1));
          counts[value] = have;
        }
      }
    } else {
      for (let start = 1; start + req.size - 1 <= MAX_VALUE; start++) {
        const taken: number[] = [];
        for (let value = start; value < start + req.size; value++) {
          if ((counts[value] as number) > 0) {
            counts[value] = (counts[value] as number) - 1;
            taken.push(value);
          }
        }
        top = Math.max(top, taken.length + best(index + 1));
        for (const value of taken) counts[value] = (counts[value] as number) + 1;
      }
    }
    return top;
  };

  const total = reqs.reduce((sum, r) => sum + r.size, 0);
  const natural =
    reqs[0]?.kind === "coat"
      ? Math.min(reqs[0].size, Math.max(0, ...coats.values()))
      : best(0);
  return natural + Math.min(yarn, total - natural);
}

function groupByCoat(naturals: Map<number, CardId[]>): Map<Coat, CardId[]> {
  const byCoat = new Map<Coat, CardId[]>();
  for (const id of [...naturals.values()].flat()) {
    const { coat } = card(id) as Extract<Card, { kind: "number" }>;
    byCoat.set(coat, [...(byCoat.get(coat) ?? []), id]);
  }
  return byCoat;
}

/**
 * Every card in `hand` that can be added to some laid-down group, with the
 * group it goes on. Numbers are listed before Yarn so a caller taking the
 * first hit spends a wild card only when nothing else fits.
 */
export function findHits(
  hand: CardId[],
  laid: (Group[] | null)[],
): { card: CardId; target: { seat: Seat; group: number } }[] {
  const yarnLast = [...hand].sort(
    (a, b) => Number(card(a).kind === "yarn") - Number(card(b).kind === "yarn"),
  );
  const hits: { card: CardId; target: { seat: Seat; group: number } }[] = [];
  for (const id of yarnLast) {
    for (const [seat, groups] of laid.entries()) {
      for (const [group, g] of (groups ?? []).entries()) {
        if (canHit(g, id).ok) hits.push({ card: id, target: { seat, group } });
      }
    }
  }
  return hits;
}
