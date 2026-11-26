# Birdwatch on iPhone, iPad and Apple TV: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Birdwatch, the 1.3 trick-taking game, playable in the iOS app (phone table, lobby, shelf) and on the Apple TV table, against the server merged in PR #156.

**Architecture:** PounceKit gets the wire types (`BirdView`, `BirdEvent`, `BirdAction`, room options, swap seats, the `houseCat` room event) and a derived `BirdTableModel`; `RoomStore` learns the third game the way it learned Tuna Tiles. The table is a new SpriteKit scene in `Pounce/Birdwatch/` (shared with the TV target, like `Pounce/Tiles/`), with the hand phases' controls (bid, nest, trump, partner) as SwiftUI panels over it in `BirdStage`, the iPhone-only shell. The TV runs the same scene as a screen: no hand, no controls. Clients never port the rules: every dim and enable comes from `playable`, `bidRange`, `partnerChoices` and `nestSize`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SpriteKit, Swift Testing (PounceKit), XCTest UI tests, XcodeGen. Server: `apps/play-api` (`wrangler dev`, `GAMES=tiles,birdwatch`).

**Spec:** `docs/superpowers/specs/2026-11-25-birdwatch-design.md` (§3 and §5 are this plan's), wire: `docs/superpowers/notes/2026-11-25-birdwatch-wire.md`, fixtures: `apps/play-api/fixtures/protocol/birdwatch-{server,client}-messages.json`.

## Global Constraints

- Game id `birdwatch`, display name "Birdwatch", 4 to 6 players, never the commercial game's name, its bird card, colours or wording, anywhere (code, comments, tests, docs, copy, commits).
- Suits are Tuna Tiles' toy suits: fish, mouse, feather, bell, same colours and glyphs (`ArtName.Tiles.glyph`), and never told apart by colour alone.
- `CardId` 0 to 56: suit `id / 14` in order fish, mouse, feather, bell; rank `id % 14 + 1`; 56 is the Bird. Counters 5 = 5, 10 and 14 = 10, 1 = 15, Bird = 20.
- The Bird card: bright, round, cartoon songbird on a white face with a "20" seed badge. Never black, never crow-shaped.
- Card backs: Cat Tower's violet paw back (`CardFaceFactory.back()`).
- VoiceOver: "10, fish, 10 points", "Bird, 20 points, top trump", "1, bell, 15 points"; cards that score nothing say just "7, mouse".
- Lobby pills: Official "1s out, Bird wild." Tucker "1s high, worth 15." Friesen "1s high, Bird follows suit."
- Main thread draws only: card faces are drawn off the main thread (`@concurrent`), prewarmed before the scene shows; no disk, Keychain or blocking calls outside `PounceKit/IO`.
- UI words: buttons one to three words, messages one short sentence, no emoji, tagline "Family game night, every night".
- Every screen fits iPhone SE, a large iPhone, iPad portrait and landscape, and the largest accessibility text size.
- Local runs are silent: `settings.soundOn` NO (and `tv.soundOn` on TV) before launch; UI tests pass `-settings.soundOn <false/>`.
- My own simulators, named "BW …", deleted when done; my own server on port 8791, never 8787 or 4343.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings on gaps (mine, open to JD's override)

1. **TV at the table: hand only, no switch.** Spec §5.6 says phones show only their own hand and the phase controls while a TV shows the table. Unlike Cat Tower and Tuna Tiles there is no Cards/Table switch: the phone draws the hand, the phase panels and one status line ("Mia's turn", "Your turn").
2. **Phase controls are SwiftUI panels over the scene** (bid, nest Done, trump, partner, the between-hands summary, the score sheet), so they get Dynamic Type, VoiceOver and buttons for free. The hand, the cats, the sill and the score strip are SpriteKit.
3. **Home's table card can't show the rule set yet.** The server's table list (`/v1/tables`) carries no options. The card shows "Birdwatch" like any game. Recorded for the server as a follow-up; nothing here works around it.
4. **Shelf availability.** Birdwatch is `.available` in `GameCatalog` (the brief: on the shelf). Production's `GAMES` doesn't list it yet, so a create there is a 400. Merging this before the flag flips puts a card on TestFlight that can't deal; the manager decides the order. The create failure already shows the shelf's "couldn't make it" shake.
5. **Partner mark privacy.** The mark (a small heart badge on your own cat chip and a line over the hand: "You're the partner") is drawn only from `youArePartner`, which only the holder's device gets, and on a shared phone only while that seat's hand is face up after its curtain. The TV never has `youArePartner`. The table shows a partner only from `view.partner` (set by the server once the called card is played).
6. **Bidding's long press** raises by 5 every 0.15 s after a 0.4 s hold, up to `bidRange.max`. The big number starts at `bidRange.min`. "Bid" sends the number shown.
7. **Trump hint ring** goes on the suit this seat holds most of (ties: the higher count of counters, then suit order).
8. **Hand sort:** by suit (fish, mouse, feather, bell) with trump last (rightmost) once named, the Bird with trump; within a suit low to high by the rule set's rank order (1 above 14 in Tucker and Friesen).
9. **Five players' score strip:** one chip per seat (each player is their own side). Four and six: one chip per team, coloured by the team ribbon.
10. **Team ribbons:** team 0 orange, team 1 teal, team 2 magenta (Palette). In a five-player game no ribbons until the partner is known; then the bid winner's and partner's cats share a gold ribbon.
11. **Cat Tower's House Cat takeover** (`left: true` seats, `houseCat` event) shows as a House Cat with the leaver's name and a small "left" mark; a pill "Mia left. A House Cat plays on." floats down.
12. **Coach marks** (first Birdwatch hand per person): the bid sign (bidding), the dimmed cards (first play turn with any card dimmed), the trump badge (first trick after trump is named), the partner mark (five players, the partner's own screen).
13. **How to play** for Birdwatch is one sheet with the rule-set pills at its top, defaulting to the table's rule set (or Official from Home), and four short sections per rule set. No video in 1.3.
14. **Lobby Start** follows the game's seat range from `GameCatalog`: Birdwatch lights Start only with 4 to 6 cats seated; "Start with 4?" closes open seats only when 4 or more are seated.
15. **Swap seats** in the seat menu (host only, Birdwatch only, any two filled or open seats): tap "Swap seats", then tap the other cushion.

## Review Focus

- A five-player partner's identity reaching the screen early: the TV, another phone, or a shared phone before its curtain. Tests: `BirdTableModelTests.partnerMarkOnlyBehindCurtain`, `BirdSceneTVTests.noPartnerBeforeCalledCardPlayed`.
- A 17-card hand on iPhone SE (5 players, Tucker, bid winner with the nest): cards overlap but every card keeps its numeral and suit visible and tappable. Test: `BirdLayoutTests.seventeenCardsFitSE`.
- A refused move (`must_follow`, `not_your_turn`) or a dropped socket mid-bid: the card snaps back, controls unlock, nothing sticks. Test: `RoomStoreBirdwatchTests.refusedPlayUnlocks`.
- A reconnect or cold open mid-hand in every phase (nest, trump, partner, between, over): the right panel shows from the snapshot alone. Test: `BirdTableModelTests.panelFromSnapshot` over every fixture.
- Long names and 3-digit negative scores in the score strip and summary on SE at the largest text size. Test: the UI shot test `BirdwatchShotTests` at accessibility XXXL with "Clementine" names and -180 scores.

---

### Task 1: The wire in PounceKit

**Files:**
- Create: `PounceKit/Sources/PounceKit/Protocol/BirdwatchModels.swift`
- Modify: `Protocol/Models.swift` (`RoomView.options`, `RoomView.birdwatch`, `isBirdwatch`, `liveTurn`, `isOut`; `SeatView.left`), `Protocol/GameEvent.swift` (`RoomEvent.birdwatch`, `.houseCat`), `Protocol/Messages.swift` (`ClientMessage.actBirdwatch`, `.setOptions`, `.swapSeats`; new `ErrorCode`s), `Protocol/TilesModels.swift` (`GameID.birdwatch`), `Games/GameCatalog.swift` (entry), `Store/TurnEpoch.swift`, `Store/TableIntent.swift` (`.birdwatch(BirdEvent, seq:)`), `Store/RoomStore.swift` (`actBirdwatch`, fold turn/status/houseCat)
- Test: `PounceKit/Tests/PounceKitTests/BirdwatchProtocolTests.swift`, `RoomStoreBirdwatchTests.swift`, `Fixtures.swift` (`birdwatchServerMessages`, `birdwatchClientMessages` from the shared files)

**Interfaces (produces):**
- `public typealias BirdCardID = Int`; `public enum BirdSuit: String, Codable, CaseIterable { fish, mouse, feather, bell }`
- `public enum BirdCard: Hashable { case bird; case suited(BirdSuit, rank: Int) }` with `init?(id:)`, `id`, `static let birdID = 56`, `points: Int`
- `public enum BirdRules: String, Codable, CaseIterable { official, tucker, friesen }`
- `public enum BirdPhase: String, Codable { bidding, nest, trump, partner, play, between, over }` (unknown decodes fail: a protocol bump)
- `public struct BirdView: Codable, Equatable, Sendable` with every field of the wire note's `BirdView`, `hands: [Seat: [BirdCardID]]` via `StringKeyedSeats`, optional choice fields
- `public struct BirdHandResult`, `BirdTrickCard { seat, card }`, `BirdLastTrick { cards, winner }`, `BirdHigh { seat, amount }`, `BirdBidRange { min, max, step }`
- `public enum BirdEvent: Codable, Equatable, Sendable` cases: `dealt(hand:dealer:handCounts:hands:)`, `bid(seat:amount:)`, `passed(seat:)`, `bidWon(seat:amount:)`, `nest(seat:cards:)`, `putBack(seat:count:cards:)`, `trump(seat:suit:)`, `called(seat:card:)`, `turn(seat:)`, `played(seat:card:)`, `partner(seat:)`, `trick(winner:cards:points:)`, `handOver(result:putBack:)`, `gameOver(winners:scores:reason:)`
- `public enum BirdAction: Encodable, Equatable, Sendable`: `bid(Int)`, `pass`, `nest([BirdCardID])`, `trump(BirdSuit)`, `partner(BirdCardID)`, `play(BirdCardID)`, `forfeit`
- `public struct RoomOptions: Codable, Equatable { var rules: BirdRules? }`
- `RoomStore.actBirdwatch(seat:_:) -> Bool`, `RoomStore.Move.birdwatch`, `RoomStore.houseCatNotice: ForfeitNotice?` (seat and serial)

- [ ] **Step 1:** Tests: every message in both birdwatch fixture files decodes (server) or encodes byte-for-byte equal as JSON objects (client: `setOptions`, `swapSeats`, every `act`); `snapshot-five-you-are-partner` has `youArePartner == 3`; `snapshot-over-left` seat 0 is `.bot` with `left == true`; `BirdCard(id: 56) == .bird`, `BirdCard(id: 13) == .suited(.fish, rank: 14)`, points of ids 4, 9, 13, 0, 56 are 5, 10, 10, 15, 20; Cat Tower and tiles fixtures still decode unchanged.
- [ ] **Step 2:** Run `swift test --package-path PounceKit --filter Birdwatch`: fails (types missing).
- [ ] **Step 3:** Implement the types; `RoomView.liveTurn` reads `birdwatch.turn` while its status is playing; `isOut` is false for every Birdwatch seat (takeover, not forfeit); `TurnEpoch` keys on `birdwatch.hand`, `phase`, `turn`, `trick.count`, `status`.
- [ ] **Step 4:** RoomStore tests: `actBirdwatch` sends `{"t":"act","seat":1,"action":{"type":"play","card":13}}`, locks until the next snapshot; a `must_follow` error yields `.rejected(.mustFollow)` and unlocks (`refusedPlayUnlocks`); a `turn` event folds `birdwatch.turn`; `gameOver` folds status `over`; `houseCat` bumps `houseCatNotice`. Run, see them pass.
- [ ] **Step 5:** `GameCatalog.birdwatch` (`"birdwatch"`, "Birdwatch", pitch "Bid, call trump, take tricks.", 4...6, art `game-birdwatch`, tint `.lime`, available, no video); `GameCatalogTests` and `AppVersionTests` expect `cat-tower,tiles,birdwatch` (and `,dish` on iOS). Every request path already reads `ClientHeaders` (app, socket, widgets, notify): grep to confirm, and fix any that doesn't.
- [ ] **Step 6:** `swift test --package-path PounceKit` all green. Commit.

### Task 2: The table model

**Files:**
- Create: `PounceKit/Sources/PounceKit/Store/BirdTableModel.swift`, `PounceKit/Sources/PounceKit/Layout/BirdLayout.swift`
- Modify: `Store/LobbyPlan.swift`, `Store/TableModel.swift` (game-aware seat range), `Store/PassAndPlay.swift` (birdwatch's turn through `TableModel.currentSeat`/`isMyTurn` via `liveTurn`)
- Test: `BirdTableModelTests.swift`, `BirdLayoutTests.swift`, `LobbyPlanTests.swift` additions

**Interfaces (produces):**
- `public struct BirdTableModel { init?(room:) ; view; mySeats; isMultiSeat; isLive; currentSeat; isMyTurn; bottomSeat(revealed:) -> Seat?; barSeats(bottom:) -> [Seat]; hand(_ seat:) -> [BirdCardID]? (sorted, rule 8); playable(_ seat:) -> Set<BirdCardID>; sides -> [[Seat]]; side(of:) -> Int?; ribbon(of:) -> Int? (rule 10); panel(for seat:) -> BirdPanel?; partnerMark(for seat:, revealed:) -> Bool; trumpHint(_ seat:) -> BirdSuit?; label(_ card:) -> String; standings -> [Seat]; forfeitSeat(shown:) }`
- `public enum BirdPanel: Equatable { case bid(BirdBidRange), nest(count: Int, fromNest: [BirdCardID]), trump(hint: BirdSuit?), partner(choices: [BirdCardID]), waiting(phase: BirdPhase, seat: Seat) }`
- `public struct BirdLayout` (phone portrait, iPad, TV): `seats` points around the window, `sill` rect, `strip` rect, `hand` frame and `cardWidth(count:)`, `handSlots(count:width:) -> [CGPoint]`
- `TableModel.seatRange: ClosedRange<Int>` (from `GameCatalog.entry(id: room.gameId)`), `minPlayers` instance-level; `startBlock`, `canStart`, `startClosingOpenSeats` use it

- [ ] **Step 1:** Tests over the fixtures: `panelFromSnapshot` (bidding-your-move gives `.bid(70...120 step 5)`, nest-bid-winner `.nest(count: 5, …)`, trump-bid-winner `.trump(hint:)`, five-partner-call `.partner`, watching ones `.waiting`); `hand` sorts with trump last and the Bird with trump; `ribbon` 4p `[0,1,0,1]`, 6p `[0,1,2,0,1,2]`, 5p nil until `partner` set; `partnerMarkOnlyBehindCurtain` (`youArePartner` seat 3 on a two-seat phone: mark only when `revealed == 3`); `label(13) == "14, fish, 10 points"`, `label(56) == "Bird, 20 points, top trump"`, `label(6) == "7, fish"`; lobby: a Birdwatch room with 3 seated + 1 open has no `startClosingOpenSeats`, 4 seated + 2 open does; Cat Tower unchanged at 2.
- [ ] **Step 2:** Layout tests: `seventeenCardsFitSE` (width 375: 17 cards, each visible strip at least 22 pt and the last card whole), 9 cards on a 393 pt phone don't overlap more than half a card, iPad landscape puts the window left of nothing (centred), TV 1920×1080 has no hand.
- [ ] **Step 3:** Implement; run `swift test --package-path PounceKit`. Commit.

### Task 3: Card faces and art

**Files:**
- Create: `Pounce/Birdwatch/BirdCardFactory.swift`, `Art/prompts/birdwatch/{bird,feeder,game-birdwatch}.txt`, imagesets `bird-card`, `bird-feeder`, `game-birdwatch` in `Pounce/Resources/Assets.xcassets`, manifest entries
- Modify: `Pounce/Design/ArtName.swift` (`ArtName.Bird`), `Art/manifest.json`

**Interfaces (produces):** `@MainActor final class BirdCardFactory { static let shared; static let cardSize = CGSize(width: 64, height: 92); func face(_ id: BirdCardID) -> SKTexture; func back() -> SKTexture; func prewarm() async }`. Faces are drawn in `@concurrent` code: Cat Tower's chunky card (rounded body in the suit's `TilePalette` colour, thick ink rim, big white outlined numeral top-left and centred, the toy glyph), a seed badge (gold seed, the value in ink) on counters; the Bird face white with the bird art and a "20" badge.

- [ ] **Step 1:** Generate the Bird (round songbird, saturated sky blue and sunny yellow with an orange beak, a white face card fits it), the feeder (nest pile icon) and the shelf cover with `Art/tools/gen.sh`, cut with `cut.sh`, into the catalog at @2x/@3x; `scripts/check-assets.sh` passes.
- [ ] **Step 2:** The style check: a debug `-bird-sheet` overlay draws 14, 1, 5 and the Bird at the width a 15-card hand gets on a 393 pt phone (BirdLayout's `cardWidth(count: 15)`); screenshot it to `Art/screenshots/birdwatch/cards.jpg` before using the faces anywhere else.
- [ ] **Step 3:** Commit.

### Task 4: The phone table scene

**Files:**
- Create: `Pounce/Birdwatch/BirdScene.swift` (nodes, redraw, intents), `BirdSeatNode.swift` (cat, count bubble, ribbon, dealer chip, bid sign, partner heart, "left" mark), `BirdHandNode.swift` (the fan, lift, dim, drag), `BirdInput.swift`, `BirdAnimations.swift` (deal, play to sill, trick sweep to winner, nest fly-in glow, bid sign pop), `BirdAccessibility.swift`, `BirdTableView.swift` (SpriteView host)
- Modify: `Pounce/App/Autoplay.swift` (`BirdScene: Autoplaying`: plays the first playable card, bids minimum or passes, discards the first `nestSize` non-counters, picks the hint suit, calls the first choice)

**Interfaces:** `final class BirdScene: SKScene { init(store: RoomStore); var onMenu, onGameOver: ([Seat]) -> Void, onShownSeat: (Seat?) -> Void, onTipSpots: ([String: CGRect]) -> Void, onScores: () -> Void; var handOnly: Bool (a TV shows the table); var selectedDiscard: Set<BirdCardID> (nest phase); func enqueue(_ TableIntent); func refresh(); func reconcileFromStore() }`. `isScreen` from the store: TV arrangement, no hand, no input.

- [ ] **Step 1:** Scene renders each fixture snapshot without a hand for a screen (`PounceTVTests/BirdSceneTVTests.noHandOnScreen`, `noPartnerBeforeCalledCardPlayed` with `snapshot-five-partner-hidden` vs `-shown`).
- [ ] **Step 2:** Play: tap lifts, tap again plays (`actBirdwatch(.play)`); drag onto the sill plays; dimmed cards (not in `playable`) wiggle on tap and play nothing; the provisional card flies to the sill, snaps back on `.rejected`.
- [ ] **Step 3:** Events animate: `played` from another seat flies a card from its cat to the sill; `trick` sweeps the sill to the winner and bumps the strip; `bid`/`passed` pop the sign; `dealt` deals face down then flips this seat's hand; `nest` flies the nest cards into the bid winner's hand glowing; `partner` adds the partner's ribbon with a flourish; `handOver` hands to the stage's summary.
- [ ] **Step 4:** VoiceOver elements: each card (label from `BirdTableModel.label`, "dimmed" trait not enabled when not playable, hint "Double tap to play"), each seat ("Mia, 7 cards, bid 85, team orange"), the sill ("Trick: 10 fish by Mia, …"), trump badge ("Trump: bell").
- [ ] **Step 5:** Build for iOS; demo screenshots. Commit.

### Task 5: The stage, phase panels and pass-and-play

**Files:**
- Create: `Pounce/Birdwatch/BirdStage.swift` (shell, curtain reuse `TilesCurtain`-style, pills, menu sheet with forfeit, game over), `BirdPanels.swift` (bid, nest bar, trump, partner picker), `BirdScoreSheet.swift` (score strip's sheet: hand-by-hand table), `BirdSummary.swift` (between hands), `BirdDemo.swift` (iPhone-only demo sockets from the fixtures: `-demo bird-bid|bird-nest|bird-trump|bird-partner|bird-play|bird-five|bird-six|bird-between|bird-over|bird-curtain|bird-tv`)
- Modify: `Pounce/Shell/TableScreen.swift` (stage switch), `Pounce/App/DemoMode.swift`, `project.yml` (TV target compiles `Pounce/Birdwatch` minus `BirdStage`, `BirdPanels`, `BirdScoreSheet`, `BirdSummary`, `BirdDemo`), `.github/workflows/ios.yml` and `scripts/distribute.swift` TV filters

- [ ] **Step 1:** Bidding panel: the big number on a sign, "+5" (long press: rule 6), "Bid" (orange), "Pass" (violet); others' signs on their cats. Nest: the cards glow in the hand, tap to mark for putting back (they drop and dim), a bar "Put back 3" turning into "Done" at the right count. Trump: four big suit buttons with glyph and name, hint ring. Partner: a sheet of `partnerChoices` by suit rows, trump's row first. Waiting: one line ("Mia is bidding").
- [ ] **Step 2:** The curtain comes down before every reveal on a shared phone (the store's `PassAndPlay`), covering hand and panels; the partner mark draws only after it.
- [ ] **Step 3:** Between hands: the summary card (bid, made or missed, each side's points this hand, totals) for the ~6 s pause. Over: places, Play again, Home.
- [ ] **Step 4:** With a TV (`room.screen == true`): `scene.handOnly = true`, a status line on top, panels as usual.
- [ ] **Step 5:** Demo screenshots on SE, 17 Pro Max, iPad portrait and landscape, and AX XXXL into `Art/screenshots/birdwatch/`. Commit.

### Task 6: Shelf, lobby and Home

**Files:** Modify `Pounce/Shell/LobbyView.swift` (rule pills, team ribbons on cushions, start range), `Pounce/Shell/SeatMenu.swift` users (Swap seats), `Pounce/Shell/HomeView.swift` (demo tables), `Pounce/Shell/GameCard.swift` if the shelf needs a third card's layout; tests `PounceUITests/BirdwatchLobbyTests.swift`

- [ ] **Step 1:** Rule pills above the start row: three pills (host taps, sends `setOptions`; guests see them read-only), one line under the chosen one. They wiggle on a refused `setOptions`.
- [ ] **Step 2:** Ribbons: a small coloured ribbon under each filled cushion's name tag by its team (4p seats 0/2 and 1/3, 6p 0/3, 1/4, 2/5, counted after compaction: compute from the filled seats in order, as the server will).
- [ ] **Step 3:** Swap seats: host-only menu item on any human, bot or open seat; picks a second seat; sends `swapSeats`.
- [ ] **Step 4:** UI test: create a Birdwatch table on the local server, add 3 House Cats, Start lights at 4, tap Tucker, swap two seats. Commit.

### Task 7: Apple TV

**Files:** Modify `PounceTV/App/TVRoom.swift` (`.birdwatch(BirdScene)`), `PounceTV/Shell/TableHost.swift`, `PounceTV/App/TVModel.swift` (`changeGame` cycles three games), `PounceTV/Shell/HomeView.swift` (three posters, lime tint), `PounceTV/Shell/LobbyView.swift` (rule set name, ribbons), `PounceTV/App/TVStandings.swift` (birdwatch scores by side), `PounceTV/App/TVTablePreview.swift` and `TVDemo.swift` (`tv-birdwatch`); tests `PounceTVTests/BirdSceneTVTests.swift`

- [ ] **Step 1:** TV arrangement: cats in an arc across the top and sides, the sill in the middle, trump badge and high-bid sign at its corner, the score strip along the bottom, the turn banner. No hand ever.
- [ ] **Step 2:** TV unit tests (Task 4 step 1) green on an Apple TV simulator; build PounceTV for tvOS. Screenshot `tv-table.jpg`, `tv-lobby.jpg`. Commit.

### Task 8: Teaching, How to play, accessibility pass

**Files:** Modify `Pounce/Shell/HowToGuide.swift`, `HowToPlaySheet.swift` (birdwatch with rule pills), `PounceKit/Sources/PounceKit/Tutorial/Coach.swift` (Birdwatch tips), `Pounce/Shell/CoachMark.swift`; tests in `PounceKitTests/CoachTests.swift`

- [ ] **Step 1:** How to play text per rule set (spec §4 in our words, terse). Coach tips per ruling 12, each shown once per person, dismissed by use or tap.
- [ ] **Step 2:** Dynamic Type at AX5 on SE across panels and summary; fix clipping. Commit.

### Task 9: Live games and the PR

**Files:** Create `PounceUITests/BirdwatchLiveTests.swift` (4, 5 and 6 players: this phone plus House Cats, autoplay to game over against the local server at speed 10), `BirdwatchShotTests.swift`; modify `README.md` (app's: Birdwatch demos, `-demo bird-*`), `scripts/ui-tests.sh` if it pins the server's games.

- [ ] **Step 1:** Run each live test against `DEV_SERVER_PORT=8791 DEV_SERVER_GAMES=tiles,birdwatch DEV_SERVER_SPEED=10`; all reach the game over screen.
- [ ] **Step 2:** `swift scripts/main-thread-lint.swift`, PounceKit tests, iOS build-for-testing, tvOS build, TV unit tests.
- [ ] **Step 3:** PR "Birdwatch on iPhone, iPad and the TV: bid, call trump, take tricks", screenshots, notes for the web session in the shared notes folder. Clean up simulators and build output.
