# Daily Dish, G1: Nine Lives (the daily sudoku) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nine Lives, the Daily Dish's sudoku: the server makes one graded puzzle a day from a seed and
referees every move; the app (iPhone, iPad, TV watch) and the web player draw it on paw tiles.

**Architecture:**
- TS is the truth, in `apps/play-api/src/daily/nine-lives/`:
  - `grid.ts`: the visible rules (moves, clashes, full, progress). Light; the web player imports it.
  - `solve.ts`: a bitmask backtracking solver (count solutions, random full grid). Server only.
  - `grade.ts`: a logic solver that grades by the hardest technique it needs. Server only.
  - `make.ts`: the puzzle maker from an `Rng` and a `DayLevel`. Server only.
  - `module.ts`: `nineLives: DailyModule<NineLivesPuzzle, NineLivesState, NineLivesMove>`.
  - `vectors.ts`: builds the golden vectors; a test checks the committed files match.
- Swift has the visible rules only (`PounceKit/Daily/NineLives/NineLivesRules.swift`), checked
  against every vector. No maker, no grader, no solution on any client.
- Views draw from a small game model fed by a driver: a local driver now (phase A), the host's
  `DailyRunSession` / `RunSession` in phase B. Play and watch share one board drawing.

**Tech Stack:** TypeScript (vitest, v8 coverage), Swift 6 (PounceKit, SwiftUI), Preact (play-web).

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` (§1 Nine Lives, §2, §3, §7, §8,
§12). Map: `docs/superpowers/plans/2026-11-20-daily-games.md`. Contract: server plan Task 3 and 5.

## Global Constraints

- `DailyModule` exactly as server plan Task 3. Until S1 merges, `nine-lives/contract.ts` holds a
  verbatim copy of its types; after, imports switch to `../module` and `contract.ts` is deleted.
- The referee (S1 `run-core`) adds `HINT_PENALTY_MS * hints` to `timeMs` before `result()`; the
  module never adds it again.
- `publicPuzzle` and `publicState` never carry the solution.
- A clash is legal to enter. `apply` refuses only: a given or hinted cell, or any move after the
  grid is solved (`over`). The run ends `solved` when every cell equals the solution.
- Weekday levels: Mon 1 … Sat 6, Sun 7 (= tier 4 with fewer givens than Thursday).
- Level → (hardest tier, givens floor): 1 → (1, 34), 2 → (2, 30), 3 → (3, 28), 4 → (4, 27),
  5 → (5, 24), 6 → (6, 22), 7 → (4, 22) with Sunday's givens below Thursday's floor.
- Tiers: 1 singles (naked, hidden); 2 locked candidates (pointing, claiming); 3 naked and hidden
  pairs; 4 naked and hidden triples and quads; 5 X-wing, swordfish, XY-wing, XYZ-wing; 6 chains
  (simple coloring, XY-chain). Needs more than tier 6: rejected.
- Puzzles are 180° symmetric (cells removed in pairs `i`, `80 - i`).
- `floorMs` = { 1: 45 s, 2: 55 s, 3: 65 s, 4: 75 s, 5: 90 s, 6: 105 s, 7: 80 s }; `minMoveGapMs` = 100.
- `compare`: solved before unsolved; solved by `timeMs`, then fewer hints; unsolved by `progress`
  (higher first), then `timeMs`.
- `progress` = non-given cells filled / non-given cells. On the board: "cells placed".
- Coverage: 100% of `src/daily/nine-lives/**` (S1's `src/daily/**` threshold).
- Generation fits a Worker request: report ms per level (median and max over a year).
- No other sudoku app's look. Pounce palette (`Palette.swift`, `styles.css`), loud and cartoony,
  ink outlines; digits on paw tiles. Words: "Notes", "Erase", "Hint", "Not quite". No emoji.
- Main thread: clash checks are a fixed 81 × 20 scan (well under 1 ms; a test pins it) and stay on
  the main actor; nothing else heavy exists on clients. Network work arrives with the host (phase B).

## Review Focus

1. **A full grid with a mistake.** Says "Not quite" (full with a clash, which with one solution is
   exactly "full and wrong"), the run goes on, and erasing fixes it. Task 3 vector `full-wrong`.
2. **Overwriting and erasing a hinted cell.** Refused as illegal on server and client. Task 3 vector
   `hinted-locked`; Task 4 Swift parity.
3. **A hint when the grid is full but wrong.** It fixes one wrong cell (never "nothing to hint").
   Task 3 test `"hint on a full wrong grid fixes a wrong cell"`.
4. **A resumed run (another device).** `publicState` alone rebuilds the board, givens included via
   `publicPuzzle`; notes are lost by design. Task 3 test `"publicState plus publicPuzzle rebuild the
   board"`.
5. **The largest text size and iPhone SE.** The number row and grid fit at 320 pt-wide content;
   digits scale with the tile, not Dynamic Type. Task 5 render test on SE width at AX5.

---

### Task 1: Visible rules, solver and contract copy

**Files:** Create `nine-lives/contract.ts`, `grid.ts`, `solve.ts`; tests `grid.test.ts`, `solve.test.ts`.

**Interfaces (produces):**
```ts
export const N = 81;
export type Cells = number[];                      // 81 digits, 0 = empty
export type NineLivesMove = { k: "set"; i: number; d: number } | { k: "clear"; i: number };
export type NineLivesState = { cells: Cells; hinted: number[] };   // hinted ascending
export function peers(i: number): readonly number[];             // 20 peers
export function clashes(cells: Cells): number[];                 // ascending cell indices in a clash
export function isFull(cells: Cells): boolean;
export function placed(givens: Cells, cells: Cells): number;      // non-given cells filled
export function progressOf(givens: Cells, cells: Cells): number; // placed / empties, 0..1
export function parseMove(raw: unknown): NineLivesMove | null;
export function applyMove(givens: Cells, s: NineLivesState, m: NineLivesMove): NineLivesState | null; // null: illegal
export function applyReveal(s: NineLivesState, r: { i: number; d: number }): NineLivesState;
// solve.ts
export function countSolutions(cells: Cells, limit: number): number;
export function randomSolution(rng: Rng): Cells;
export function solveOne(cells: Cells): Cells | null;
```
- [ ] Tests: peers count 20 and symmetric; clashes on row, column and box, givens included; parseMove
  rejects extra keys, non-integers, `i` outside 0..80, `d` outside 1..9; applyMove refuses givens and
  hinted cells; countSolutions caps at `limit`; randomSolution is a valid grid and deterministic per
  seed. Run `pnpm --filter @pounce/play-api exec vitest run src/daily/nine-lives` (FAIL, then PASS).
- [ ] Commit `feat(nine-lives): visible rules and solver`.

### Task 2: Logic grader and puzzle maker

**Files:** Create `grade.ts`, `make.ts`; tests `grade.test.ts`, `make.test.ts`.

**Interfaces:**
```ts
export type Tier = 1 | 2 | 3 | 4 | 5 | 6;
export function grade(givens: Cells, maxTier?: Tier): { tier: Tier; solution: Cells } | null; // null: not solvable by logic ≤ maxTier
export const LEVELS: Record<DayLevel, { tier: Tier; floor: number }>;
export type NineLivesPuzzle = { givens: Cells; solution: Cells; tier: Tier };
export function makePuzzle(rng: Rng, level: DayLevel): NineLivesPuzzle;
```
- [ ] Tests: each technique on a hand-built candidate grid makes exactly the textbook eliminations
  (one test per technique); a known easy puzzle grades 1; a puzzle with two solutions grades null;
  `makePuzzle` is deterministic per seed; property test over a year of dates (2027-01-01 …
  2027-12-31, seed from the date): one solution by `countSolutions(…, 2) === 1`, `grade(givens).tier`
  equals `LEVELS[level].tier`, givens ≥ floor, 180° symmetric, Sunday's givens < Thursday's floor;
  logs median and max ms per level.
- [ ] Commit `feat(nine-lives): logic grader and puzzle maker`.

### Task 3: The module and golden vectors

**Files:** Create `module.ts`, `vectors.ts`, `module.test.ts`, `vectors.test.ts`;
`apps/play-api/fixtures/daily/nine-lives/rules.json` and `puzzles.json`.

- `module.ts` exports `nineLives` per Global Constraints. `hint` picks the empty cell with the fewest
  candidates (lowest index on ties); on a full wrong grid, the first wrong cell. `reveal` is `{ i, d }`.
- `rules.json`: `[{ name, givens, steps: [{ move | hint, ok, reason?, state, clashes, full, end, progress }] }]`.
- `puzzles.json`: `[{ seed, level, givens, tier }]`, one per level (pins the maker).
- `UPDATE_VECTORS=1 pnpm --filter @pounce/play-api exec vitest run src/daily/nine-lives/vectors.test.ts`
  writes them; without it the test compares.
- [ ] Tests: the contract tests (publicPuzzle keys only `givens`; solve ends `solved`; clash legal;
  over after solve; hint; compare; floorMs), and Review Focus 1–4.
- [ ] Commit `feat(nine-lives): daily module and golden vectors`.

### Task 4: Swift rules

**Files:** Create `PounceKit/Sources/PounceKit/Daily/NineLives/NineLivesRules.swift`;
`PounceKit/Tests/PounceKitTests/Daily/NineLives/NineLivesRulesTests.swift`.
- `public struct NineLivesBoard: Sendable, Equatable { givens: [UInt8]; cells: [UInt8]; hinted: Set<Int> }`
  with `apply(_ move: NineLivesMove) -> Bool`, `applyReveal(i:d:)`, `clashes: Set<Int>`, `isFull`,
  `looksSolved` (full, no clash), `progress`. Codable wire shapes for `{ givens }`, `{ cells, hinted }`
  and moves.
- [ ] Every step of every vector in `rules.json` matches (state, legality, clashes, full, end, progress).
  Run `swift test --package-path apps/play-ios/PounceKit --filter NineLives`.
- [ ] Commit `feat(nine-lives): Swift rules pass the vectors`.

### Task 5: iOS views

**Files:** `apps/play-ios/Pounce/Daily/NineLives/`: `NineLivesArt.swift` (paw tile shape, colors),
`NineLivesGrid.swift` (shared drawing, no UIKit: tvOS-ready), `NineLivesModel.swift` (`@MainActor
@Observable`: selection, notes, moves through a `NineLivesDriver`), `NineLivesPlayView.swift`,
`NineLivesWatchView.swift`, `NineLivesLocalDriver.swift` (phase A, DEBUG demo puzzle).
- [ ] Render checks (ImageRenderer) on SE, a large iPhone, iPad both ways and AX5; clash timing test.
- [ ] Commit `feat(nine-lives): iPhone and iPad play and watch views`.

### Task 6: Web views

**Files:** `apps/play-web/src/daily/nine-lives/`: `grid.tsx` (shared drawing), `play.tsx`, `watch.tsx`,
`model.ts`, `local.ts`, `nine-lives.css`; test `apps/play-web/tests/daily-nine-lives.test.ts`.
Imports only `@pounce/play-api/daily/nine-lives/grid` (never the maker or grader).
- [ ] Tests: model applies moves, notes, erase, Not quite; views render 81 cells and the pad.
- [ ] Commit `feat(nine-lives): web play and watch views`, then report phase A to the lead and wait.

### Phase B (after H1 and H2 merge; lead's message)

- Rebase on `origin/main`; switch `contract.ts` to `../module`; one line each in `src/daily/games.ts`,
  Swift `DailyCatalog`, the web registry.
- Drivers become the hosts' sessions; iPhone UI test and Playwright test play a puzzle to the end
  against `wrangler dev --port 8802` with `DAILY=on`; frame gates; screenshots per `AGENTS.md`.
- One PR, "Nine Lives: the daily sudoku".
