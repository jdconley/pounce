import XCTest

/// Frame times while playing (`docs/main-thread.md`): the rule is no gameplay frame over 16.7 ms,
/// and no more than 8.3 ms (a 120 Hz frame) of the app's own main-thread work in any frame.
///
/// Each test opens a demo table that plays itself (DEBUG `-autoplay`: drags out and back, a frame
/// at a time, through the same code a finger runs) and measures `seconds` of it while the test
/// only waits. Nothing reads the screen in that window: a UI test's query snapshots the
/// accessibility tree on the main thread and costs the app frames it wouldn't otherwise drop (on
/// the simulator, 19 to 22 frames over 16.7 ms in 15 s of querying every half second, against
/// none without). Each test prints a `FRAMES` line: the table's rendered frames, the main
/// thread's (the watchdog's display link), the app's work per frame, and hangs.
///
/// It fails when:
/// - the table doesn't ask for the screen's top rate (120 on ProMotion),
/// - the main thread hung over 100 ms,
/// - any frame held over 8.3 ms of the app's own work (its `FrameWork` pieces, in CPU time),
/// - any table or main-thread frame took over 16.7 ms.
/// On a Mac so busy that the simulator itself is held up (a load average over half its cores) the
/// last two are reported, not enforced: frames slip with none of the app's work in them, and the
/// main thread lands on efficiency cores, where the same work takes two to three times the CPU
/// time. On a phone, or a quiet Mac, they are enforced.
///
/// `scripts/frame-rate.sh` runs these on a simulator or a plugged-in iPhone (the 120 Hz numbers).
@MainActor
final class FrameRateTests: XCTestCase {
    /// Seconds measured per table (`POUNCE_FRAMES_SECONDS`, `TEST_RUNNER_POUNCE_FRAMES_SECONDS`).
    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 20

    override func setUp() {
        continueAfterFailure = true
    }

    /// Cat Tower's hit table (`-demo hit`): the hand's first card into the laid zone, and the last
    /// card along the hand, over and over.
    func testCatTowerPlaysAtTheTopFrameRate() {
        play("hit", as: "cat-tower", ready: "table.deck")
    }

    /// Tuna Tiles mid game (`-demo tiles`): the stash's first piece onto the rug's first set, and
    /// back to the stash, over and over.
    func testTunaTilesPlaysAtTheTopFrameRate() {
        play("tiles", as: "tuna-tiles", ready: "tiles.debug")
    }

    /// Tuna Tiles' busiest table (`-demo tiles-late`: 25 sets, 22 pieces in the stash): each drop
    /// reflows the whole rug.
    func testTunaTilesLateTablePlaysAtTheTopFrameRate() {
        play("tiles-late", as: "tuna-tiles-late", ready: "tiles.debug")
    }

    // MARK: playing and the gate

    private func play(_ demo: String, as name: String, ready: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = Live.demo(demo, speed: 1)
        app.launchArguments += ["-autoplay"]
        app.launch()
        XCTAssertTrue(el(app, ready).waitForExistence(timeout: Live.t(20)), "the \(name) table never came up", file: file, line: line)
        // Cat Tower's first table asks about notifications; out of the way, as a player would.
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            _ = notNow.waitForNonExistence(timeout: 3)
        }
        let before = gameplayBaseline(app)
        // Only waiting: nothing reads the screen while the table plays (its first drag starts 3 s
        // after the table appears, once the baseline is taken).
        Thread.sleep(forTimeInterval: seconds)
        let load = Host.loadPerCore()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away", file: file, line: line) }
        let window = after - before
        let report = window.report(name) + String(format: " | host load %.2f per core", load)
        print(report)
        // What the slow frames held (the app's own work, or none), read once, after the window.
        for frame in (value(el(app, "watchdog.frames")) ?? "").split(separator: "\n") {
            print("FRAMES \(name) \(frame)")
        }
        let note = XCTAttachment(string: report)
        note.name = "frames-\(name)"
        note.lifetime = .keepAlways
        add(note)

        XCTAssertGreaterThan(window.screen, 0, report, file: file, line: line)
        XCTAssertEqual(window.table, window.screen, "the table doesn't ask for the screen's top rate: \(report)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.tableFrames.count, Int(seconds) * window.screen / 2, "the table hardly rendered while it played: \(report)", file: file, line: line)
        XCTAssertFalse(window.hangs > 0, "the main thread hung during gameplay: \(report)", file: file, line: line)
        if load > Host.busyLoadPerCore {
            print("FRAMES \(name): the host is busy (load \(String(format: "%.2f", load)) per core), so frame and work times are reported, not enforced")
        } else {
            XCTAssertEqual(window.workOver, 0, "a frame held over 8.3 ms of the app's own work: \(report)", file: file, line: line)
            XCTAssertEqual(window.tableFrames.slow, 0, "the table drew a frame over 16.7 ms: \(report)", file: file, line: line)
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)", file: file, line: line)
        }
    }
}
