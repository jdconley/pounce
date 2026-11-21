import XCTest

/// Frame times on Cat Nap's puzzle screen (`docs/main-thread.md`), as `DailyFrameTests` measures
/// the host: today's quilt from a dev server with `DAILY=on`, marking itself (`-autoplay`: drags
/// paint a row "no cat" and clear it again, through the same input a finger runs, each a move to
/// the server) with the clock running and nothing reading the screen. Prints a `FRAMES` line, and
/// fails on a main-thread hang over 100 ms or app work over 8.3 ms in a frame, and, near the
/// reference's speed on a quiet machine, a main-thread frame over 16.7 ms.
@MainActor
final class CatNapFrameTests: XCTestCase {
    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 12

    override func setUp() {
        continueAfterFailure = true
    }

    func testCatNapHoldsTheFrameRateWhileMarking() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people", "-autoplay", "-settings.soundOn", "<false/>"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        let treat = el(app, "home.dish.cat-nap")
        guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Cat Nap on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "catnap.quilt").waitForExistence(timeout: Live.t(15)), "the quilt never came up")
        let before = gameplayBaseline(app)
        // Only waiting: nothing reads the screen in the window while the quilt marks itself.
        Thread.sleep(forTimeInterval: seconds)
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away") }
        let window = after - before
        let report = window.report("daily-cat-nap") + String(format: " | host load %.2f per core", host.load)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-daily-cat-nap"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(window.link.count, Int(seconds) * 20, "the screen hardly drew: \(report)")
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)") }
        if host.busy || !window.nearReference {
            print("FRAMES daily-cat-nap: frames over 16.7 ms are reported, not enforced (\(host.busy ? "busy Mac" : "slow machine"))")
        } else {
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)")
        }
    }
}
