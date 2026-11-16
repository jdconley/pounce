# Pounce on the TV, stage 2: web — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The web player gets a TV page at `/play/tv` that shows the table for both games on any big screen, a phone controller layout that shows only your own cards when a TV is at the table (with an always-visible Cards/Table switch), "Show on TV" by backup code, the `/play/tv-link/<token>` page a phone camera opens from the TV's QR, and live `aim` pointing.

**Architecture:** The public table (everything anyone may see) is split out of `CatTowerTable` and `TilesTable` into components the phone's full table and the TV page both render: one copy of the drawing code. The TV page is a separate route that skips first run, keeps its own device credential, waits on a screen link socket, then opens a `RoomStore` with `role=screen`. The phone's controller is a new component per game built from the same hand pieces and move logic as today's table. Timers (aim throttle, link renewal) live in `src/net` and `src/store`, never in `src/ui` or `src/table` (ESLint main-thread rules).

**Tech Stack:** Preact 11, Vite 8, TypeScript, vitest (`apps/play-web/tests`), Playwright (`apps/play-web/e2e`), `qrcode-generator` (already a dependency).

**Spec:** `docs/superpowers/specs/2026-11-16-tv-table-design.md` (§3, §4, §6, Testing "Web e2e"). Wire contract: `docs/tv-protocol.md` (stage 1). Code map: the stage 2 notes in the plan workspace (`web-map.md`).

## Global Constraints

- The wire contract is `docs/tv-protocol.md`; nothing here changes the server except the e2e server's `--var TV:on`.
- The TV page never creates a person, never runs first run, never calls `syncProfile`, `reach` or `noteSource`, and keeps its credential under its own key `pounce.tv.device` (a phone and a TV page in one browser are two devices; the server refuses a seated device as a screen).
- The TV page has no text entry anywhere. It works by arrow keys, Enter, Escape/Backspace (and remote Back codes) and the mouse.
- Phones switch to the controller by default when `room.screen === true` and they hold a seat. The Cards/Table switch is on the controller screen itself, always visible, one tap: "Cards" | "Table". The choice is per phone, per table (kept in `pounce.views`, a map of code → view, newest 30). When `screen` is absent every phone shows the full table, whatever the switch says; when it comes back, a phone on "Table" stays on "Table".
- Sound: the TV plays game sounds. A phone on "Cards" plays no game-event sounds (button taps stay). A phone on "Table" plays them as today.
- Haptics stay on phones; `buzz("turn")` on your turn, in both views.
- Copy, exact: TV home "Scan with your phone to put your table here", buttons "Cat Tower", "Tuna Tiles"; TV start "Start"; TV lobby "Press Start on any phone", "Change game"; TV menu "Link another table", "Leave table", "Sound on"/"Sound off"; TV game over "Play again on any phone"; TV turn banner "<Name>'s turn"; old browser "Use a laptop or an Apple TV."; phone switch "Cards", "Table"; phone "Show on TV" (sheet title and menu item), field label "TV code", button "Show"; toast "On the TV"; confirm "Move the TV to this table?" with "Move" / "Cancel"; tip at the switch "Your cards are here. The table is on the TV."; tv-link page "Put a table on the TV", sections "Your tables", "New game". No emoji anywhere.
- TV sizing: at 1920×1080, nothing that matters (card ranks, tile numbers, names, counts, scores, banner) is under 28 CSS px; layouts scale with `height / 1080` so 1280×720 and 3840×2160 viewports both fit with nothing clipped.
- Main thread: no `setTimeout`/`setInterval` in `src/ui/**`, `src/table/**`, `app.tsx`, `main.tsx`; storage only through `store` (`lib/kv.ts`); no `localStorage` direct use. Any new top-level folder joins `UI_CODE` in `eslint.main-thread.mjs`.
- Keep the accessible names and ids the existing e2e and the main-thread spec use: "Practice", "Menu", "Home", "Play Tuna Tiles", "Start", "Hint", "Start over", `#deck`, `#discard`, `#play-btn`, `.card.mine .card-inner`, the "Toy box" img.
- Fit: phone controller at 320×568, 375×667, 390×844, 430×932, iPad 820×1180 and 1180×820; TV at 1280×720, 1920×1080, 3840×2160. Long names (20 characters) and three-digit scores included.
- Browser support: current Chrome, Safari, Firefox, Edge; current Chromium TV browsers. No legacy bundle; `index.html` gets a `nomodule` fallback that shows "Use a laptop or an Apple TV." on `/play/tv`.

