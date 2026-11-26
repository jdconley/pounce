# Birdwatch in the web player: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Birdwatch plays in the web player (`apps/play-web`) and on its TV page, against the server merged in PR #156, with the same rules, rooms and words as iOS.

**Architecture:** The server says what is legal (`playable`, `bidRange`, `partnerChoices`); the web player never ports the rules. It imports only the pure card and rule-set data from `@pounce/play-api/birdwatch/{cards,rules}` to sort and label cards. A public table (`bw-public.tsx`: the window of cats, the sill, the trump badge, the score strip) is shared by the phone table and the TV, as Cat Tower's `ct-public.tsx` and Tuna Tiles' `tiles-public.tsx` are. The phone table (`birdwatch.tsx`) adds the hand and one phase panel at a time (bid, nest, trump, partner). Geometry is pure (`bw-layout.ts`) and tested without a browser.

**Tech Stack:** Preact 11, TypeScript, plain DOM moved by `transform` (motion.ts), Web Animations, Vitest + happy-dom, Playwright against `wrangler dev`.

**Spec:** `docs/superpowers/specs/2026-11-25-birdwatch-design.md` (§3, §5.1-5.5, §5.7, §5.8 here; §5.6 for the TV), wire `docs/superpowers/notes/2026-11-25-birdwatch-wire.md`, parent `docs/superpowers/specs/2026-11-15-web-player-design.md`.

## Global Constraints

- The main thread draws only: no storage outside `lib/kv.ts`, no `setTimeout`/`setInterval` in `ui/`, `table/`, no 16.7 hard-coded, no `@pounce/play-api/bots/*` or `games/*` value imports on the page (`eslint.main-thread.mjs`). The House Cat never runs in the browser.
- Animate `transform` and `opacity` only; fade overlapping groups as one layer (a dimmed card is one element; the dimmed hand is never faded card by card over another card).
- 60 fps or better, smooth at 120 Hz: per-frame main-thread work p95 under 8.3 ms on a laptop.
- Copy: buttons 1-3 words, messages one short sentence, no emoji, no "you can". Never the commercial game's name, bird card, colours or wording. No Wordle, Block Blast, Zoodoku, NYT or Queens.
- The Bird: bright, round, cartoon songbird, ours; never black, never crow-shaped. Suits: fish, mouse, feather, bell with Tuna Tiles' colours and silhouettes; colour never the only cue.
- Code id `birdwatch`; display name "Birdwatch". Rule set names: Official, Tucker, Friesen. Pill lines verbatim: Official "1s out, Bird wild.", Tucker "1s high, worth 15.", Friesen "1s high, Bird follows suit."
- Screen-reader labels: "10, fish, 10 points", "Bird, 20 points, top trump", "1, bell, 15 points"; a card worth nothing: "7, mouse".
- Local server on port 8795 (`GAMES:tiles,birdwatch`); never 8787 or 4343. Browsers muted (`--mute-audio`, headless).
- Stay out of `apps/play-ios` and `apps/play-api`.

## Rulings on gaps (recorded here, per the brief)

