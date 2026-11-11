/**
 * Push copy (§12.2). The voice is the cats: warm, a little dramatic about
 * themselves, never about the other person. Names, never blame; no emoji, no
 * countdowns, no guilt. Lines past the spec's are in the same voice for JD
 * to review.
 */

export type Answer = "play" | "later" | "no";
export type PounceTarget = { table: string } | "new" | "pick";

const DAY_MS = 24 * 60 * 60 * 1000;
/** A rotated line doesn't come back within 7 days while another one can go (§12.2). */
const NO_REPEAT_MS = 7 * DAY_MS;

export const days = (n: number): string => (n === 1 ? "1 day" : `${n} days`);

export function yourMoveBody(from: string | null, table: string, completesToday: boolean): string {
  const tail = completesToday ? "Your turn makes today count." : `Your move at ${table}.`;
  return from === null ? tail : `${from} played. ${tail}`;
}

/** A nudge: who asked, and the table. Gentle: no hurry, no count of how long it's been. */
export const nudgeBody = (from: string, table: string): string => `${from} nudged you. Your move at ${table}.`;

/** A day before a stalled seat can be retired: what happens, said plainly, with no blame. */
export const retireSoonBody = (table: string): string =>
  `Still your move at ${table}. From tomorrow the others can play on without you.`;
/** A stalled seat was retired: who did it, and that the game is over for you. */
export const retiredBody = (from: string, table: string): string =>
  `${from} played on without you at ${table}. Your seat there is retired.`;

export function pounceBody(from: string, target: PounceTarget): string {
  if (target === "new") return `${from} wants to play. New game?`;
  if (target === "pick") return `${from} wants to play. You pick.`;
  return `${from} wants to play. ${target.table}?`;
}

export function answeredBody(who: string, answer: Answer): string {
  if (answer === "play") return `${who} is coming.`;
  return answer === "later" ? `${who}: in a bit.` : `${who}: not now.`;
}

export const napBody = (count: number) => `A cat nap covered yesterday. ${days(count)} and counting.`;
export const winbackBody = (count: number) => `Two days in a row brings ${count} back.`;
export const pausedBody = (who: string, n: number) => `${who} put the cats to bed for ${days(n)}.`;
export const milestoneBody = (n: number) => `${n} days together. There's a gift on the rug.`;
export const playAgainBody = (who: string) => `${who} dealt a new game.`;
export const freshStartBody = (partner: string, month: boolean) =>
  `New ${month ? "month" : "week"}, new deal. One turn starts a streak with ${partner}.`;
/** The last reminder before going quiet (§12.3). */
export const GOING_QUIET = "The cats will keep your seat warm.";

/** What a rotated line may use: a table where it's your move, the partner, the streak count. */
export type LineCtx = { table: string | null; partner: string; count: number };
export type Line = { id: string; needs: ("table" | "count")[]; text: (c: LineCtx) => string };

export const DAILY_LINES: readonly Line[] = [
  { id: "d-rug", needs: ["table"], text: (c) => `The cats are on the rug. Your move at ${c.table}.` },
  { id: "d-grabs", needs: ["count"], text: (c) => `Day ${c.count + 1} is up for grabs. One turn with ${c.partner} keeps it.` },
  { id: "d-guard", needs: [], text: (c) => `${c.partner}'s cat is guarding the deck. Your move.` },
  { id: "d-couch", needs: [], text: (c) => `A turn with ${c.partner}, then the couch.` },
  { id: "d-shuffled", needs: ["table"], text: (c) => `The deck is shuffled and the cats are ready. Your move at ${c.table}.` },
  { id: "d-spot", needs: [], text: (c) => `${c.partner}'s cat saved you a spot on the rug.` },
  { id: "d-yarn", needs: ["table"], text: (c) => `The yarn is out at ${c.table}. Your move.` },
];

export const LAST_CHANCE_LINES: readonly Line[] = [
  { id: "l-keeps", needs: [], text: (c) => `One turn tonight keeps ${days(c.count)} going.` },
  { id: "l-bed", needs: [], text: () => "The cats want one more turn before bed." },
  { id: "l-curl", needs: ["table"], text: (c) => `One more turn at ${c.table} before the cats curl up.` },
  { id: "l-saved", needs: [], text: () => "The cats saved one turn for tonight." },
  { id: "l-lights", needs: [], text: (c) => `One turn with ${c.partner} tonight, then lights out.` },
  { id: "l-together", needs: [], text: (c) => `${days(c.count)} together so far. One turn tonight keeps them going.` },
  { id: "l-still-up", needs: ["table"], text: (c) => `The cats are still up at ${c.table}. One turn before bed?` },
];

const fits = (line: Line, c: LineCtx) =>
  line.needs.every((n) => (n === "table" ? c.table !== null : c.count >= 1));

/**
 * Round-robin from `cursor` (§12.3): the first line that fits and hasn't gone
 * out in 7 days, else the one that fits and went out longest ago.
 */
export function pickLine(
  lines: readonly Line[],
  c: LineCtx,
  used: Record<string, number>,
  cursor: number,
  now: number,
): { id: string; text: string; cursor: number } | null {
  const order = lines.map((_, k) => (cursor + k) % lines.length).filter((i) => fits(lines[i] as Line, c));
  const lastUsed = (i: number) => used[(lines[i] as Line).id] ?? -Infinity;
  const fresh = order.find((i) => now - lastUsed(i) >= NO_REPEAT_MS);
  const pick = fresh ?? [...order].sort((x, y) => lastUsed(x) - lastUsed(y))[0];
  if (pick === undefined) return null;
  const line = lines[pick] as Line;
  return { id: line.id, text: line.text(c), cursor: pick + 1 };
}