## Review Focus

1. **Same browser, two roles.** A phone tab and a `/play/tv` tab in one browser profile: two credentials, both work, the TV tab never shows a hand. (Task 1 unit test on the key; Task 9 e2e.)
2. **The TV drops mid-hand.** Phones go back to the full table after about 10 s, the game goes on, and the TV rejoins to the same table on reload (it remembers the room it was showing under `pounce.tv.room`). (Task 9 e2e.)
3. **A phone on "Table" when the TV comes back** stays on "Table"; one on "Cards" goes back to Cards. (Task 7 unit, Task 9 e2e.)
4. **Aim spam.** Dragging a tile draft fast sends at most one `aim` per 120 ms per device with the last state always sent, and a cleared aim follows a submit or reset. (Task 1 unit.)
5. **A smart-TV remote.** Arrow keys always move focus to the nearest focusable thing in that direction and never leave focus on nothing; Back opens the menu at the table and goes back from it. (Task 4 unit for the pure focus helper.)

---

### Task 1: Net and store for screens, links and aims

**Files:**
- Modify: `apps/play-web/src/net/api.ts` (`Api` takes a credential key; `screens`, `linkScreen`; `createRoom` takes `{ screen: true }`)
- Create: `apps/play-web/src/net/screen-link.ts`
- Modify: `apps/play-web/src/net/socket.ts` (`role` option → `?role=screen`)
- Modify: `apps/play-web/src/store/room.ts` (`aims`, `aim()`, `screen`)
- Create: `apps/play-web/src/store/views.ts`
- Test: `apps/play-web/tests/screen-link.test.ts`, `tests/room.test.ts`, `tests/socket.test.ts`, `tests/views.test.ts`

**Interfaces:**
- Produces:
  - `new Api(base?, fetcher?, credentialKey = "pounce.device")`; `export const tvApi = new Api(undefined, undefined, "pounce.tv.device")`.
  - `api.screens(showing?: string): Promise<{ token: string; code: string; url: string; expiresIn: number }>`
  - `api.linkScreen(body: { token: string } | { code: string }, room: string, move?: boolean): Promise<"linked" | "showing">` — throws `ApiError` for 404/403/429 (with `retryAfter` on the error for 429).
  - `api.createRoom(game, opts?: { screen?: true })` — existing signature plus the option.
  - `class ScreenLink` in `net/screen-link.ts`: `constructor(opts: { api: Api; origin?: string; factory?: SocketFactory; setTimer?; clearTimer?; now? })`; `start(showing?: string)`; `stop()`; `on(listener: (e: ScreenLinkEvent) => void): () => void` with `ScreenLinkEvent = { kind: "code"; token: string; code: string; url: string } | { kind: "linked"; room: string } | { kind: "offline" }`. It renews at 80% of `expiresIn` (new `screens()`, new socket, old socket closed), reconnects its socket with the socket backoff, and stops after `linked`.
  - `RoomSocketOptions.role?: "screen"`; `socketUrl(origin, code, role?)`.
  - `RoomState.aims: Record<number, GameAim>` — the latest aim per seat; cleared for all seats when a snapshot's turn or status differs from the last, and per seat by a clearing `aim`.
  - `RoomStore.aim(seat: number, aim: GameAim | null): void` — leading send, then at most one send per `AIM_EVERY_MS = 120` with the latest value trailing; `null` sends the clearing message at once and drops any pending trailing value.
  - `views.ts`: `viewOf(code: string): "cards" | "table"` (default "cards"), `setView(code, view)`, stored as `pounce.views` (newest 30 codes).

