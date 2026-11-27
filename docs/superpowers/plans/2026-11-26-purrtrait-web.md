# Purrtrait in the web player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Purrtrait plays in the web player (`apps/play-web`): the browser TV page is the easel, a browser phone draws or guesses, against the server plan's wire.

**Architecture:** One pure ink core shared by drawing and showing (`table/purr-ink.ts`: point filtering, simplification, op encoding and decoding, `compact`), a canvas renderer (`table/purr-easel.ts`: a bitmap canvas for finished strokes plus a live layer for the stroke in progress, drawn once per animation frame), and three surfaces: the TV easel (`ui/tv/purr-tv.tsx`), the drawer's phone (`table/purr-draw.tsx`) and the guesser's phone (`table/purr-watch.tsx`). The server says what is legal and holds the word; the browser never picks words.

**Tech Stack:** Preact, TypeScript, 2D canvas, a Web Worker for ink encoding and `inkSync` replay, Vitest + happy-dom, Playwright against `wrangler dev`.

**Spec:** `docs/superpowers/specs/2026-11-26-purrtrait-design.md` (§4, §5, §6, §7, §11). Wire: `docs/superpowers/plans/2026-11-26-purrtrait-server.md` "Wire contract", then the server session's `purrtrait-server-wire.md` and `apps/play-api/fixtures/protocol/purrtrait-*.json` once it lands.

## Global Constraints

- The main thread draws only (`docs/main-thread.md`, `eslint.main-thread.mjs`): ink encoding, decoding and `inkSync` rasterising run in a worker (`src/workers/`); the page appends points and draws.
- 120 fps on a ProMotion phone while drawing, 60 on the TV page; per-frame main-thread work p95 under 8.3 ms.
- The drawer's own lines draw on the frame they happen, never waiting for the server.
- Easel 3:4, grid 768 × 1024, colours 0-7 plus 8 (white eraser), widths 0-2 = 4, 10, 24 grid units. Points under 2 units from the last kept are dropped; RDP tolerance 1 unit; a batch every 50 ms and at stroke end; at most 25 messages a second.
- No drawing on a guesser's phone, ever. No word anywhere but the drawer's phone until the reveal. No save, share or download of a drawing.
- Copy: one to three words per button, no emoji, never the commercial game's name or category words. Strings fixed by the spec: "Starts on the TV", "Scan to join", "Scan the code on the TV.", "Look at the TV", "You draw next", "Waiting for the TV", "Easel full", "Got it", "Give up", "Undo", "Clear", tips "Pick one to draw", "No letters or numbers", "Tap who said it first", "Guess out loud".
- Local server on port 8797 with `GAMES=tiles,birdwatch,purrtrait`; never 8787 or 4343. Browsers muted.
- Stay out of `apps/play-ios`. Touch `apps/play-api` only for the `/play/e/` route if the server session hasn't, and say so.

## Rulings

Recorded by the web session as it built (branch `claude/purrtrait-web`).