1. **No iOS art yet.** The iOS session had no Birdwatch art when this started. Faces are drawn to §3.3: the suit's Tuna Tiles colour body, big white outlined numeral, the existing `tile-<suit>` silhouette, a seed badge (5, 10, 15) on counters. The Bird is our own SVG (`src/table/bw-art/bird.svg`): round, yellow-orange, a big eye and a teal wing, on a white face with a "20" seed badge. Back: the existing `card-back` (Cat Tower's violet paw back). The Home poster `game-birdwatch.webp` is made once by `scripts/build-birdwatch-art.mjs` (room art + cats + the Bird) and committed. If iOS exports art later, `build-art.mjs` takes it over.
2. **Home's table card can't name the rule set.** `GET /v1/devices/me/tables` carries no options (`apps/play-api/src/room/tables.ts`). Server gap, reported in the PR; Home shows "Birdwatch" as it shows other games. The lobby, the table menu and the TV name the rule set (they have the snapshot).
3. **No e2e sharding exists** in CI (`e2e-web` is one job over Playwright projects). Birdwatch's full games run in one spec, `e2e/birdwatch.spec.ts`, on `laptop-chrome` (keyboard and mouse) with the 5-player game also on `android-chrome` (touch). If the job grows past its 40 minute timeout, the spec gets a CI job of its own (`e2e-web-birdwatch`, `--project laptop-chrome --grep Birdwatch`).
4. **First table and practice.** A Birdwatch first table gets House Cats up to 4 seats (3 cats), so Start is lit at once; Practice fills 3 House Cats and closes the rest. Home's Practice stays Cat Tower; the shelf's Birdwatch poster makes a table.
5. **Raise faster.** A long press on +5 repeats the raise every 140 ms after 400 ms, driven by `requestAnimationFrame` and pointer events (no timers in table code).
6. **Keys.** Hand: Left/Right move the selection, Enter or Space plays (play phase) or toggles a put-back (nest), Escape clears. Bidding: + or = raises 5, - lowers, Enter bids, P passes. Trump: 1-4 pick fish, mouse, feather, bell. Partner: the picker's buttons are a grid in Tab order.
7. **Between hands** is the server's `between` phase: the summary panel shows until the next `dealt`. The game-over dialog lists sides, not seats, in 4 and 6 players.
8. **5-player privacy.** `youArePartner` shows a small "Partner" ribbon on the hand only while that seat's hand is shown (behind the curtain on a shared device). The public table never marks the partner until `view.partner` is set. A phone that holds both seats can't hide it (§4.6, accepted).
9. **How to Play** is an in-app sheet per rule set (`bw-help.tsx`), opened from the table menu and from the lobby's rule pills' "How to play" link. Other games keep `/support`.
10. **TV "Change game"** cycles through the three games (`otherGame` returns the next id), so a TV can open a Birdwatch table.

## Review Focus

1. **Seventeen cards on a 320 px phone** (Tucker, 5 players, bid winner with the nest): the fan overlaps, every card's numeral stays readable (the numeral sits top-left), nothing leaves the screen. Test: `bw-layout.test.ts` "17 cards fit 320 wide with a corner showing".
2. **A long name at six seats** in the window and on the score strip: names truncate with an ellipsis, chips never overlap. Test: layout test "six seats never overlap at 320 px"; e2e screenshot at iPhone SE.
3. **A move refused** (`must_follow` from a stale tap, `bid_too_low` after someone else bid): the card goes back, the panel shakes, nothing stays stuck as pending. Test: `bw-table.test.ts` "a refused play puts the card back".
4. **The page opens mid-hand from a snapshot** (reload, a second device): every phase renders from the snapshot alone, with no event seen first. Test: `bw-store.test.ts` renders each fixture snapshot through `bwPhaseOf` and the table smoke test.
5. **A seat a House Cat took over** (`left: true`, `kind: "bot"`): its name stays, a House Cat badge shows, the forfeit menu item is gone for the leaver, game over with `reason: "left"` reads "Game over". Test: `bw-model.test.ts` "a seat that left" and the fixture `snapshot-over-left`.

---

## File structure

| File | Responsibility |
| --- | --- |
| `src/lib/catalog.ts`, `src/lib/env.ts` | Shelf entry, `x-pounce-games` lists `birdwatch` |
| `src/store/room.ts` | Birdwatch event pacing and folding; pending action type |
| `src/store/lobby.ts` | Seat floor per game (4 for Birdwatch), first table / practice House Cats, rule-set and swap messages |
| `src/table/bw-model.ts` | Pure: card facts and labels, hand sort, sides and ribbons, who acts, phase of this device, summary rows, standings |
| `src/table/bw-layout.ts` | Pure geometry: window seats, sill, trump badge, score strip, hand fan, panel; phone, landscape, TV |
| `src/table/bw-faces.tsx` | Card faces and back, the Bird, the seed badge |
| `src/table/bw-art/bird.svg` | The Bird |
| `src/table/bw-public.tsx` | The table anyone may see (phone and TV) |
| `src/table/bw-panels.tsx` | Bid, nest, trump, partner, between-hands, score sheet |
| `src/table/birdwatch.tsx` | The phone table: hand, input, curtain, tips; the Cards view when a TV shows the table |
| `src/table/bw-help.tsx` | How to Play per rule set |
| `src/table/birdwatch.css` | Its styles |
| `src/ui/lobby.tsx` | Rule pills, Swap seats, team ribbons |
| `src/ui/table-screen.tsx` | Routes Birdwatch; game over, scores, forfeit for it |
| `src/ui/tv/tv-model.ts`, `tv-table.tsx`, `tv-lobby.tsx` | The TV's Birdwatch table, rule set name, game cycling |
| `scripts/build-birdwatch-art.mjs` | Makes the poster webp |
| `tests/bw-*.test.ts`, `tests/catalog.test.ts`, `tests/lobby.test.ts`, `tests/tv-model.test.ts` | Unit tests |
| `e2e/birdwatch.spec.ts`, `e2e/birdwatch-helpers.ts`, `playwright.config.ts` | Full games vs House Cats; screenshots |