- [ ] Step 1: failing unit tests — `Api` with key `"pounce.tv.device"` reads and writes only that key; `screens()`/`linkScreen()` request shapes and error mapping (404 → `ApiError(404,"not_found")`, 409 `showing` → `"showing"`); `socketUrl(..., "screen")` ends with `&role=screen`; `ScreenLink` with a fake socket and clock: emits `code`, renews at 80% (two `screens()` calls, the first socket closed), emits `linked` and stops; `RoomStore.aim` throttle (`FakeSocket.sent`: leading, ≤ 1 per 120 ms, trailing last, clear immediate); `aims` set by `{t:"aim"}`, cleared on turn change; `views` default, set, cap 30.
- [ ] Step 2: run `pnpm --filter @pounce/play-web test` → FAIL.
- [ ] Step 3: implement.
- [ ] Step 4: run `pnpm --filter @pounce/play-web test && pnpm lint` → PASS.
- [ ] Step 5: commit "Web: talk to TVs: screen links, the screen role, live aim".

---

### Task 2: Routes, the shared QR, and the TV page shell

**Files:**
- Modify: `apps/play-web/src/lib/router.ts` (`{kind:"tv"}`, `{kind:"tvLink"; token}`)
- Modify: `apps/play-web/src/app.tsx` (TV route renders before the age and name gates; first-run effects skipped)
- Create: `apps/play-web/src/ui/qr.tsx` (`QrCode({ url, label, size })`, extracted from `QrCard` in `lobby.tsx`, which then uses it)
- Create: `apps/play-web/src/ui/tv/tv-app.tsx`, `apps/play-web/src/ui/tv/focus.ts`, `apps/play-web/src/ui/tv/tv.css`
- Modify: `apps/play-web/index.html` (`nomodule` fallback for `/play/tv`)
- Test: `apps/play-web/tests/router.test.ts`, `apps/play-web/tests/focus.test.ts`

