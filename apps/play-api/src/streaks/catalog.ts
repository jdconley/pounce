/**
 * Everything a pair can earn (§9). Ids match the art file names (§9.6:
 * `toy-*`, `back-*`, `rug-*`), so placeholders swap for art by name.
 */
export type Rarity = "common" | "shiny" | "golden";

const toys = (rarity: Rarity, names: string[]) => names.map((n) => ({ id: `toy-${n}`, rarity }));

/** 24 toys: 16 common, 6 shiny, 2 golden (§9.3). */
export const TOYS: readonly { id: string; rarity: Rarity }[] = [
  ...toys("common", [
    "yarn-ball",
    "feather-wand",
    "cardboard-box",
    "mouse",
    "fish",
    "bell",
    "laser-dot",
    "catnip-sack",
    "sock",
    "bottle-cap",
    "crinkle-ball",
    "spring",
    "ribbon",
    "paper-bag",
    "pom-pom",
    "cork",
  ]),
  ...toys("shiny", ["rainbow-yarn", "glitter-mouse", "silver-bell", "moon-fish", "star-wand", "disco-ball"]),
  ...toys("golden", ["golden-fish", "golden-mouse"]),
];

export const DEFAULT_BACK = "back-violet-paw";
export const NORMAL_BACKS: readonly string[] = ["back-yarn-swirl", "back-moonlit-fish", "back-cucumber-chaos"];
export const RARE_BACKS: readonly string[] = ["back-crown", "back-heart-paws"];
/** Unlocked by a full set of toys (§9.3), never by a gift. */
export const FULL_SET_BACK = "back-golden-yarn";
export const BACKS: readonly string[] = [DEFAULT_BACK, ...NORMAL_BACKS, ...RARE_BACKS, FULL_SET_BACK];

/** The magenta, teal and orange rug every table has today. */
export const DEFAULT_RUG = "rug-classic";
export const RUGS: readonly string[] = [DEFAULT_RUG, "rug-night-sky", "rug-candy-stripe", "rug-fish-pond", "rug-royal-violet"];

export const isBack = (id: string): boolean => BACKS.includes(id);
export const isRug = (id: string): boolean => RUGS.includes(id);

const MILESTONES = [3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365];
const LAST_LISTED = 365;
const EVERY_AFTER = 100;
const BIG = [7, 30, 100, 365];

/** 3, 7, 14, …, 365, then every hundred: 400, 500, … */
export function isMilestone(n: number): boolean {
  return MILESTONES.includes(n) || (n > LAST_LISTED && n % EVERY_AFTER === 0);
}

export function nextMilestone(n: number): number {
  const listed = MILESTONES.find((m) => m > n);
  return listed ?? (Math.floor(n / EVERY_AFTER) + 1) * EVERY_AFTER;
}

/** Big milestones give a rug or a rare card back (§9.2). */
export function isBigMilestone(n: number): boolean {
  return BIG.includes(n) || n > LAST_LISTED;
}

/** Lifetime days together at which the condo gains a stage (§9.1). */
export const CONDO: readonly number[] = [1, 3, 7, 14, 30, 50, 100, 150, 200, 365];

export function condoStage(lifetimeKept: number): number {
  return CONDO.filter((t) => lifetimeKept >= t).length;
}
