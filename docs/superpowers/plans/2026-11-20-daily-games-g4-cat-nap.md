# Daily Dish, G4: Cat Nap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cat Nap, the Daily Dish's animal placement puzzle: server rules, a seeded puzzle maker with a logic grader, the `DailyModule`, golden vectors, Swift rules that pass them, and the iPhone, iPad, web and TV-watch views.

**Architecture:**
- **TS is the truth** (`apps/play-api/src/daily/cat-nap/`):
  - `rules.ts`: the board, marks, moves, clashes, hints. Pure, small, imported by the web player.
  - `logic.ts`: the logic solver and grader. Server only (the web player never imports it).
  - `maker.ts`: solution, patches, keep only puzzles the grader solves at the day's grade.
  - `module.ts`: the `DailyModule` for `cat-nap`.
- **Swift** (`PounceKit/Daily/CatNap/`) has the rules only, checked against the TS vectors.
- **Views** draw one board from `(puzzle, state)`; play adds input, watch adds nothing. iOS is SwiftUI `Canvas`; web is SVG in Preact.

**Tech Stack:** TypeScript and vitest (play-api), Swift 6 and Swift Testing/XCTest (PounceKit), SwiftUI, Preact and Playwright (play-web).

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` §1 "Cat Nap", §2, §7, §8, §12. Map: `2026-11-20-daily-games.md`. Contract: `2026-11-20-daily-games-1-server.md` Task 3.

## Global Constraints

- The rule set: an N by N quilt with N patches; one cat in every row, every column and every patch; no two cats touch, diagonals included; exactly one solution, reachable by logic.
- Sizes by `DayLevel`: 1 → 5, 2 → 6, 3 → 7, 4 → 7, 5 → 8, 6 → 8, 7 (Sunday) → 9.
- Deeper logic later in the week: the grade bands in Task 3 (tunable from measurement, never inverted).
- `publicPuzzle` is `{ n, patches }` only, never the solution or the grade.
- No route or move carries a score, time or "solved". The module ends a run `solved` only when the cats are exactly the solution.
- A hint places one cat from the solution and the server adds 30 s (run-core). The board never says "wrong" except through a hint.
- Generation fits a Worker request: measured per size, reported.
- Swift has no puzzle maker and no solver. Drag marking over 9 by 9 runs its rule checks off the main actor.
- Original names and art only: no Zoodoku or LinkedIn Queens names, art, colors or layout. Colors never carry meaning alone: thick patch borders and a pattern per patch.
- UI copy: one to three words on buttons, no emoji; teach with tips (phase B, with the host).
- Own only G4's files (map plan). Until S1 merges, the contract types live in `cat-nap/contract.ts`, an exact copy of Task 3; after, it is deleted and imports switch to `../module` and `../days`.
- Coverage: `src/daily/cat-nap/**` at 100%.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A drag that crosses a hinted cat or a cat.** The client leaves hinted cells out of a drag; the server refuses any move that touches a hinted cell. Pinned by vectors `drag-skips-hinted` and `hinted-is-locked`.
2. **A full board of cats that breaks a rule** (n cats, a pair touching). Not solved, the clash shows, play goes on. Vector `full-but-touching`.
3. **A hint when every solution cat is placed but a wrong extra cat is too.** The hint locks the solution cat in that row and clears the cats that clash with it, so a hint always makes progress. Test `hint clears the cats that clash with it`.
4. **Generation that never finds a puzzle for some seed.** `make` has a bounded number of tries, then falls back to the best puzzle that is unique by logic at any grade, never throws, never loops. Test `make always returns a unique puzzle, even when the band is impossible`.
5. **Resuming a run** from `publicState` on another device: the board, the hinted locks and the clashes come back exactly. Test `publicState round-trips into the client rules`.

---

### Task 1: Contract copy and the rules

**Files:**
- Create: `apps/play-api/src/daily/cat-nap/contract.ts` (Task 3's types verbatim, plus `type Day = string` and `type DayLevel = 1|2|3|4|5|6|7`)
- Create: `apps/play-api/src/daily/cat-nap/rules.ts`
- Test: `apps/play-api/src/daily/cat-nap/rules.test.ts`

**Interfaces (Produces):**

```ts
export type Mark = 0 | 1 | 2;                     // empty, "no cat", cat
export type Quilt = { n: number; patches: number[] };   // row-major, patch id 0..n-1 per cell
export type NapState = { cells: Mark[]; hinted: number[] }; // hinted: locked cat cells, ascending
export type NapMove = { k: "mark"; cells: number[]; to: "x" | "cat" | "clear" };
export type Clashes = { rows: number[]; cols: number[]; patches: number[]; touching: number[]; cells: number[] };
export function emptyState(q: Quilt): NapState;
export function parseNapMove(raw: unknown): NapMove | null;
export function applyMark(q: Quilt, s: NapState, m: NapMove): NapState | null; // null: illegal
export function clashes(q: Quilt, s: NapState): Clashes;
export function complete(q: Quilt, s: NapState): boolean;   // n cats and no clash
export function hintTarget(q: Quilt, s: NapState, solution: number[]): number | null; // cell, or null when solved
export function applyHint(q: Quilt, s: NapState, cell: number): NapState;
export function catsPlaced(q: Quilt, s: NapState): number;  // cats not in any clash, capped at n
export function tapMove(s: NapState, cell: number): NapMove | null;   // empty → x → cat → empty; null on a hinted cell
export function dragPaint(s: NapState, start: number): "x" | "clear" | null; // empty start paints x, x start clears, else null
export function dragMove(s: NapState, paint: "x" | "clear", cells: number[]): NapMove | null; // the cells the paint changes, in order, hinted and cats skipped
```

- `parseNapMove`: exactly the keys `k`, `cells`, `to`; `cells` 1..81 distinct non-negative integers; `to: "cat"` needs exactly one cell. Anything else is null.
- `applyMark`: illegal when a cell is `>= n*n` or is hinted. Otherwise each cell becomes 1 (`x`), 2 (`cat`) or 0 (`clear`).
- `clashes`: rows, columns and patches holding 2+ cats; `touching`: cats with a cat among their 8 neighbours; `cells`: every cat in any of those, ascending.
- `hintTarget`: the first row r (top down) whose solution cell is not a cat, or is a cat that clashes with another cat. `applyHint`: that cell becomes a hinted cat, and every cat that clashes with it (same row, column, patch, or touching), unless hinted, is cleared.

- [ ] **Step 1: Write failing tests**: `parseNapMove takes only the exact shape` (extra key, float, duplicate, 82 cells, cat with two cells: null); `marks set, overwrite and clear`; `a hinted cell is locked`; `out of range is illegal`; `two cats in a row, column, patch clash`; `touching includes diagonals`; `complete needs n cats and no clash`; `hint clears the cats that clash with it`; `hint is null once solved`; `catsPlaced ignores clashing cats`; `tap cycles empty, x, cat, empty`; `a drag from empty paints x over empties only`; `a drag from x clears x only`; `a drag skips hinted cells and cats`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/cat-nap`. Expected: FAIL.
- [ ] **Step 3: Implement** `contract.ts` and `rules.ts`.
- [ ] **Step 4: Run the same.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(cat-nap): rules`.

### Task 2: The logic solver and grader

**Files:**
- Create: `apps/play-api/src/daily/cat-nap/logic.ts`
- Test: `apps/play-api/src/daily/cat-nap/logic.test.ts`

**Interfaces (Produces):**

```ts
export type Grade = 1 | 2 | 3 | 4;
export function countSolutions(q: Quilt, limit: number): number;     // backtracking, stops at limit
export function grade(q: Quilt): { grade: Grade; solution: number[] } | null; // null: logic can't finish
```

Techniques, each tried only when every lower one is stuck; the grade is the highest used:
1. **Singles:** a row, column or patch with one candidate gets its cat; a cat removes its row, column, patch and neighbours.
2. **Confinement:** a unit's candidates all in one row, column or patch clear the rest of that line or patch; a cell that would remove every candidate of some unit is cleared.
3. **Groups:** k patches (2 ≤ k < n) whose candidates lie within k rows (or columns) clear those rows (columns) outside them; and k rows (columns) within k patches clear those patches outside them.
4. **Trial:** a cat at a candidate that leads, by grades 1 to 3, to a unit with no candidate is cleared.

`solution[r]` is the column of row r's cat.

- [ ] **Step 1: Write failing tests**: `countSolutions finds 1 for a hand-made unique 5x5 and 2+ for an ambiguous one`; `grade 1 for a singles puzzle`; `grade needs confinement` and `grade needs groups` and `grade needs trial` on hand-made quilts found by a search script and pinned; `grade is null when two solutions`; `every grade's solution passes complete`.
- [ ] **Step 2: Run** the folder. Expected: FAIL.
- [ ] **Step 3: Implement** `logic.ts` with candidate bitsets (`Uint8Array` of n*n).
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(cat-nap): logic grader`.

### Task 3: The puzzle maker

**Files:**
- Create: `apps/play-api/src/daily/cat-nap/maker.ts`
- Test: `apps/play-api/src/daily/cat-nap/maker.test.ts`, `apps/play-api/src/daily/cat-nap/year.test.ts`

**Interfaces (Produces):**

```ts
export type NapPuzzle = Quilt & { solution: number[]; level: DayLevel; grade: Grade };
export const SIZES: Record<DayLevel, number>;          // { 1: 5, 2: 6, 3: 7, 4: 7, 5: 8, 6: 8, 7: 9 }
export const GRADES: Record<DayLevel, [Grade, Grade]>; // the accepted band, min and max
export function makeNap(rng: Rng, level: DayLevel): NapPuzzle;
```

- The solution: a column per row, no two in neighbouring rows within one column of each other, by shuffled backtracking.
- Patches: seeded at the solution's cats, grown one random frontier cell (4-connected) at a time until the quilt is full. Contiguous by construction.
- Keep a quilt when `grade` is non-null and inside the band. Bounded tries; past them, the first logic-unique quilt seen at any grade (Review Focus 4).
- Starting bands (tuned by measurement in Step 4, keeping min non-decreasing Mon to Sat): 1 → [1,2], 2 → [2,2], 3 → [2,3], 4 → [3,3], 5 → [3,4], 6 → [4,4], 7 → [3,3].

- [ ] **Step 1: Write failing tests**: `makeNap is deterministic for a seed`; `sizes follow the level`; `patches are contiguous and each holds one solution cat`; `make always returns a unique puzzle, even when the band is impossible` (GRADES overridden through a test-only parameter); `year.test.ts`: 365 dates from 2027-01-04, seeds from `createRng` over a fixed word mix of the date, each `countSolutions === 1`, contiguous, grade in band, and a printed table of ms per size (mean and max).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `maker.ts`.
- [ ] **Step 4: Run, read the timing table, tune bands or tries** so the worst case stays under 1 s of CPU and the mean under 100 ms on a laptop. Expected: PASS.
- [ ] **Step 5: Commit** `feat(cat-nap): puzzle maker`.

### Task 4: The module

**Files:**
- Create: `apps/play-api/src/daily/cat-nap/module.ts`
- Test: `apps/play-api/src/daily/cat-nap/module.test.ts`

**Interfaces:** Consumes Tasks 1 to 3. Produces `export const catNap: DailyModule<NapPuzzle, NapState, NapMove>` with:
- `id: "cat-nap"`, `make: makeNap`, `publicPuzzle: (p) => ({ n, patches })`, `init: emptyState`, `parseMove: parseNapMove`.
- `apply`: illegal → `{ ok: false, reason: "illegal" }`; else the new state, with `end: "solved"` when the cats are exactly `solution`.
- `hint`: `hintTarget`; null target → `{ ok: false, reason: "over" }`; else `applyHint`, `reveal: { cell }`, and `end: "solved"` when that finishes it.
- `progress`: `catsPlaced / n`. `publicState`: the state. `result`: `{ outcome, timeMs, hints, progress }`.
- `compare`: solved before unsolved; solved by `timeMs`; unsolved by `progress` (higher first), then `timeMs`.
- `floorMs`: { 1: 6000, 2: 9000, 3: 12000, 4: 12000, 5: 16000, 6: 16000, 7: 20000 }. `minMoveGapMs: 0` (a batch's moves share one arrival time; the floor guards speed).

- [ ] **Step 1: Write failing tests**: `publicPuzzle carries only n and patches`; `solving by marks ends solved`; `a valid-looking full board that is not the solution never happens` (all 365 puzzles: `complete` implies solution); `hint reveals one cell and can finish`; `compare ranks solved by time, then unsolved by progress`; `publicState round-trips into the client rules`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run with coverage** `pnpm --filter @pounce/play-api exec vitest run --coverage src/daily/cat-nap`. Expected: PASS, 100% for the folder.
- [ ] **Step 5: Commit** `feat(cat-nap): daily module`.

### Task 5: Golden vectors

**Files:**
- Create: `apps/play-api/scripts/cat-nap-vectors.ts` (writes), `apps/play-api/src/daily/cat-nap/vectors.ts` (builds them), `apps/play-api/fixtures/daily/cat-nap/vectors.json`
- Test: `apps/play-api/src/daily/cat-nap/vectors.test.ts` (rebuilds and compares to the file)

**Format:** an array of `{ name, quilt: Quilt, start: NapState, steps: Step[] }`, where a step is `{ move: unknown }`, `{ hint: number }`, `{ tap: number }` or `{ drag: number[] }` (the client helpers make the move, which the step also records as `made`), and carries `{ ok: boolean, state: NapState, clashes: Clashes, complete: boolean, placed: number }` after it.

Vectors: `tap-cycle`, `drag-x`, `drag-clear`, `row-clash`, `column-clash`, `patch-clash`, `touching-diagonal`, `touching-side`, `full-but-touching`, `finish-5x5`, `finish-9x9`, `hint-locks`, `hint-clears-clashes`, `hinted-is-locked`, `drag-skips-hinted`, `bad-shapes` (each malformed move `ok: false`, state unchanged).

- [ ] **Step 1: Write the test** that rebuilds the vectors and deep-equals the file. Run: FAIL (no file).
- [ ] **Step 2: Implement** `vectors.ts` and the script; run `pnpm --filter @pounce/play-api exec tsx scripts/cat-nap-vectors.ts` (or `node --experimental-strip-types`). Run the test: PASS.
- [ ] **Step 3: Commit** `test(cat-nap): golden vectors`.

### Task 6: Swift rules

**Files:**
- Create: `apps/play-ios/PounceKit/Sources/PounceKit/Daily/CatNap/CatNapRules.swift`
- Test: `apps/play-ios/PounceKit/Tests/PounceKitTests/CatNapRulesTests.swift`

**Interfaces (Produces):** `public struct NapQuilt: Codable, Sendable, Equatable { n; patches }`, `public struct NapState: Codable, Sendable, Equatable { cells: [UInt8]; hinted: [Int] }`, `public enum NapTo: String { x, cat, clear }`, `public struct NapMove: Codable, Sendable, Equatable { cells: [Int]; to: NapTo }` (encodes `k: "mark"`; `init?(json: Any)` mirrors `parseNapMove`), `public struct NapClashes: Equatable, Sendable { rows, cols, patches, touching, cells }`, and `public enum CatNapRules` with `apply`, `clashes`, `complete`, `applyHint`, `placed`, `tapMove`, `dragPaint`, `dragMove`, plus `@concurrent public static func check(_:_:) async -> NapClashes` for the views.

- [ ] **Step 1: Write the test** that reads `fixtures/daily/cat-nap/vectors.json` (by path, like `Fixtures.url`) and checks every step's `ok`, state, clashes, `complete` and `placed`. Run `swift test --filter CatNapRules` in `PounceKit`: FAIL.
- [ ] **Step 2: Implement.** Run: PASS.
- [ ] **Step 3: Commit** `feat(cat-nap): Swift rules`.

### Task 7: The iOS views on a local state

**Files (all under `apps/play-ios/Pounce/Daily/CatNap/`):**
- `CatNapModel.swift`: `@MainActor @Observable final class CatNapModel` with `quilt`, `state`, `clashes`, `tap(_ cell:)`, `drag(began:)`, `drag(over:)`, `dragEnded()`, `onMove: (NapMove) -> Void`, and `receive(state:)` (server truth). Marks show at once; `clashes` comes from `CatNapRules.check` off the main actor, a stale result dropped.
- `CatNapQuilt.swift`: the shared drawing: patch fills from an own palette of nine loud colors, a pattern per patch (stripes, dots, checks, zigzags, plaid, waves, stars, crosshatch, stitches), thick dark seams between patches, `catN-asleep` art for cats, a paw-print stamp for "no cat", a red-orange pulsing ring and a jagged edge on clashing cats and lines.
- `CatNapPlayView.swift`: the quilt sized to fit (square, safe areas), one gesture for tap and drag; accessibility: each cell a button labelled "Row 3, column 4, blue stripes, cat".
- `CatNapWatchView.swift`: the quilt from `(quilt, state)`, no input (for tvOS).
- `CatNapPreview.swift` (DEBUG): a local puzzle and state for `#Preview` until the host exists.

- [ ] **Step 1: The model's pure parts** are `CatNapRules.tapMove`, `dragPaint` and `dragMove` (Task 6, mirroring Task 1 and pinned by vectors `tap-cycle`, `drag-x`, `drag-clear`, `drag-skips-hinted`), so the app model holds no rule of its own.
- [ ] **Step 2: Implement the views; build** with `xcodebuild -scheme Pounce -destination 'platform=iOS Simulator,name=<own sim>' build`. Expected: success, and `swift scripts/main-thread-lint.swift` passes.
- [ ] **Step 3: Commit** `feat(cat-nap): iOS quilt, play and watch views`.

### Task 8: The web views on a local state

**Files (all under `apps/play-web/src/daily/cat-nap/`):**
- `quilt.tsx`: the shared SVG drawing (same palette and patterns, own CSS in `cat-nap.css`).
- `play.tsx`: `CatNapPlay({ quilt, state, onMove })` with pointer events for tap and drag (one pointer, captured), local marks at once, clashes from `rules.ts` (a 9 by 9 check is microseconds, well under a frame; measured in the test).
- `watch.tsx`: `CatNapWatch({ quilt, state })`.
- `model.ts`: the tap cycle and drag paint, from `rules.ts`.
- Test: `apps/play-web/tests/cat-nap.test.ts` (model, and a happy-dom render of play and watch).

- [ ] **Step 1: Write failing tests**: `tap cycles empty, x, cat, empty`; `a drag paints x over empties only`; `watch renders a cat per cat cell and no handlers`; `clashes over 9x9 take under 1 ms` (1000 runs).
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-web exec vitest run tests/cat-nap.test.ts`: FAIL.
- [ ] **Step 3: Implement.** Run: PASS; `pnpm --filter @pounce/play-web typecheck` and `pnpm lint` pass.
- [ ] **Step 4: Commit** `feat(cat-nap): web quilt, play and watch views`.

### Phase A ends here: report to the lead, then wait.

### Task 9 (phase B): Plug in and ship

After the lead says H1 and H2 merged:
- Rebase on `origin/main`; delete `contract.ts`, import `../module` and `../days`; add `"cat-nap": catNap` to `src/daily/games.ts`, Cat Nap to `DailyCatalog` and the web registry.
- Wrap the views in the hosts' `DailyGameView` / `DailyGameScreen` and `DailyWatchView`, moves through `DailyRunSession.send(move:)` / `RunSession`.
- Coach marks through the tip system: "Tap twice for a cat", "Drag to mark", once each.
- An iPhone UI test and a web Playwright test that solve today's puzzle against `wrangler dev --port 8805` with `DAILY=on` (the test reads the solution through a test hook the host provides, or solves with the hint button).
- Frame gates on the puzzle screen; screenshots on iPhone SE, a large iPhone, iPad both ways, the largest text size, and 1080p watch.
- One PR, "Cat Nap: the daily cat puzzle".
