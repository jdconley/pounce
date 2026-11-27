import XCTest

/// Frame times on the Apple TV (`docs/main-thread.md`), the TV's `FrameRateTests`: the same rules,
/// read from the same watchdog (`Watchdog`, shared with `PounceUITests`).
///
/// Each test opens a TV table that plays itself (DEBUG `-demo tv-hit`/`tv-tiles`/`tv-shell`, a
/// fake socket sending a game's moves as a server would: turns, draws, the phones' aims, hits,
/// discards, lay-downs and plays) and measures `seconds` of it while the test only waits. Nothing
/// reads the screen in that window. Each test prints a `FRAMES` line.
///
/// It fails when:
/// - the table doesn't ask for the screen's top rate,
/// - the app's own work hung the main thread (over 100 ms near the reference's speed),
/// - any frame held over 8.3 ms of the app's own work (the 120 Hz budget, so a 60 Hz TV has
///   headroom),
/// - any table or main-thread frame took over 16.7 ms.
/// Time budgets fit the machine (`Watchdog.timeFailures`), and frames over 16.7 ms are enforced
/// only near the reference's speed on a quiet machine, as on the iPhone.
///
/// `scripts/frame-rate.sh PLATFORM=tvOS` runs these on an Apple TV simulator or a paired Apple TV.
@MainActor
final class FrameRateTVTests: XCTestCase {
    /// Seconds measured per table (`POUNCE_FRAMES_SECONDS`, `TEST_RUNNER_POUNCE_FRAMES_SECONDS`).
    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 20

    override func setUp() {
        continueAfterFailure = true
    }

