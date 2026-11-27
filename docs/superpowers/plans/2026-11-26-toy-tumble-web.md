# Toy Tumble web player and TV page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toy Tumble plays in the web player, on touch and keyboard, and the web TV page shows every box live. It is off in production until `GAMES` lists `tumble`.

**Architecture:**
- The web imports the TypeScript engine straight from `@pounce/play-api` (`src/tumble/*`, already a workspace dependency). So the web box is the server's own code.
- A `TumbleClient` store does three things:
  - runs the local box on the frame clock;
  - batches events to the socket;
  - replays every other box from the relayed stream.
- Canvas 2D draws boxes. Settled cells are cached per box on an offscreen canvas. Preact draws the chrome around them: tray, minis, standings.

**Tech Stack:** Preact, Vite, canvas 2D, vitest with happy-dom, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-26-toy-tumble-design.md`. The wire is `docs/live-protocol.md` (from the server plan, Task 4).

**Precedent:** the Birdwatch web PR, commit `4e8e6f20` (`git show --stat 4e8e6f20`). Follow its file layout, store wiring (`store/room.ts`, `store/lobby.ts`), catalog, lobby option pills, TV wiring (`ui/tv/*`), e2e helpers and screenshot script.

## Global Constraints

- The other games' names and the trade words for their pieces appear nowhere. Code says toy, box, row, junk and trick. A words test (server plan, Task 9) scans `apps/play-web/src/tumble`.
- UI words, exactly:
  - "Toy Tumble"
  - "Round 2"
  - "Out"
  - "Waiting for Sam"
  - "Play without Sam"
  - "Reconnecting"
  - "You win the round"
  - "Cats: Easy" and "Cats: Quick"
  - the trick names Hairball, Paw Swipe, Catnip, Scoop, Settle, Nap, Swap and Bath
  - the tips "Drag to move.", "Tap to turn.", "Flick down to drop.", "Tap a trick, then a box." and "Clear rows to block it."
- Sending: a batch at most every 50 ms while something changes, and at once on a set-down or a trick. `m` events are coalesced to the latest.
- Junk waits 2000 ms by the local clock from its `a` ack. It lands at the first set-down that clears nothing after that.
- Keys:
  - arrows move, repeating after 150 ms, then every 33 ms;
  - Down soft-drops;
  - Up or X turns clockwise, and Z counter-clockwise;
  - Space drops;
  - 1 to 6 use the first held trick on that seat.
- Gravity starts at 1000 ms per row and gets 15% faster every 30 s, never below 50 ms. From 2:30 it gets 30% faster every 15 s. Catnip ×4. The set-down wait is 500 ms, reset by a move up to 15 times.
- The main thread does UI only: input, the engine step (< 0.5 ms) and drawing. Socket decode stays where the web player's net layer already does it. The frame budget is 8.3 ms.
- Mute in tests: Playwright Chromium runs headless, or with `--mute-audio` when headed.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Tab hidden mid-round.** `requestAnimationFrame` stops. On return, the box must sync from the server, not replay a burst of frames. Pinned in Task 2.
2. **A sequence gap** (a missed relay). The client asks for a sync and never replays out of order. Pinned in Task 2.
3. **Keyboard focus.** Arrow keys and Space must not scroll the page or press a focused button while playing. Pinned in Task 4.
4. **Six players on a 375 px phone.** Five minis and the tray fit with no overlap. At a TV table they're chips. Pinned in Task 3.
5. **The TV page joining mid-round.** It draws every box from the sync at once. Pinned in Task 5.

---

### Task 1: The local box and the stream

**Files:**
- Create:
  - `apps/play-web/src/tumble/local.ts`: the frame-clock driver of one's own box: gravity, the set-down wait, moves, turns, drops, junk waits, and the events out.
  - `apps/play-web/src/tumble/replay.ts`: other boxes from relays, hits, acks and syncs.
  - `tests/tumble-local.test.ts` and `tests/tumble-replay.test.ts`.

**Interfaces:**
- Produces:
  - `class LocalBox { constructor(o: { r, seat, roundSeed, trickSeed, startsAt, send: (ev: ClientEvent) => void }); step(now: number): void; move(dx: -1|1): void; turn(dir: 1|-1): void; soft(on: boolean): void; drop(): void; use(slot: number, seat: number): void; hit(h: HitWire): void; sync(b: BoxSync): void; view(): { box: Box; toy: { id, rot, x, y } | null; landing: number; waiting: { rows, leftMs }[] } }`
  - `class Replay { apply(msg: TumbleRelay | HitWire | TumbleSync | TumbleSeat): void; box(seat): Box; toy(seat): { id, rot, x, y, at } | null; needsSync(): boolean }`
- `local.ts` sends with a `Batcher` (50 ms, flush on `l` and `u`).

- [ ] **Step 1: Write the failing tests.**
  - With a fake clock, a toy falls one row per 1000 ms. Move, turn and drop are applied at once, and `send` gets `["m",…]` coalesced, then `["l",…]` on the drop.
  - A `junk` hit sends `["a",id]` at once. It lands at the first non-clearing set-down at or after 2000 ms, not before, and is listed in `landed`.
  - Replay of the server fixtures' streams gives the same boxes as the engine.
  - A `q` gap sets `needsSync()`.
  - Hits are applied when the target's `a` arrives.
- [ ] **Step 2: Run, expect FAIL.** Run `pnpm --filter @pounce/play-web exec vitest run tests/tumble-local.test.ts tests/tumble-replay.test.ts`.
- [ ] **Step 3: Implement.** On `visibilitychange` to hidden, mark the box stale. On return, ask the room for a sync (any `tumble` batch triggers one; send an empty `ev` batch) before stepping (Review Focus 1).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 2: Store and socket wiring

**Files:**
- Modify: `apps/play-web/src/store/room.ts` (route `tumble`, `tumbleHit`, `tumbleSync` and `tumbleSeat` to the Toy Tumble store), `store/lobby.ts` (the `cats` option), `src/lib/catalog.ts` (the Toy Tumble entry, 2 to 6 players), `src/lib/env.ts` (list `tumble` in `games`)
- Create: `apps/play-web/src/tumble/store.ts`, `tests/tumble-store.test.ts`

- [ ] **Step 1: Write the failing tests**, following `tests/bw-store.test.ts`:
  - The snapshot's `status:"countdown"` with `startsAt` creates the `LocalBox` for the device's seat and a `Replay` for the others.
  - A gap or a hidden tab gives a sync request (Review Focus 1 and 2).
  - Round end clears the boxes.
  - Away and left seats show their state.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 3: The player screen

**Files:**
- Create:
  - `apps/play-web/src/tumble/canvas.ts`: draws a box at any cell size, with cushions, silhouettes, hairball rows, trick badges, the paw-print landing outline and the cat on the rim with the next toy. Settled cells are cached on an offscreen canvas.
  - `tumble/screen.tsx`: the layout of spec §5.2, with the countdown, round over and watching.
  - `tumble/layout.ts`: sizes from the viewport.
  - `tumble/tumble.css`
  - `tests/tumble-layout.test.ts`
- Art: the cushion, silhouette and hairball sprites under `src/art/`, through `scripts/build-art.mjs`, matching the iOS art manifest (the iOS plan, Task 4, owns the art; until it lands, draw the cushions procedurally with the same colors).

- [ ] **Step 1: Write the failing tests** in `tumble-layout.test.ts`.
  - For 375×667, 390×844, 768×1024, 1024×768 and 1440×900, at 2 and 6 players:
    - cells ≥ 20 px on phones;
    - no rect overlaps another;
    - everything inside the safe viewport.
  - At a TV table, the minis become chips (Review Focus 4).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the screen and canvas, with the hit animation, out (the box tips) and round over (confetti, paw tokens).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 4: Touch and keyboard

**Files:**
- Create: `apps/play-web/src/tumble/input.ts`, `tests/tumble-input.test.ts`

- [ ] **Step 1: Write the failing tests** with synthetic pointer events.
  - A horizontal drag of 3 cell-widths gives 3 moves.
  - A tap turns.
  - A slow downward drag soft-drops while held.
  - A fast downward flick drops.
  - Tapping a trick, then a mini, sends `u`. So does dragging a trick onto a box.
  - Every key in Global Constraints, with repeat timing.
  - Arrow and Space keys call `preventDefault` while playing (Review Focus 3).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** with pointer events on the canvas. Handle input at the event, not in rAF. Use `touch-action: none` on the play area.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 5: The TV page

**Files:**
- Create: `apps/play-web/src/tumble/tv.tsx`
- Modify: `src/ui/tv/tv-table.tsx`, `tv-model.ts`, `tv-lobby.tsx`, `tv-board.css`

- [ ] **Step 1: Write the failing test** (happy-dom). A screen snapshot plus a `tumbleSync` of 6 boxes draws 6 boxes in one row, with name, wins, held tricks and the junk meter (Review Focus 5).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** spec §5.6.
  - Boxes are sized to fill the screen.
  - Falling toys glide: interpolate y by the box's gravity between `m` updates.
  - Hits fly from thrower to target.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 6: Lobby, tips, How to play, e2e and frame gates

**Files:**
- Modify: `src/ui/lobby.tsx` (the Cats pills, one seat per device, "Waiting for Sam"), the web player's tips and How to play (the Toy Tumble page with the tricks table), `e2e/main-thread.spec.ts`
- Create: `e2e/tumble.spec.ts`, `e2e/tumble-tv.spec.ts`, `scripts/tumble-shots.mjs`

- [ ] **Step 1: Write the e2e specs** against the local Worker the web e2e already starts (with `GAMES` including `tumble` in its dev vars, never 8787 or 4343).
  - Two browser players and one House Cat play a round to the end.
  - Keyboard play works.
  - The TV page shows 3 boxes live.
  - A TV page opened mid-round draws all boxes.
  - A player reloading mid-round is back within 15 s.
- [ ] **Step 2: Add the main-thread gate cases.** 60 s of scripted keyboard play against 5 House Cats, with hits, and a TV page with 6 boxes for 60 s. No long task, and no frame over 16.7 ms.
- [ ] **Step 3: Run.** Run `pnpm --filter @pounce/play-web e2e -- tumble main-thread`, expecting PASS.
- [ ] **Step 4: Take screenshots** with `scripts/tumble-shots.mjs`: lobby, play, round over, watching and the TV, at phone, tablet and desktop, for the PR.
- [ ] **Step 5: Commit, push and open the PR "Toy Tumble plays in the web browser and on the TV page (still off)"**, with before and after screenshots of the lobby and shelf.
