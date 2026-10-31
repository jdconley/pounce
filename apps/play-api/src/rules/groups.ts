import { card, type Card, type CardId, type Coat } from "./cards";

export type GroupKind = "set" | "run" | "coat";

/** `cards` are in display order: runs ascend, Yarn sits at the value it stands for. */
export type Group =
  | { kind: "set"; cards: CardId[]; value: number }
  | { kind: "run"; cards: CardId[]; start: number; end: number }
  | { kind: "coat"; cards: CardId[]; coat: Coat };

export type Requirement = { kind: GroupKind; size: number };

type Natural = Extract<Card, { kind: "number" }>;

const MAX_VALUE = 12;

/**
 * Build a group for `req` from `cards`, or null if invalid. Needs exactly
 * `req.size` distinct cards, no Cucumbers and at least one natural card.
 * For a run containing Yarn, `runStart` (the value of the first card) picks the
 * placement; without it the lowest start that fits is used.
 */
export function buildGroup(
  req: Requirement,
  cards: CardId[],
  runStart?: number,
): Group | null {
  if (cards.length !== req.size || new Set(cards).size !== cards.length) {
    return null;
  }
  let decoded: Card[];
  try {
    decoded = cards.map(card);
  } catch {
    return null;
  }
  if (decoded.some((c) => c.kind === "cucumber")) return null;
  const naturals = decoded.filter((c): c is Natural => c.kind === "number");
  const first = naturals[0];
  if (first === undefined) return null;

  switch (req.kind) {
    case "set":
      return naturals.every((c) => c.value === first.value)
        ? { kind: "set", cards, value: first.value }
        : null;
    case "coat":
      return naturals.every((c) => c.coat === first.coat)
        ? { kind: "coat", cards, coat: first.coat }
        : null;
    case "run":
      return buildRun(decoded, naturals, runStart);
  }
}

function buildRun(
  decoded: Card[],
  naturals: Natural[],
  runStart: number | undefined,
): Group | null {
  const size = decoded.length;
  const values = naturals.map((c) => c.value);
  if (new Set(values).size !== values.length) return null;
  // A start fits when every natural lies in start..start+size-1 and the whole
  // run stays within 1..12.
  const lowest = Math.max(1, Math.max(...values) - size + 1);
  const highest = Math.min(Math.min(...values), MAX_VALUE + 1 - size);
  const start = runStart ?? lowest;
  if (!Number.isInteger(start) || start < lowest || start > highest) return null;

  const slots: (CardId | undefined)[] = new Array<CardId | undefined>(size);
  for (const c of naturals) slots[c.value - start] = c.id;
  const yarns = decoded.filter((c) => c.kind === "yarn").map((c) => c.id);
  const cards = Array.from(slots, (id) => id ?? (yarns.shift() as CardId));
  return { kind: "run", cards, start, end: start + size - 1 };
}

/**
 * Whether `id` can be added to a laid-down group. Returns the extended group
 * (the input is not mutated).
 */
export function canHit(
  group: Group,
  id: CardId,
): { ok: true; group: Group } | { ok: false } {
  const c = card(id);
  if (c.kind === "cucumber") return { ok: false };
  const cards = (front: boolean): CardId[] =>
    front ? [id, ...group.cards] : [...group.cards, id];

  switch (group.kind) {
    case "set":
      return c.kind === "yarn" || c.value === group.value
        ? { ok: true, group: { ...group, cards: cards(false) } }
        : { ok: false };
    case "coat":
      return c.kind === "yarn" || c.coat === group.coat
        ? { ok: true, group: { ...group, cards: cards(false) } }
        : { ok: false };
    case "run": {
      const atEnd = (): { ok: true; group: Group } => ({
        ok: true,
        group: { ...group, cards: cards(false), end: group.end + 1 },
      });
      const atStart = (): { ok: true; group: Group } => ({
        ok: true,
        group: { ...group, cards: cards(true), start: group.start - 1 },
      });
      if (c.kind === "yarn") {
        if (group.end < MAX_VALUE) return atEnd();
        return group.start > 1 ? atStart() : { ok: false };
      }
      if (c.value === group.end + 1) return atEnd();
      if (c.value === group.start - 1) return atStart();
      return { ok: false };
    }
  }
}