**Interfaces:**
- Produces:
  - `parseRoute("/play/tv")` → `{kind:"tv"}`; `parseRoute("/play/tv-link/<22 chars>")` → `{kind:"tvLink", token}`; `pathFor` inverses.
  - `focus.ts`: `nearest(from: Rect, candidates: { id: string; rect: Rect }[], dir: "up" | "down" | "left" | "right"): string | null` (pure: in the half-plane of `dir`, smallest distance weighting off-axis ×2), and `useDpad(root: Ref<HTMLElement>)` that moves focus among `[data-tv]` elements on arrow keys and keeps focus on something (first `[data-tv-default]`) whenever it would be lost.
  - `TvApp`: phases `start` → `home` → `lobby` | `table` | `over`. `start`: one big "Start" (requests full screen, unlocks audio, takes a Wake Lock, re-taken on `visibilitychange`). `home`: the link QR (`ScreenLink`'s `url`) big, the backup code under it, "Scan with your phone to put your table here", and buttons "Cat Tower" and "Tuna Tiles" (create a room with `screen: true`, then open it). The room it shows is kept as `pounce.tv.room` so a reload rejoins it.

- [ ] Step 1: failing tests for `parseRoute`/`pathFor` and `nearest` (four directions, ties, nothing in that direction → null).
- [ ] Step 2: implement; the table phases render placeholders until Tasks 5–6.
- [ ] Step 3: `pnpm --filter @pounce/play-web test && pnpm lint && pnpm --filter @pounce/play-web build` → PASS.
- [ ] Step 4: commit "Web: a TV page that shows its link and makes a table".

---

### Task 3: TV layouts for both games (pure)

**Files:**
- Modify: `apps/play-web/src/table/ct-layout.ts`, `apps/play-web/src/table/tiles-layout.ts`
- Test: `apps/play-web/tests/layout.test.ts`

**Interfaces:**
- Produces: `ctLayout({ ...input, tv: true })` and `tilesLayout({ ...input, tv: true })`: no hand, no trays, no rack; every playing seat placed around the table (Cat Tower: seats across the top and the sides, piles centre, laid rows between; tiles: seats across the top, the board filling the rest); the stage uses the full 16:9 frame; sizes scale by `unit = min(width / 1920, height / 1080)`. A `banner: Rect` for the turn banner in both.

- [ ] Step 1: failing tests at 1280×720, 1920×1080, 3840×2160 for 2–6 seats (Cat Tower) and 2–4 (tiles), with every seat laid down with 3 groups of 10 cards (Cat Tower) and 30 sets of 3 on the board (tiles): every rect inside the frame; no two seat rects overlap; at 1920×1080 `cw >= 112`, `avatar >= 132`, piece `pw >= 52`, banner height ≥ 64; at 3840×2160 every size doubles (±1 px).
- [ ] Step 2: implement. Step 3: tests PASS. Step 4: commit "Web: big-screen layouts for both games".

---

### Task 4: Split the public table out of both tables

**Files:**
- Create: `apps/play-web/src/table/ct-public.tsx` (`CtPublic`), `apps/play-web/src/table/tiles-public.tsx` (`TilesPublic`)
- Create: `apps/play-web/src/table/ct-moves.ts` (the move logic `CatTowerTable` holds today, pure: draw, discard (with skip target), tray placement, lay down via `matchPhase`, hit targets via `canHit`)
- Modify: `apps/play-web/src/table/cattower.tsx`, `apps/play-web/src/table/tiles.tsx`
- Test: `apps/play-web/tests/ct-moves.test.ts`; the existing e2e must pass unchanged.

**Interfaces:**
- Produces:
  - `CtPublic({ room, layout, motion, aims, onGroup?, onSeat?, discardAim?, children? })` renders the rug, tower, every seat's avatar with counts and scores, the laid rows and their group zones, deck and discard, the cue line, flights and `RoundOver`, and the aim glow (`.group-zone.aimed` for `aims[turn]`). Callers add the hand, trays and controls as children. It plays game sounds only when `sounds` is true (prop, default true).
  - `TilesPublic({ room, layout, aims, draft?, onSet?, sounds? })` renders seats, board, pool and sets; when `aims[turn]` exists and no local `draft` is given, the board shows the aim's table with pieces not on `v.table` marked `.draft`.
  - `ct-moves.ts`: `hitTargets(card: CardId, laid: (Group[] | null)[]): { seat: number; group: number; side?: HitSide }[]`, `layDownGroups(trays: CardId[][], phase: number): { cards: CardId[]; runStart?: number }[] | null`, `discardNeedsTarget(card: CardId): boolean`, `skipTargets(view: CatTowerView, seat: number): number[]`, plus `targetLabel(room, seat, group): string` ("Mom's 3s", "Your run", "Ava's run of 7s") — the copy for the hit list.
  - `CatTowerTable` and `TilesTable` render the public components plus their hand layers; behaviour and every existing id, label and test stay as they are.

- [ ] Step 1: failing tests for `ct-moves.ts` (`hitTargets` matches `canHit` on a laid set and a run with both sides, none on an unlaid seat; `layDownGroups` for phases 1, 4, 8; `targetLabel` words).
- [ ] Step 2: extract; run `pnpm --filter @pounce/play-web test`, `pnpm --filter @pounce/play-web build`, then the full e2e `pnpm --filter @pounce/play-web e2e` → PASS with no spec edits.
- [ ] Step 3: commit "Web: one table drawing for the phone and the TV".

---

### Task 5: The TV table, lobby and game over

**Files:**
- Create: `apps/play-web/src/ui/tv/tv-table.tsx`, `apps/play-web/src/ui/tv/tv-lobby.tsx`, `apps/play-web/src/ui/tv/tv-menu.tsx`
- Modify: `apps/play-web/src/ui/tv/tv-app.tsx`, `apps/play-web/src/ui/tv/tv.css`

**Interfaces:**
- Consumes: `tvApi`, `ScreenLink`, `RoomStore` with `role: "screen"` (Task 1); TV layouts (Task 3); `CtPublic`, `TilesPublic` (Task 4); `QrCode`, `useDpad` (Task 2).
- Produces:
  - Lobby: the invite QR (`<origin>/j/<CODE>`) big, the code under it, the seats as cats walking on as they fill, "Press Start on any phone", and "Change game" only while nobody is seated (makes a room of the other game and moves there).
  - Table: the public table in the TV layout, the turn banner "<Name>'s turn", the aim glow and tile drafts, game sounds, celebrations (round over, phase, game over) at TV size.
  - Game over: scores and "Play again on any phone"; on `{t:"rematch"}` the TV follows the new code as a screen.
  - Menu (Escape, Backspace, remote Back, or a corner button): "Link another table" (shows the link QR with `showing` set; a link moves the TV), "Leave table" (home), "Sound on"/"Sound off".
  - The room's socket closing for good (`closed`, `notFound`) goes home.

- [ ] Step 1: implement; drive it by hand against the e2e server (`E2E_PORT=8792`, `--var TV:on`) with two phone tabs; screenshot 1920×1080 and 1280×720 for both games and every phase (home, lobby, table, game over, menu) into the plan workspace.
- [ ] Step 2: `pnpm --filter @pounce/play-web test && pnpm lint && pnpm --filter @pounce/play-web build` → PASS.
- [ ] Step 3: commit "Web: the TV shows the table, the lobby and the winners".

---

### Task 6: Cat Tower on a phone controller

**Files:**
- Create: `apps/play-web/src/table/ct-controller.tsx`, `apps/play-web/src/table/ct-controller-layout.ts`
- Modify: `apps/play-web/src/ui/table-screen.tsx` (choose controller vs full table; the switch), `apps/play-web/src/table/table.css`
- Test: `apps/play-web/tests/layout.test.ts` (controller layout)

**Interfaces:**
- Consumes: `views.ts`, `RoomStore.aim` (Task 1); `ct-moves.ts` (Task 4).
- Produces: `CtController({ store, state })` — top: "Your turn" or "<Name>'s turn" and the Cards/Table switch; on your turn in the draw step two big buttons, Deck (`#deck`) and the discard card (`#discard`); the hand large and sorted the player's way (today's sort and drag-to-reorder, ids and `.card.mine` kept); the lay-down trays as today's minus the table; Hit: pick a card, then a target from a short list of `hitTargets` labelled by `targetLabel`; choosing a target calls `store.aim(seat, { target })`, confirm plays it and clears the aim; Discard by dragging to the discard spot or tapping "Discard"; off turn, the hand and "<Name>'s turn". No game-event sounds. `ctControllerLayout({ width, height, insets, handCount, trays, step })`.
- The switch: `SwitchView({ view, onChange })` with `aria-label` "View", two buttons "Cards" and "Table", `aria-pressed`; on the full table too while `screen` is on. A first-time `<Tip id="tv.switch" anchor="view-switch" text="Your cards are here. The table is on the TV.">`.