---

### Task 1: The wire, the store and the header

**Files:** Modify `src/lib/catalog.ts`, `src/lib/env.ts`, `src/store/room.ts`, `tests/catalog.test.ts`. Create `tests/bw-store.test.ts`.

**Interfaces:**
- Produces: `GameId` includes `"birdwatch"`; `CATALOG.birdwatch = { title: "Birdwatch", minSeats: 4, maxSeats: 6, tagline: "Bid, call trump, take tricks.", art: "game-birdwatch" }`; `GAMES = "cat-tower,tiles,birdwatch,dish"`; `RoomState.pending.action: Action | TilesAction | BirdAction`; `foldEvent` folds `kind: "birdwatch"` and `kind: "houseCat"`; `eventPause` for Birdwatch: `played` 520, `trick` 900, `handOver` 1200, `bid`/`passed` 380, `turn` 0, others 300.

- [ ] Test: every fixture in `birdwatch-server-messages.json` goes through a `RoomStore` on a fake socket (`tests/fake-socket.ts`) with instant timers: snapshots land as `state.room.birdwatch`, events fold (`played` moves the card from `hands` to `trick` and lowers `handCounts`; `trick` clears `trick` and sets `lastTrick`; `bid` sets `bids[seat]` and `high`; `passed` sets `passed[seat]`; `trump` sets `trump`; `houseCat` sets the seat's kind to `bot` and `left: true`), and errors set `state.error.code`.
- [ ] Test: `NOT_YET` is empty and the shelf matches the server's catalog.
- [ ] Implement, run `pnpm --filter @pounce/play-web test`, commit.

### Task 2: Pure model

**Files:** Create `src/table/bw-model.ts`, `tests/bw-model.test.ts`.

**Interfaces (produces):**
- `cardFacts(id, rules): { bird: boolean; suit: Suit | null; rank: number | null; points: number }`
- `cardLabel(id, rules, trump?): string` (labels above; the Bird: "Bird, 20 points, top trump")
- `sortHand(cards, trump: Suit | null, rules): CardId[]`: suits grouped in the order fish, mouse, feather, bell with trump moved last, high to the right within a suit (rule set's rank order, 1 above 14 in Tucker and Friesen), the Bird last of all.
- `sideOf(view, seat): number` (index into `view.teams`), `sides(view): { seats: number[]; score: number; taken: number; bidding: boolean }[]` (taken = sum of `points` this hand of its seats; 5 players: each seat its own side, and the bid winner's side adds the partner's points once `partner` is known).
- `ribbonOf(view, seat): string` colour per side (`RIBBONS = ["#FFC21A", "#00D1C1", "#FF5CA8"]`), 5 players: the bid winner and, once known, the partner share `RIBBONS[0]`; everyone else none.
- `bwSeat(room, revealed)`: the same shape as `useCtSeat` (seat on show, curtain seat, my turn) for a shared device: the curtain rises for whoever acts next on this device before any hand shows, and again for each new hand (`key = hand:turn`).
- `phaseFor(view, seat): "bid" | "nest" | "trump" | "partner" | "play" | "wait" | "between" | "over"` for this device.
- `summary(view, seats)`: the last `history` entry as rows `{ label, change, total, made }` per side and the bid line ("Alice bid 85", "Made it" / "Missed").
- `standings(room)`: sides best first with names joined ("Alice and Ben"), and `overTitle(room)`: "Alice and Ben win", a single seat "Alice wins", none "Game over".
- `RULE_COPY: Record<RuleSetId, { name: string; line: string }>`.

- [ ] Tests with the fixtures' views and hand-made ones: sort order with trump bell in Tucker puts 1 above 14 and bells then the Bird last; labels; sides in 4, 5 (before and after `partner`), 6; standings and titles for `snapshot-over-target` and `snapshot-over-left`; `bwSeat` raises the curtain for a shared device on a new hand.
- [ ] Implement, run tests, commit.

### Task 3: Layout

**Files:** Create `src/table/bw-layout.ts`, `tests/bw-layout.test.ts`.

**Interfaces (produces):** `bwLayout({ width, height, insets, seats: number[] /* others, in order from my left */, hand: number, panel: "bid" | "nest" | "trump" | "partner" | "between" | null, tv?: boolean, cards?: boolean }): BwLayout` with `cw, ch, avatar, seats: Map<seat, {x,y}>, sill: Rect, slots: Map<seat, Pose>` (each trick card in front of its cat), `trump: Rect, strip: Rect, hand: Pose[], handRect: Rect, panel: Rect, banner: Rect, menu: Rect, landscape`. The hand fans with `fan()` from `ct-layout.ts`. Wide screens cap the stage at `min(width, height * 1.75, 1500)` and centre it, as `ctLayout` does. `cards: true` (the controller) drops the window and sill and gives the hand and panel the screen.

- [ ] Tests: at 320x568, 393x852, 768x1024, 1024x768, 1440x900, 1920x1080 TV, with 3, 4, 5 others and 9, 10, 15, 17 cards: every card inside the screen less insets; at least 22 px of each card's left edge shows; seats don't overlap each other or the sill; the strip and panel sit above the hand; the panel fits.
- [ ] Implement, run tests, commit.

### Task 4: Faces and art

**Files:** Create `src/table/bw-faces.tsx`, `src/table/bw-art/bird.svg`, `scripts/build-birdwatch-art.mjs`, `src/art/game-birdwatch.webp`, `src/table/birdwatch.css` (faces part).

**Interfaces (produces):** `BirdFace({ id, rules, dim? })`, `BirdBack()`, `injectBirdStyles()`.

- [ ] A face is one element with CSS background layers (the suit silhouette from `art("tile-<suit>")`, a saturated suit body gradient) and two spans (numeral top-left and big centre, seed badge bottom-right). The Bird is `bird.svg` on white with a "20" seed.
- [ ] Faces checked in a 15-card hand at 393 px (e2e screenshot); commit.

### Task 5: Public table

**Files:** Create `src/table/bw-public.tsx`; CSS.

**Interfaces (produces):** `BwPublic(props: { store; room; layout; motion; sounds?; haptics?; children?; onStrip?: () => void; seatsMine?: number[] })`: each other seat's cat (`SeatAvatar` with `count`), a ribbon under its name, a dealer chip, its bid sign (`bids[seat]`, "Pass" when `passed`, the high bid's sign gold, "Missed" after a missed hand), the turn pulse; the sill with `trick` cards at `slots`, the last trick sweeping to its winner on `trick` events; the trump badge (`#bw-trump`) and the high bid; the score strip (`#bw-strip`, a button when `onStrip`): one chip per side.

- [ ] Smoke test in `tests/bw-table.test.ts` (happy-dom): each fixture snapshot renders without throwing and names the trump and scores in its labels; commit.

### Task 6: Phone table, panels, input, tips, help

**Files:** Create `src/table/birdwatch.tsx`, `src/table/bw-panels.tsx`, `src/table/bw-help.tsx`; modify `src/ui/table-screen.tsx`.

**Interfaces:** `BirdwatchTable({ store, state, sounds?, topInset?, cards?: boolean, onView? })`. Panels: `BidPanel({ range, high, onBid, onPass })` (`#bw-bid`, `#bw-raise`, `#bw-pass`), `NestBar({ need, chosen, onDone })` (`#bw-nest-done`, "Put back 3", "Done"), `TrumpPicker({ suggest, onPick })` (`#bw-suit-fish` …), `PartnerPicker({ choices, trump, rules, onPick })` (rows by suit, trump first, then the Bird), `HandSummary`, `ScoreSheet`.

- [ ] Hand: tap lifts, tap again plays; drag onto the sill plays; unplayable cards (not in `playable` on my turn in play) carry `.dim` (one element each, not overlapping a translucent sibling: the dim is a filter on the face, `opacity` stays 1). Nest: tap toggles a put-back (lifted), Done sends `{type:"nest", discard}` when the count is right; `fromNest` cards glow.
- [ ] `table-screen.tsx`: Birdwatch routes to `BirdwatchTable`; game over, scores, forfeit read Birdwatch (left seats are out; forfeit says "A House Cat takes your seat.").
- [ ] Tips (one at a time, learned by use): `bw.bid` at `#bw-bid-sign` "Bid what your side will take.", `bw.follow` at `#bw-hand` "Follow the suit led. Dim cards can't play.", `bw.trump` at `#bw-trump` "Trump beats every other suit.", `bw.partner` at `#bw-partner-mark` "You're the secret partner.", `bw.keys` at `#bw-hand` "Keys: arrows pick, Enter plays." (fine pointer only).
- [ ] Unit test: a refused play puts the card back (`state.error` clears the held card); commit.

### Task 7: Lobby

**Files:** Modify `src/ui/lobby.tsx`, `src/store/lobby.ts`, `tests/lobby.test.ts`.

- [ ] `store/lobby.ts`: `minPlayers(room)` (4 for Birdwatch, else 2) used by `startBlock`, `startClosingOpenSeats`, `startWords` ("Needs 4 players."); `firstTableMessages` and `practiceMessages` fill House Cats up to `minPlayers - 1` others; `rulesMessage(rules)`, `swapMessage(a, b)`.
- [ ] Lobby: three pills (`role="radiogroup"`, "Rules"), host only (others see the chosen pill), the chosen one's line under them; a "How to play" link opens `bw-help`; ribbons on name tags by seat order once 4 or 6 are seated (`teamsFor` from the room's seat order after compaction: seated seats in order); seat menu "Swap seats" then tap a second seat.
- [ ] Tests for `minPlayers`, first table, practice, start words; commit.

