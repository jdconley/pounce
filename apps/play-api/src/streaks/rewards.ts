import { DEFAULT_RUG, isBigMilestone, NORMAL_BACKS, RARE_BACKS, RUGS, TOYS, type Rarity } from "./catalog";

import type { Rng } from "../rules/rng";

/** Kept days since the last shiny-or-better toy, and since the last golden one. */
export type Pity = { shiny: number; golden: number };

/** A shiny by the 7th kept day without one, a golden by the 30th (§9.3). */
const SHINY_PITY = 6;
const GOLDEN_PITY = 29;
const GOLDEN_ODDS = 0.03;
const SHINY_ODDS = 0.15;
const RARITIES: readonly Rarity[] = ["golden", "shiny", "common"];

/** The gift when there's nothing left to give (§9.2). */
export const CONFETTI = "confetti";

const pick = <T>(items: readonly T[], rng: Rng): T => items[Math.floor(rng() * items.length)] as T;

function rollRarity(pity: Pity, rng: Rng): Rarity {
  if (pity.golden >= GOLDEN_PITY) return "golden";
  if (pity.shiny >= SHINY_PITY) return "shiny";
  const r = rng();
  if (r < GOLDEN_ODDS) return "golden";
  return r < GOLDEN_ODDS + SHINY_ODDS ? "shiny" : "common";
}

/**
 * Today's toy (§9.3): no duplicates until the set is complete, with pity for
 * shiny and golden. When the rolled rarity is used up, the rarest one left.
 */
export function drawToy(owned: readonly string[], pity: Pity, rng: Rng): { toy: string; pity: Pity } {
  const unowned = TOYS.filter((t) => !owned.includes(t.id));
  const pool = unowned.length > 0 ? unowned : TOYS;
  const rolled = rollRarity(pity, rng);
  const rarity = [rolled, ...RARITIES].find((r) => pool.some((t) => t.rarity === r)) as Rarity;
  const toy = pick(
    pool.filter((t) => t.rarity === rarity),
    rng,
  ).id;
  const next: Pity =
    rarity === "golden"
      ? { shiny: 0, golden: 0 }
      : rarity === "shiny"
        ? { shiny: 0, golden: pity.golden + 1 }
        : { shiny: pity.shiny + 1, golden: pity.golden + 1 };
  return { toy, pity: next };
}

/**
 * A milestone's gift (§9.2): something the pair doesn't own from the
 * milestone's tier, else a toy they don't own, else confetti.
 */
export function giftItem(milestone: number, owned: readonly string[], rng: Rng): string {
  const tier = isBigMilestone(milestone)
    ? [...RUGS.filter((r) => r !== DEFAULT_RUG), ...RARE_BACKS]
    : [...TOYS.map((t) => t.id), ...NORMAL_BACKS];
  const fresh = tier.filter((id) => !owned.includes(id));
  if (fresh.length > 0) return pick(fresh, rng);
  const toys = TOYS.map((t) => t.id).filter((id) => !owned.includes(id));
  return toys.length > 0 ? pick(toys, rng) : CONFETTI;
}
