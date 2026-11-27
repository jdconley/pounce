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

Record yours here as you go, as the Birdwatch iOS plan did.

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