- [ ] Step 1: failing layout tests at the phone sizes in Global Constraints, 11 cards and 3 trays: hand, trays, buttons and the switch inside the safe frame, no overlaps, card width ≥ 56 px at 320 wide.
- [ ] Step 2: implement; Step 3: tests and build PASS; screenshots at 320×568, 390×844, 430×932, 820×1180 of: off turn, draw step, play step with trays, the hit list with a target chosen, pass-and-play curtain.
- [ ] Step 4: commit "Web: your phone shows just your cards when the table is on the TV".

---

### Task 7: Tuna Tiles on a phone controller

**Files:**
- Create: `apps/play-web/src/table/tiles-controller.tsx`
- Modify: `apps/play-web/src/table/tiles.tsx` (send the draft as `aim`), `apps/play-web/src/ui/table-screen.tsx`

**Interfaces:**
- Produces: off turn, the rack only (large, sortable) with "<Name>'s turn" and the switch; on your turn, today's full tiles table (rearranging needs it) with the switch, and every draft change calls `store.aim(seat, { table: draft.table })`; submit, reset and turn end clear it. No game-event sounds on "Cards".
- Unit test (`tests/views.test.ts` or a new `tests/controller.test.ts`) for the view rule: `showController(room, view)` true only when `room.screen && mySeats(room).length > 0 && view === "cards"`.

