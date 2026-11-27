# Purrtrait on iPhone, iPad and Apple TV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Purrtrait in the iOS app (draw on iPhone or iPad, or guess) and the Apple TV app (the easel), against the server plan's wire.

**Architecture:** PounceKit gets the wire types and a pure ink core (`Purrtrait/InkCodec.swift`: filtering, RDP simplification, op encoding and decoding, `compact`), shared by iOS and tvOS and unit-tested on macOS. Rendering is one cross-platform easel view (`PurrEaselView`, layer-backed: a bitmap layer of finished strokes rasterised off the main thread, plus a `CAShapeLayer` for the stroke in progress), used by the drawer's canvas on iOS (with touch input) and the TV's easel on tvOS. Not PencilKit, not SpriteKit. Ink encoding and decoding live in the socket layer, off the main thread.

**Tech Stack:** Swift 6, SwiftUI, Core Animation, Core Graphics, Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-11-26-purrtrait-design.md` (§4, §5, §6, §7, §9, §11). Wire: `docs/superpowers/plans/2026-11-26-purrtrait-server.md` "Wire contract", then the server session's `purrtrait-server-wire.md` and `apps/play-api/fixtures/protocol/purrtrait-*.json` once it lands.

## Global Constraints

- The main thread draws only; `swift scripts/main-thread-lint.swift` passes. Rasterising a full `inkSync`, encoding batches and decoding relayed ink run off the main thread; the main thread appends points and draws.
- 120 fps on ProMotion while drawing (coalesced touches, `preferredFrameRateRange` up to 120 while a finger is down), 60 on Apple TV. `FrameRateTests` gains a drawing case.
- The drawer's own lines draw locally on the frame they happen.
- Easel 3:4, grid 768 × 1024, colours 0-7 plus 8 (white eraser), widths 0-2 = 4, 10, 24 grid units; drop points under 2 units; RDP 1 unit; a batch every 50 ms and at stroke end; at most 25 messages a second. Apple Pencil works as a finger; pressure is ignored.
- No drawing on a guesser's phone. No word anywhere but the drawer's device before the reveal. No save, share, export or screenshot button. A shared phone's curtain comes down before the words.
- Copy fixed by the spec: "Starts on the TV", "Scan to join", "Scan the code on the TV.", "Look at the TV", "You draw next", "Waiting for the TV", "Easel full", "Got it", "Give up", "Undo", "Clear", tips "Pick one to draw", "No letters or numbers", "Tap who said it first", "Guess out loud". No emoji. Never the commercial game's name or category words.
- `x-pounce-games` adds `purrtrait` only in the build that draws it. The QR's `/e/` link opens the app only once `PURRTRAIT_APPLINKS` is on (server); add `/e/*` handling now, and `pounce-dev://e/<CODE>?near=<KEY>` for tests.
- Simulators named "Purrtrait <device>", muted with `defaults write com.conleychaos.play settings.soundOn -bool NO` (plus `tv.soundOn` on TV) before launch; deleted with the build output when done. Local server on port 8798 with `DEV_SERVER_GAMES=tiles,birdwatch,purrtrait`; never 8787 or 4343.
- Stay out of `apps/play-web` and `apps/play-api` (fixtures are read, not written).

## Rulings

Mine, open to JD's override.

1. **Codes are 5 + 3.** Room codes are five characters (`RoomCode`); the TV's typed fallback is the room code and the key's first three, eight in all (`room.near.code`, shown as given; the server's fix). Join keeps five tiles; when a code turns out to be a Purrtrait table's (a 403 on the probe), three more tiles appear with "Three more from the TV". An eight-character code goes on the socket as `near`.
2. **The palette** is ours and the web's (notes `purrtrait-ios-tv.md`): black #1A1426, red #FF3B4A, orange #FF9419, yellow #FFD400, green #2ECC5B, blue #2F80FF, purple #9B4DFF, brown #8B5A2B, eraser white. Brown over pink: animals and trees need it.
3. **One easel view, two hosts.** `PurrEaselView` (layers: a bitmap of finished strokes from the `InkRaster` actor, a `CAShapeLayer` for the live stroke, and one shape layer per stroke while its bitmap is on the way, so nothing blinks) is compiled into both apps. The phone's `PurrCanvasView` adds touches and a 120 Hz display link while a finger is down; the TV's `PurrInkFollower` feeds it from the room's `InkFeed`, building a whole `inkSync` off the main thread.
4. **Ink never touches SwiftUI state.** `RoomStore.ink` (`InkFeed`) is unobserved; the easel listens to it. The store drops a relay for any turn but the room's, and a new turn key empties it (the reveal keeps the picture up).
5. **What the drawer sees is what the finger made**, every point 2 units apart; what goes is each batch simplified (RDP, 1 unit). The TV's lines sit within a unit of the drawer's.
6. **The resend** (server wire): a clear, then every visible stroke with its own id, the final message `last: true`. The next stroke follows the highest id resent. Batches that never left (the socket was down) go again after the reconnect, in order. The drawer's device takes the room's `inkSync` only when it has no drawing of its own this turn (it was closed and came back); otherwise its own picture stands and its unsent batches catch the room up.
7. **`easel_full`** ends the stroke, drops what waits to go (the room would refuse it whole), shows "Easel full" over the easel and lights Clear, which then goes as a message of its own.
8. **403 to a phone.** URLSession never hands the app an upgrade's body, so a phone reads `x-pounce-error` when the server sends it (`not_near`, `removed`); without it, a 403 to a socket that brought a key (or a typed code) is `not_near`, and any other 403 is retried as before. The room's 4403 close (reason `removed`) on an open socket ends the visit with no reconnect. Asked of the server in the notes.
9. **The phone's lobby is its own screen** (`PurrLobbyView`): the TV does the joining, so no code chip, QR, invite, House Cat or seat ellipse for ten. The cats in a grid, the host's timer pills, "This phone" for pass and play, the host's tap on another cat removes it (asks first), Start at two with the TV on ("Waiting for the TV" otherwise). Mid-game the host removes a player from the paw menu.
10. **The shelf.** `GameCatalog.Availability.onTV`: the card is bright, wears "Starts on the TV", and a tap says "Pick it on the TV." (a tip points at it once). Nothing is made from the phone.
11. **Show on TV** is in the host's paw menu only, as "New TV" (the spec's path for a TV that came back as a new device). The lobby has none.
12. **The drawer's screen** puts the paw, the word and the clock in one row; the 3:4 easel takes the height that's left; colours across one row, widths, Undo and Clear in the next, Got it and Give up last. Give up asks first. Wide screens (iPad landscape) put the tools in a column beside an easel at full height. Text in the tools caps at XXXL so the SE fits at the largest size.
13. **The reveal shows on every phone** (the word is everyone's then) and on the TV across the easel. The TV holds the last reveal three seconds before game over.
14. **The TV has no SpriteKit scene for Purrtrait** (`TVRoom.Scene.purrtrait`); `PurrTVTable` draws in SwiftUI and the easel's layers, and marks itself gameplay for the watchdog. Its paw draws its own icon.
15. **Tips**: "Pick one to draw" (the word cards), "No letters or numbers" (the easel, learned by a stroke), "Tap who said it first" (Got it, after the easel's), "Guess out loud" (a guesser's "Look at the TV"), and "Pick it on the TV." (the shelf card).
16. **No video** in How to play for Purrtrait yet: four short sections.

## Review Focus

1. **A fast scribble on an iPhone SE (60 Hz):** no gaps, no hitches, the frame-rate test stays green. Test: `InkCodecTests.coalescedFastLineStaysWhole` and `FrameRateTests.drawing`.
2. **The Apple TV app relaunched mid-turn after an undo and a clear:** the same picture comes back from `inkSync`. Test: `PounceTVTests/PurrEaselTVTests.syncAfterUndoAndClear`.
3. **iPhone SE at the largest text size as the drawer:** easel, tools, Got it and Give up fit; nothing clips. Test: `PurrtraitShotTests` at AX XXXL with long names.
4. **iPad landscape as the drawer:** the 3:4 easel fills the height and the tools sit beside it. Test: shot test on iPad landscape.
5. **The drawer backgrounding the app mid-stroke:** the stroke ends; on return the canvas restores from `inkSync`. Test: `PurrDrawModelTests.backgroundEndsStroke`.

---

### Task 1: The wire and the ink codec in PounceKit

**Files:** Create `PounceKit/Sources/PounceKit/Protocol/PurrtraitModels.swift`, `PounceKit/Sources/PounceKit/Purrtrait/InkCodec.swift`; modify `Models.swift`, `GameEvent.swift`, `Messages.swift` (`ink`, `remove`, new `ErrorCode`s), `RoomSocket.swift` (`ink`, `inkSync`, `inkResend` decoded off the main thread), `GameCatalog.swift`, `RoomStore.swift`; tests `PurrtraitProtocolTests.swift`, `InkCodecTests.swift`.
- [ ] Tests first: every purrtrait fixture decodes and every client message encodes equal to its fixture; codec round trip; `compact` on "s,s,u,c,s" matches the server; a batch stays under 8 KB.
- [ ] Implement, `swift test --package-path PounceKit`, commit.

### Task 2: The easel view

**Files:** Create `Pounce/Purrtrait/PurrEaselView.swift` (compiled into iOS and tvOS), `PurrRaster.swift` (off-main rasteriser); tests.
- [ ] Tests: midpoint smoothing; finished strokes flatten into the bitmap; resize re-rasterises from the op log.
- [ ] Implement, commit.

### Task 3: The drawer's canvas and the guesser's screen on iOS

**Files:** Create `Pounce/Purrtrait/PurrDrawScreen.swift` (word cards, then word and timer, easel with touch input, palette, widths, Undo, Clear, Got it sheet, Give up, curtain), `PurrWatchScreen.swift` ("Look at the TV", whose turn, score, "You draw next"), `PurrDrawModel.swift` (PounceKit or app: stroke ids, batching, rate limit, `inkResend` reply), `PurrtraitStage.swift`; modify `TableScreen.swift`.
- [ ] Tests: `PurrDrawModelTests` (batches every 50 ms, 25 per second, resend replays with a leading clear, background ends the stroke); demo screenshots on SE, 17 Pro Max, iPad portrait and landscape, AX XXXL. Commit.

### Task 4: Joining, shelf, lobby, remove

**Files:** The `/e/<CODE>?near=` universal link and dev scheme, "Join with code" takes 5 or 8 characters, the shelf card "Starts on the TV" with a tip, lobby timer pills (host), the seat menu's Remove (host), `not_near` and `removed` state cards, Show on TV hidden at a Purrtrait table except the host's "new TV" path.
- [ ] UI test against the local server: a stale key is refused; a removed phone stays out. Commit.

### Task 5: Apple TV

**Files:** `PounceTV`: the Purrtrait poster on Home, the lobby with the join QR from `room.near` (refreshing every key) and the 8-character code, the easel screen (cats and scores left, drawer, timer and group right, the reveal), game over; tests `PurrEaselTVTests`.
- [ ] TV tests green on an Apple TV simulator, screenshots, commit.

### Task 6: Teaching, live games and the PR

**Files:** How to play page, tips (`UITips`), `PurrtraitLiveTests` (this phone plus a second simulator or the web harness at one table with the Apple TV simulator), `FrameRateTests.drawing`.
- [ ] Main-thread lint, PounceKit tests, iOS and tvOS builds, TV tests, live test; PR "Purrtrait on iPhone, iPad and the TV: draw on your phone, the TV shows it live"; notes in the shared notes folder; clean up simulators and build output.