1. **The typed code.** Room codes are 5 characters (`ROOM_CODE`); the server's TV code is the room code and the key's first 3 letters, 8 in all, shown as the server gives it with a space after the room code: `BCDFG KQ2`. "Join with code" takes 5 or 8 (`typedCode` in `lib/router.ts`); 8 go to the socket as `near=`.
2. **Palette and line shape** are the iOS session's exact values (`COLOURS` in `purr-ink.ts`): #1A1426, #FF3B4A, #FF9419, #FFD400, #2ECC5B, #2F80FF, #9B4DFF, #8B5A2B, white #FFFFFF as the eraser on #FFFFFF paper. A line is moveTo the first point, lineTo the first midpoint, a quadratic through each midpoint with the point between as control, lineTo the last point; one point is a dot of the width.
3. **What runs where.** A 50 ms batch is tens of points: filtering, RDP and encoding it, and decoding a relayed batch, stay on the page (always far under 1 ms, which `docs/main-thread.md` allows). Whole drawings go to `workers/purr-ink.worker.ts`: an `inkSync` decoded there, and the bitmap layer rastered there on an OffscreenCanvas after an undo, a resize or a sync, handed back as an ImageBitmap. A browser with no OffscreenCanvas draws it on the page.
4. **Late screens still get the ink.** A TV that reloads gets its snapshot and `inkSync` before its easel mounts, so the room store keeps the current turn's ink messages in memory (`inkLog`) and replays them to a listener that subscribes later. Dropped when a snapshot shows another turn.
5. **Pacing.** The writer sends at most 22 messages a second (the server takes 25), for jitter. A `["c"]` always starts a message of its own. After `easel_full`, Clear drops what waits and sends `["c"]` alone, at once. Offline, ink waits in the writer and goes when the socket is back. The reply to `inkResend` is the whole easel, sent at once (it is exempt), its last message marked `"last": true`; it carries what was waiting, so nothing goes twice.
6. **`inkSync` on the drawer's device** is taken only by a page that has drawn nothing this turn (a reload). A page that drew keeps its own picture; its unsent batches follow.
7. **Seats.** Nobody can open a seat from a scan, so the host's phone keeps one seat open in a Purrtrait lobby (`keepSeatOpen`); Start closes the open ones, as at other tables. A lobby of 7 to 10 seats is a ring on the phone and two rows on the TV.
8. **The phone's lobby** (a redesign for one room): no code chip, no Far away, no House Cat. One panel: the timer pills (the host's to change), "Scan the code on the TV.", This device, Show on TV (the host, only while no TV shows the table: the new-TV path), How to play. The seat sheet has Remove for the host. Under Start: "Waiting for the TV" until the TV shows the table.
9. **The shelf** shows Purrtrait with "Starts on the TV" where Play would be, and the tip "Pick Purrtrait on the TV." once Home's Play tip is learned. As Toy Tumble does (`SHELF` in `lib/catalog.ts`), Purrtrait is offered on the shelf and the TV's posters only by a build with `WEB_PURRTRAIT=on`, so it stays off production's shelf until the switch-on release; a table of it still draws. CI's e2e jobs build with `WEB_PURRTRAIT=on`.
10. **A second e2e server.** Purrtrait runs on the room's clock, which the main e2e server's `DEV_SPEED:20` cuts to seconds, so `playwright.config.ts` starts a second `wrangler dev` at real speed (port `E2E_PORT + 6`) for `purrtrait.spec.ts` and the drawing frame gate.
11. **Poster art** is composed from the existing tuxedo cat and a drawn easel (no art generator was available); the iOS session may replace it with its own.
12. **The TV's home** with five posters (four games and Tonight's board) is three rows of two.
13. **The reveal** sizes the word to its longest word, so a word never breaks in the middle.
14. **Got it** opens "Who got it?", everyone else's cat and name. **Give up** asks once: Give up / Keep drawing. Undo, Clear and Got it carry no icons, so the tools fit one row on iPhone SE and wrap only at the largest text.
15. **Tips.** "No letters or numbers" points at the word bar (the easel fills its screen, so a tip beside it would fall off), learned on the first stroke. "Tap who said it first" shows on the Who got it? sheet, over the cats (over the tools it would cover Undo and Clear). "Pick one to draw" on the cards, "Guess out loud" on a guesser's "Look at the TV".
16. **No Cards/Table switch** at a Purrtrait table, and the table menu's Show on TV is the host's only, while no TV shows it. Forfeit says "Your turns are skipped. The rest play on." A removed phone says "The host removed you from this table."
17. **The drawer's screen holds through the pick:** the `chosen` event's fold keeps the picking device the drawer's until the snapshot brings the word, so a shared phone's curtain never comes down twice.
18. **Tests' hooks:** the QR element carries `data-url` (the URL it encodes).

## Review Focus