- [ ] Steps: failing unit test → implement → tests/build PASS → screenshots (off turn rack, on turn) → commit "Web: Tuna Tiles on a phone with the TV; the TV watches you work it out".

---

### Task 8: Show on TV, and the page a phone's camera opens

**Files:**
- Create: `apps/play-web/src/ui/show-on-tv.tsx` (the sheet), `apps/play-web/src/ui/tv-link.tsx` (the `/play/tv-link/<token>` page)
- Modify: `apps/play-web/src/ui/lobby.tsx` (a "Show on TV" choice in the add bar), `apps/play-web/src/ui/table-screen.tsx` (menu item), `apps/play-web/src/app.tsx` (route; first run first if needed, then back to the link)

**Interfaces:**
- Produces:
  - Show on TV sheet: field "TV code" (6 letters/digits, upper-cased as typed), "Show"; on 409 `showing` a confirm "Move the TV to this table?" with "Move" / "Cancel"; on success a toast "On the TV"; wrong code → "No TV with that code."; 429 → "Too many wrong codes. Try again later."
  - tv-link page: "Put a table on the TV"; "Your tables" (the known tables still in lobby or playing, tap one to link it); "New game" with the two games (makes the table, links it, opens it).

- [ ] Steps: implement → unit test for code normalisation (`normaliseTvCode(" bcd fgh ")` → `"BCDFGH"`, invalid → null) → build PASS → screenshots → commit "Web: put your table on the TV with its code or its QR".

---

### Task 9: End-to-end, frame gates, and the PR

**Files:**
- Modify: `apps/play-web/playwright.config.ts` (`--var TV:on`; project `tv-chrome` = Desktop Chrome at 1920×1080 with `testMatch: /tv\.spec/`; phone projects `testIgnore` adds `tv\.spec`)
- Create: `apps/play-web/e2e/tv.spec.ts`, `apps/play-web/e2e/tv-helpers.ts`
- Modify: `apps/play-web/e2e/main-thread.spec.ts` (a `tv-chrome` budget, 1000/60 ms p95, with a TV play-through: TV page, two phones, a few turns of each game)

Tests in `tv.spec.ts` (phones as Pixel 7 and iPhone 13 contexts created inside the test):
- `a TV and two browser phones play Cat Tower to the end` (real turns until someone lays down, then the rest forfeit — game over shows on the TV with "Play again on any phone").
- `a TV and two browser phones play Tuna Tiles to the end` (draws and plays, then forfeit to the end).
- `a pass-and-play phone with a TV` (one phone, two seats; the curtain on the phone, normal turns on the TV).
- `the Cards/Table switch survives the TV leaving and coming back`.
- `the TV drops mid-hand and comes back` (phones show the full table after the grace; the TV reloads into the same table).
- `a phone links its table to a TV on its home screen, by QR link and by backup code`.
- `the controller fits phone sizes` (320×568 and 430×932: nothing outside the viewport, `#deck` and the hand visible).
- `the TV never shows a hand` (no `.card.mine`, no rack tiles in the TV page's DOM at any point of the Cat Tower game).

- [ ] Step 1: write the specs; run `pnpm --filter @pounce/play-web build && pnpm --filter @pounce/play-web e2e` → PASS on every project.
- [ ] Step 2: cross-platform: `apps/play-ios/scripts/e2e.sh` (iPhone client, with `DEV_SERVER_URL=http://localhost:8793`) joins a table a TV page shows and plays it out; `e2e/mixed.spec.ts` passes.
- [ ] Step 3: before/after screenshots of the phone table, the controller and the TV for the PR.
- [ ] Step 4: PR "Pounce on the TV in any browser; your phone shows just your cards"; merge when `check`, `build`, `e2e-web` pass; check production `/play/tv` loads and makes a table.
