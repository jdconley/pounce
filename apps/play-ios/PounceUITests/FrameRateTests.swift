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
/// Time budgets fit the machine (`Watchdog.timeFailures`): on a phone or the reference Mac, no frame
/// over 8.3 ms of the app's own work and no hang over 100 ms that it filled; on a machine measured
/// slower (a CI virtual machine), the app's work at p95 within 8.3 ms times its slowdown and at p99
/// within three times that, and no hang over 250 ms times the slowdown that its work filled. Frames over 16.7 ms are enforced only near the
/// reference's speed and on a quiet machine: on a phone always.
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

    /// Cat Tower on Cards (`-demo controller`: the hit table with a TV showing it): the hand's
    /// first card up to the action row and back, and the last card along the hand.
    func testCatTowerCardsPlaysAtTheTopFrameRate() {
        play("controller", as: "cat-tower-cards", ready: "table.deck")
    }

    /// Tuna Tiles mid game (`-demo tiles`): the stash's first piece onto the rug's first set, and
    /// back to the stash, over and over.
    func testTunaTilesPlaysAtTheTopFrameRate() {
        play("tiles", as: "tuna-tiles", ready: "tiles.debug")
    }

    /// Tuna Tiles on Cards, my move (`-demo controller-tiles`: `tiles` with a TV showing it): the
    /// same drags, and each drop sends the draft to the TV.
    func testTunaTilesCardsPlaysAtTheTopFrameRate() {
        play("controller-tiles", as: "tuna-tiles-cards", ready: "tiles.debug")
    }

    /// Tuna Tiles off turn on Cards, then the turn coming (`-demo controller-tiles-off`, the House
    /// Cats held until 6 s into the window): stash drags along the stash alone, then the table
    /// opening around it, then the usual drags.
    func testTunaTilesTurnComingOnCardsPlaysAtTheTopFrameRate() {
        play("controller-tiles-off", as: "tuna-tiles-turn", ready: "tiles.debug", extra: ["-tiles-hold-bots"], release: 6)
    }

    /// Tuna Tiles' busiest table (`-demo tiles-late`: 25 sets, 22 pieces in the stash): each drop
    /// reflows the whole rug.
    func testTunaTilesLateTablePlaysAtTheTopFrameRate() {
        play("tiles-late", as: "tuna-tiles-late", ready: "tiles.debug")
    }

    // MARK: playing and the gate

    /// `release`: seconds into the window when a held demo goes on (`Live.releaseDemo`).
    private func play(
        _ demo: String, as name: String, ready: String, extra: [String] = [], release: TimeInterval? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let app = Live.demo(demo, speed: 1)
        app.launchArguments += ["-autoplay"] + extra
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
        if let release {
            Thread.sleep(forTimeInterval: min(release, seconds))
            Live.releaseDemo()
            Thread.sleep(forTimeInterval: max(seconds - release, 0))
        } else {
            Thread.sleep(forTimeInterval: seconds)
        }
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away", file: file, line: line) }
        let window = after - before
        let report = window.report(name) + String(format: " | host load %.2f per core", host.load)
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
        // It rests between drags (the view pauses), so a quarter of the window's frames at least.
        XCTAssertGreaterThanOrEqual(window.tableFrames.count, Int(seconds) * window.screen / 4, "the table hardly rendered while it played: \(report)", file: file, line: line)
        // The app's time budgets, as fits this machine (`Watchdog.timeFailures`).
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)", file: file, line: line) }
        if window.hangs > window.appHangs {
            print("FRAMES \(name): \(window.hangs - window.appHangs) main-thread hang(s) the app's own work didn't fill: reported, not gated")
        }
        if host.busy || !window.nearReference {
            print("FRAMES \(name): frames over 16.7 ms are reported, not enforced: \(host.busy ? "the simulator's Mac is busy" : String(format: "this machine is %.2fx slower than the reference", window.slowdown))")
        } else {
            XCTAssertEqual(window.tableFrames.slow, 0, "the table drew a frame over 16.7 ms: \(report)", file: file, line: line)
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)", file: file, line: line)
        }
    }
}
