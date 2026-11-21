# Daily Dish, G2: Box Fort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Box Fort, the Daily Dish's block-placing puzzle: the server's rules, puzzle maker, scoring
and `DailyModule`; golden vectors; the same rules in Swift; and the play and watch views on iOS
and the web.

**Architecture:**
- One pure TS rules file (`rules.ts`) is the truth. The module, the vector builder and the web
  player all call it. The maker (`maker.ts`) is server only.
- Pieces travel with their cells (`{ id, tint, cells }`), so clients need no piece catalog and a
  new piece never needs an app update.
- Swift mirrors `rules.ts` only (no maker) and must pass every vector.
- Views draw from a plain state value. Phase A drives them from a local state; phase B swaps in
  the host's `DailyRunSession` / `RunSession`.

**Tech Stack:** TypeScript (Worker, vitest), Swift 6 (PounceKit, SwiftUI `Canvas`), Preact (web).

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` §1 "Box Fort", §2, §3, §7, §8,
§12. Map: `2026-11-20-daily-games.md`. Contract: `2026-11-20-daily-games-1-server.md` Task 3.

## Global Constraints

- Rules: 8 by 8 rug; pieces never rotate; three per set; full rows and columns clear at once; the
  run ends when nothing left in the current set fits, or when the last set is placed.
- The next set is dealt only after all three of the current set are placed. No future set is ever
  in `publicPuzzle`, `publicState` or an early `reveal`.
- Outcome is always `"done"`. No hints (`hint` returns `null`). Rank by points, then faster time.
- Original pieces, names, art, colors and sounds. Nothing from Block Blast. Loud, cartoony Pounce
  palette (`Palette.swift`), never beige or muted.
- Main thread: "does any piece fit" runs off the main actor in Swift (`@concurrent`). Drag holds
  120 Hz: per-frame work moves one layer, never redraws the rug.
- UI words: one to three per button, no emoji, no paragraphs.
- Owned files only: `apps/play-api/src/daily/box-fort/`, `apps/play-api/fixtures/daily/box-fort/`,
  `apps/play-api/scripts/box-fort-vectors.ts`, `PounceKit/Sources/PounceKit/Daily/BoxFort/`,
  `PounceKit/Tests/PounceKitTests/Daily/BoxFort/`, `Pounce/Daily/BoxFort/`,
  `apps/play-web/src/daily/box-fort/`, `apps/play-web/tests/daily-box-fort*.test.ts`, and in phase B
  one line per registry plus the game's UI and e2e tests.
- Dev server port 8803 only, `DAILY=on`. Own simulator, shut down after.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions (the builder's calls the spec leaves open)

**Scoring** (`rules.ts`, exported constants):
- `SQUARE_POINTS = 1` per square placed.
- `lineBonus(n) = 10 * n * (n + 1) / 2` for `n` lines cleared by one placement: 10, 30, 60, 100…
- Combo: `combo` counts consecutive clearing placements, this one included. A placement that clears
  nothing sets it to 0. `comboBonus(k) = 15 * (k - 1)` for `k ≥ 1`.
- `FULL_FORT = 200` when the last set's last piece is placed.

**Levels** (`maker.ts`, `LEVELS: Record<DayLevel, LevelSpec>`), weights are easy/medium/awkward:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 (Sun) |
|---|---|---|---|---|---|---|---|
| weights | 6/3/1 | 5/4/2 | 4/4/3 | 3/4/4 | 2/4/5 | 2/3/6 | 3/4/4 |
| max awkward per set | 1 | 1 | 1 | 2 | 2 | 3 | 2 |
| starting boxes | 0 | 4 | 6 | 8 | 10 | 12 | 8 |
| sets | 15 | 15 | 15 | 15 | 15 | 15 | 22 |

- Starting boxes: distinct random cells, tint `CLUTTER = 7`; no row or column over 5 boxes; every
  piece of the first set fits. Up to 50 tries, then one box fewer, until it holds.
- Piece tints: 1 to 6, drawn per piece.
- `floorMs = 20_000` every level (a full run at bot speed). `minMoveGapMs = 0` (a batch's moves arrive together, so any gap refuses its second move).

**Pieces** (`pieces.ts`): 40 shapes (10 easy, 16 medium, 14 awkward), cells as `[row, col]` from the top-left of the bounding box.
- Easy: `dot`, `duo-h`, `duo-v`, `trio-h`, `trio-v`, `sq2`, `nook-a..d` (three-cell corners).
- Medium: `quad-h`, `quad-v`, `rect-h` (2×3), `rect-v` (3×2), `ell-a..h` (four-cell L, all 8),
  `tee-up/down/left/right`.
- Awkward: `five-h`, `five-v`, `sq3`, `zig-h`, `zag-h`, `zig-v`, `zag-v`, `big-a..d` (five-cell
  3×3 corners), `plus`, `paws-a`, `paws-b` (two boxes touching at a corner: ours).

**Wire shapes:**
- `Piece = { id: string; tint: number; cells: [number, number][] }`
- Move: `{ k: "place", slot: 0 | 1 | 2, row: 0..7, col: 0..7 }`, exact keys.
- `publicPuzzle = { rug: number[64], sets: number, pieces: Piece[] }` (the first set only).
- `reveal = { set: number; pieces: Piece[] }`.
- `publicState = { rug, set, sets, pieces, placed: boolean[3], points, combo, lines, over }`, where
  `over` is `"full" | "stuck" | null`.
- `progress = (set + placedCount / 3) / sets`.

## Review Focus

1. **The set that completes is followed by one where nothing fits.** The run ends at once, and the
   reveal still goes out so the player sees why. (Task 3 test "a dealt set that can't fit ends the
   run, and is still revealed".)
2. **A placement that fills a row and a column at once.** The crossing cell clears once, both lines
   count. (Task 1 test "row and column clear together".)
3. **The last piece of the last set clears lines.** Line bonus, combo and full fort all add.
   (Vector `full-fort`.)
4. **A move for a slot already placed, or after the end.** Refused as illegal / over, state
   unchanged. (Task 3 tests.)
5. **The drag lands between cells or half off the rug.** The drop snaps to the nearest cell and is
   refused (piece returns to the tray) when any box would be off the rug or on a box. (Task 6
   layout test "snap rounds to nearest and refuses off-rug".)

---

### Task 1: Contract copy, pieces and rules (TS)

**Files:**
- Create: `apps/play-api/src/daily/box-fort/contract.ts` (a verbatim copy of the server plan's
  Task 3 types plus `Day`, `DayLevel`; replaced by `../module` and `../days` after S1 merges)
- Create: `apps/play-api/src/daily/box-fort/pieces.ts`, `rules.ts`
- Test: `pieces.test.ts`, `rules.test.ts` in the same folder

**Interfaces:**
- Produces (`pieces.ts`): `type Cell = [number, number]`, `type Shape = { id: string; tier: 0 | 1 | 2; cells: Cell[] }`, `SHAPES: readonly Shape[]`, `type Piece = { id: string; tint: number; cells: Cell[] }`.
- Produces (`rules.ts`): `SIZE = 8`, `CLUTTER = 7`, `SQUARE_POINTS`, `lineBonus(n)`, `comboBonus(k)`, `FULL_FORT`,
  `type BoxFortState`, `type Cleared = { rows: number[]; cols: number[] }`,
  `fits(rug, cells, row, col): boolean`, `anyFits(rug, pieces: Piece[]): boolean`,
  `place(rug, piece, row, col): { rug: number[]; cleared: Cleared } | null`,
  `start(rug, sets): BoxFortState`,
  `step(s, pieces, slot, row, col): { state; gained; cleared; setDone: boolean } | null`,
  `deal(s, next: Piece[] | null): BoxFortState` (adds `FULL_FORT` and `over: "full"` for null, else moves to the next set and sets `over: "stuck"` if nothing fits).

- [ ] Tests: every shape normalized (min row and col 0), unique ids, unique cell sets, 40 shapes, tiers as listed; `fits` refuses overlap and off-rug; "row and column clear together" (crossing cell once, `lineBonus(2)`); combo grows over consecutive clears and resets on a non-clear; `step` refuses a placed slot, a slot past 2, an overlapping spot; `step` sets `over: "stuck"` when none of the unplaced pieces fit; `deal(null)` adds 200.
- [ ] Run `pnpm --filter @pounce/play-api exec vitest run src/daily/box-fort`: FAIL, then implement, then PASS with 100% coverage of the folder.
- [ ] Commit `feat(box-fort): pieces and rules`.

### Task 2: The puzzle maker

**Files:** Create `maker.ts`; test `maker.test.ts`.

**Interfaces:**
- Consumes: `Rng` from `src/rules/rng.ts`, `DayLevel` from `contract.ts`.
- Produces: `type BoxFortPuzzle = { rug: number[]; sets: Piece[][] }`, `LEVELS`, `make(rng, level): BoxFortPuzzle`.

- [ ] Tests: "the same seed gives the same puzzle"; "a year of dates": for 2027-01-01..2027-12-31 (seed = first 16 bytes of sha256(date) as four uint32; level by weekday) the puzzle is deterministic, has the level's set count and box count (or fewer, never more), no full line, no row or column over 5 boxes, the first set fits piece by piece, at most the level's awkward pieces per set; "dates differ"; "the awkward share grows from Monday to Saturday" over the year.
- [ ] FAIL, implement, PASS, commit `feat(box-fort): puzzle maker`.

### Task 3: The `DailyModule`

**Files:** Create `module.ts`; test `module.test.ts`.

**Interfaces:**
- Produces: `export const boxFort: DailyModule<BoxFortPuzzle, BoxFortState, Place>`.

- [ ] Tests: `parseMove` exact shape (extra keys, wrong types, out of range, non-integers → null); `publicPuzzle` has only `rug`, `sets`, `pieces` and the pieces are `sets[0]`; "no future set ever leaks": play a whole puzzle greedily and assert after every apply that `publicState` and any `reveal` hold only the current set's pieces, and a reveal appears exactly when the third piece is placed; "a dealt set that can't fit ends the run, and is still revealed"; full fort ends with `end: "done"`; moves after the end answer `{ ok: false, reason: "over" }`; illegal moves answer `illegal`; `result` gives `points`, `hints: 0`, the outcome passed in; `compare` ranks points first, then time; `hint` is null.
- [ ] FAIL, implement, PASS, commit `feat(box-fort): daily module`.

### Task 4: Golden vectors

**Files:** Create `vectors.ts` (pure builder), `apps/play-api/scripts/box-fort-vectors.ts` (writes
the files), `vectors.test.ts`, `apps/play-api/fixtures/daily/box-fort/*.json`; add the package
script `vectors:box-fort` (esbuild bundle piped to node).

**Interfaces:**
- Produces files `placements.json`, `clears.json`, `combos.json`, `nothing-fits.json`, `full-fort.json`, `illegal.json`, `day-1.json`..`day-7.json` (a greedy run on a made puzzle of each level). Each is `{ name, start: publicPuzzle, steps: [{ move, ok, reveal, gained, cleared, end, state }] }`.

- [ ] Test: each file equals `buildVectors()` byte for byte (stale files fail, with the regenerate command in the message), and replaying through `boxFort` matches every step.
- [ ] Generate, PASS, commit `test(box-fort): golden vectors`.

### Task 5: Swift rules

**Files:** Create `PounceKit/Sources/PounceKit/Daily/BoxFort/BoxFortRules.swift`; test
`PounceKitTests/Daily/BoxFort/BoxFortVectorTests.swift`, `BoxFortRulesTests.swift`.

**Interfaces:**
- Produces: `BoxFortPiece` (Codable, Sendable), `BoxFortState` (Equatable, Sendable, Codable as `publicState`), `BoxFortCleared`, `BoxFortRules.fits`, `.anyFits`, `.step(_:slot:row:col:) -> BoxFortStep?`, `.deal(_:next:)`, and `@concurrent static func anyFitsOffMain(rug:pieces:) async -> Bool`.

- [ ] Vector test replays every file: illegal steps return nil and keep state; legal steps match `gained`, `cleared`, `end` and `state` exactly.
- [ ] `swift test --package-path apps/play-ios/PounceKit --filter BoxFort`: FAIL, implement, PASS. Commit `feat(box-fort): Swift rules pass the vectors`.

### Task 6: iOS views

**Files:** PounceKit `Daily/BoxFort/BoxFortLayout.swift` (geometry: rug rect, cell size, the snap,
the tray) and its test; app `Pounce/Daily/BoxFort/BoxFortArt.swift` (drawing a box, the rug, a
piece, shared by play and watch), `BoxFortPlayView.swift`, `BoxFortWatchView.swift`,
`BoxFortPlayModel.swift` (`@MainActor @Observable`, a local state in phase A).

- [ ] Layout tests: "snap rounds to nearest and refuses off-rug"; the rug is square and fits iPhone SE (320×568 points less bars) and iPad landscape; the lifted piece sits above the finger by a fixed offset.
- [ ] Views: the rug is a `Canvas` that redraws only on a state or ghost-cell change; the dragged piece is its own layer moved with `.offset` from `@GestureState`; the ghost and the lines that would clear light up; clears pop with a short spring; points count up. Watch view draws the same `BoxFortArt` from `publicState`, read only.
- [ ] Build the app for an iPhone simulator, look at it locally (uncommitted harness), commit `feat(box-fort): iPhone and iPad views`.

### Task 7: Web views

**Files:** `apps/play-web/src/daily/box-fort/model.ts` (local state over `rules.ts`), `rug.tsx`
(shared drawing), `play.tsx` (pointer drag, transform written on `requestAnimationFrame`, no Preact
render per move), `watch.tsx`, `box-fort.css`; test `apps/play-web/tests/daily-box-fort.test.ts`.

- [ ] Model tests: a placement updates points like the rules; a finished set waits for a reveal; snap math matches iOS's.
- [ ] Typecheck, lint, test PASS. Commit `feat(box-fort): web views`.

### Phase A end

- [ ] `pnpm check` green. Leave a hand-over note in the shared notes folder. Report to the lead and wait.

### Phase B (after the lead's message)

- Rebase on `origin/main`; `contract.ts` goes, imports become `../module` and `../days`.
- One line each: `src/daily/games.ts`, Swift `DailyCatalog`, the web registry.
- Plug the views into `DailyGameView` / `DailyGameScreen` and the watch views.
- iPhone UI test and web Playwright test playing a run to the end against port 8803, `DAILY=on`.
- Frame gates (the drag), screenshots per `AGENTS.md`, PR "Box Fort: the daily block puzzle".