### Task 8: TV

**Files:** Modify `src/ui/tv/tv-model.ts`, `tv-table.tsx`, `tv-lobby.tsx`, `tests/tv-model.test.ts`.

- [ ] `TvBirdwatch` draws `BwPublic` in the TV layout with the turn banner; never the partner mark before `partner`; `turnSeat`, `standings`, `overTitle`, `cheerStep` read Birdwatch; `otherGame` cycles; the TV lobby shows the rule set's name.
- [ ] Tests; commit.

### Task 9: End to end and screenshots

**Files:** Create `e2e/birdwatch.spec.ts`, `e2e/birdwatch-helpers.ts`; modify `playwright.config.ts` (`GAMES:tiles,birdwatch`).

- [ ] `playBirdwatch(page)` loop: on my turn bid the minimum or pass (alternating by hand), put back the first N cards, pick the suggested trump, call the first partner choice, play the first non-dim card by keyboard on laptop and by tap on a phone; until the game-over dialog.
- [ ] Tests: 4 players Official, 5 players Tucker, 6 players Friesen, each to game over against House Cats; a lobby test (pills, swap, ribbons); a pass-and-play curtain test with two people on one page in 5 players.
- [ ] Screenshots of each screen (lobby, bidding, nest, trump, partner, play, between, score sheet, game over, TV) at iPhone SE, a large phone, iPad portrait and landscape, laptop, and 200% text: `scripts/birdwatch-shots.mjs` into `screenshots/birdwatch/`.
- [ ] Run lint, typecheck, unit, e2e locally; open the PR; CI green.