    /// Cat Tower with six seats, the TV's busiest table: every seat laid down, long groups folded.
    func testCatTowerSixSeatsPlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-hit", speed: 1)
        app.launchArguments += ["-seats", "6"]
        app.launch()
        XCTAssertTrue(el(app, "table.deck").waitForExistence(timeout: Live.t(20)), "the Cat Tower table never came up")
        measure(app, as: "tv-cat-tower-6")
    }

    /// Toy Tumble with six boxes for a minute (spec §7, Review Focus 5): every box a House Cat's,
    /// toys gliding between position updates, junk and tricks flying between boxes.
    func testToyTumbleSixBoxesPlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-tumble", speed: 1)
        app.launchArguments += ["-seats", "6"]
        app.launch()
        XCTAssertTrue(el(app, "tumble.mini.5").waitForExistence(timeout: Live.t(20)), "the Toy Tumble table never came up")
        measure(app, as: "tv-toy-tumble-6", minimum: 60)
    }

    /// Tuna Tiles with four seats: a phone's draft growing on the rug, the play landing, draws.
    func testTunaTilesFourSeatsPlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-tiles", speed: 1)
        app.launchArguments += ["-seats", "4"]
        app.launch()
        XCTAssertTrue(el(app, "tiles.debug").waitForExistence(timeout: Live.t(20)), "the Tuna Tiles table never came up")
        measure(app, as: "tv-tuna-tiles-4")
    }

    /// The whole TV: home, a poster pressed on the remote, the lobby filling, then the six-seat
    /// Cat Tower table it starts, measured inside the shell (its backdrop and the paw's focus).
    func testShellHomeLobbyTablePlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-shell", speed: 1)
        app.launch()
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 20), "home never showed with Cat Tower focused")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.lobby.game").waitForExistence(timeout: Live.t(10)), "no lobby")
        // The lobby is live (its room came over the socket) before the first go-ahead.
        XCTAssertTrue(waitForFocus(app, "tv.lobby.changeGame"), "the empty lobby has no Change game focused")
        Live.releaseDemo()
        XCTAssertTrue(until(10) { !self.el(app, "tv.lobby.changeGame").exists }, "nobody sat down")
        Live.releaseDemo()
        XCTAssertTrue(el(app, "table.deck").waitForExistence(timeout: Live.t(20)), "the game never started")
        measure(app, as: "tv-shell")
    }

    /// Purrtrait's easel with six players (DEBUG `-demo tv-purrtrait`): a drawer's phone sends a cat
    /// stroke by stroke, 50 ms batches as a phone sends them, then the reveal and the next turn,
    /// over and over. The easel is layers in SwiftUI, so there's no SpriteKit table to ask for the
    /// top rate: the main thread's budget, its hangs and the display link's frames are what's held.
    func testPurrtraitEaselPlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-purrtrait", speed: 1)
        app.launchArguments += ["-seats", "6", "-settings.soundOn", "<false/>", "-tv.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "tv.purrtrait").waitForExistence(timeout: Live.t(20)), "the easel never came up")
        measure(app, as: "tv-purrtrait-6", table: false)
    }

    /// Tonight's board on a busy evening (DEBUG `-demo tv-board`): a result and a fresh board every
    /// 1.5 s, progress between, rows sliding in and cats leaping, and a run offered and watched
    /// halfway. SwiftUI only, so there is no table to ask for the top rate: the main thread's budget,
    /// its hangs and the display link's frames are what's held.
    func testBoardPlaysAtTheTopFrameRate() {
        let app = Live.demo("tv-board", speed: 1)
        // Silent on a Mac: speed 1 plays real sound.
        app.launchArguments += ["-settings.soundOn", "<false/>", "-tv.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "tv.board").waitForExistence(timeout: Live.t(20)), "the board never came up")
        XCTAssertTrue(el(app, "tv.board.game.box-fort").waitForExistence(timeout: Live.t(10)), "the board has no games")
        let before = gameplayBaseline(app)
        Thread.sleep(forTimeInterval: seconds / 2)
        // Halfway: Kid's run is offered, and the card comes up over the board.
        Live.releaseDemo()
        Thread.sleep(forTimeInterval: seconds / 2)
        measure(app, as: "tv-board", from: before, table: false)
    }

    // MARK: the gate

    private func measure(
        _ app: XCUIApplication, as name: String, from baseline: Watchdog? = nil, table: Bool = true, minimum: Double = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let seconds = max(self.seconds, minimum)
        let before = baseline ?? gameplayBaseline(app)
        // Only waiting: nothing reads the screen while the table plays.
        if baseline == nil { Thread.sleep(forTimeInterval: seconds) }
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away", file: file, line: line) }
        let window = after - before
        let report = window.report(name) + String(format: " | host load %.2f per core", host.load)
        print(report)
        for frame in (value(el(app, "watchdog.frames")) ?? "").split(separator: "\n") {
            print("FRAMES \(name) \(frame)")
        }
        let note = XCTAttachment(string: report)
        note.name = "frames-\(name)"
        note.lifetime = .keepAlways
        add(note)

        XCTAssertGreaterThan(window.screen, 0, report, file: file, line: line)
        if table {
            XCTAssertEqual(window.table, window.screen, "the table doesn't ask for the screen's top rate: \(report)", file: file, line: line)
            // It rests between moves (the view pauses), so a quarter of the window's frames at least.
            XCTAssertGreaterThanOrEqual(window.tableFrames.count, Int(seconds) * window.screen / 4, "the table hardly rendered while it played: \(report)", file: file, line: line)
        }
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)", file: file, line: line) }
        if window.hangs > window.appHangs {
            print("FRAMES \(name): \(window.hangs - window.appHangs) main-thread hang(s) the app's own work didn't fill: reported, not gated")
        }
        if host.busy || !window.nearReference {
            print("FRAMES \(name): frames over 16.7 ms are reported, not enforced: \(host.busy ? "the simulator's Mac is busy" : String(format: "this machine is %.2fx slower than the reference", window.slowdown))")
        } else {
            if table { XCTAssertEqual(window.tableFrames.slow, 0, "the table drew a frame over 16.7 ms: \(report)", file: file, line: line) }
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)", file: file, line: line)
        }
    }
}