1. **A finger drawing fast on a 60 Hz Android phone:** no gaps in the line (coalesced events), no dropped frames. Test: `purr-ink.test.ts` "coalesced points keep a fast line whole" and the main-thread gate in Task 6.
2. **The TV page reloaded mid-turn after an undo and a clear:** the easel shows the same picture. Test: Task 3 "inkSync replays to the same pixels" (compare canvas `getImageData` hashes).
3. **iPhone SE (375 × 667) as the drawer:** easel, tools, Got it and Give up all fit without scrolling. Test: Playwright screenshot at 375 × 667 and `purr-layout.test.ts`.
4. **A phone that scanned a QR a minute ago:** "Scan the code on the TV." with no join, no stuck spinner. Test: Task 5 e2e with a stale key.
5. **The drawer locking their phone mid-stroke:** the stroke ends cleanly; on return the canvas shows the drawing from `inkSync`. Test: Task 4 "visibility hidden ends the stroke".

---

### Task 1: The wire and the ink core

**Files:** Create `src/table/purr-model.ts`, `src/table/purr-ink.ts`, tests beside them. Modify the room store for `purrtrait` views, `ink`, `inkSync`, `inkResend`, `remove`, the new error codes, `tests/catalog.test.ts` (purrtrait drawn now).
- [ ] Tests first: every purrtrait fixture decodes; `encodeBatch` of a recorded stroke yields valid ops under 8 KB; `decode(encode(x))` round-trips; `compact` matches the server's on "s,s,u,c,s"; RDP keeps corners.
- [ ] Implement, run `pnpm --filter @pounce/play-web test`, commit.

### Task 2: The easel renderer and its worker

**Files:** Create `src/table/purr-easel.ts`, `src/workers/purr-ink.worker.ts`, tests.
- [ ] Tests: smoothing through midpoints; finished strokes go to the bitmap, the live stroke redraws alone; resize keeps the picture (re-rasterise in the worker from the op log).
- [ ] Implement, commit.

### Task 3: The TV page

**Files:** Create `src/ui/tv/purr-tv.tsx` (lobby with join QR from `room.near`, the easel, cats and scores on the left, drawer, timer and group on the right, the reveal, game over), modify the TV home's posters and "Change game".
- [ ] Tests: lobby QR encodes `https://play.conleychaos.com/e/<CODE>?near=<KEY>` and refreshes with the key; the 8-character code shows; reload mid-turn replays `inkSync` to the same pixels; the reveal shows the word.
- [ ] Implement, screenshots at 1920 × 1080 and 1280 × 720, commit.

### Task 4: The drawer's phone and the guesser's phone

**Files:** Create `src/table/purr-draw.tsx`, `src/table/purr-watch.tsx`, `src/table/purr-layout.ts`, `src/table/purrtrait.css`.
- [ ] Drawer: two word cards with points, then word and timer on top, easel, colours, widths, Undo, Clear, Got it (sheet of cats and names), Give up; curtain on a shared device; "Easel full" on that error; replays its own drawing on `inkResend`.
- [ ] Guesser: "Look at the TV", whose turn, score, "You draw next".
- [ ] Tests: layout fits 320 × 568 up; pointer events with `getCoalescedEvents`; visibility hidden ends the stroke. Commit.

### Task 5: Joining, shelf, lobby, remove

**Files:** The `/play/e/<CODE>` route (scan opens it), "Join with code" takes 5 or 8 characters, the shelf poster "Starts on the TV" with a tip, the lobby timer pills (host), the seat menu's Remove (host), "Scan the code on the TV." on `not_near`.
- [ ] e2e: a stale key is refused; a removed phone stays out. Commit.

### Task 6: Full games, gates and the PR

**Files:** `e2e/purrtrait.spec.ts` (the TV page and three phones, one a shared phone, play a whole game; the drawing shows on the TV while drawn; a TV reload mid-turn), `e2e/main-thread.spec.ts` (a 10-second scripted drawing on the slowed phone and the TV project), How to play page, tips.
- [ ] Run the e2e and the gates, screenshots of every screen at every size in the spec's list, PR "Purrtrait in the browser: draw on your phone, the TV shows it live", notes for the iOS session in the shared notes folder.
