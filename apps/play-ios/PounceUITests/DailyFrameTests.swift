import XCTest

/// Frame times on the Daily Dish's screens (`docs/main-thread.md`), as `FrameRateTests` measures
/// a table: the Dish's board changing as a live one does (`-dish-autoplay`: tabs, progress, the TV
/// count), and the puzzle host with its clock running (the server's test game; needs a server
/// with `DAILY=on DAILY_TEST=on`). Each prints a `FRAMES` line, and fails on a main-thread hang
/// over 100 ms or app work over 8.3 ms in a frame (`Watchdog.timeFailures`), and, near the
/// reference's speed on a quiet machine, a main-thread frame over 16.7 ms.
@MainActor
final class DailyFrameTests: XCTestCase {
    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 12

    override func setUp() {
        continueAfterFailure = true
    }

    func testTheDishBoardHoldsTheFrameRate() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people", "-demo-streaks", "-demo-dish", "some", "-show-dish", "-dish-autoplay"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "screen-dish").waitForExistence(timeout: Live.t(20)), "no Dish")
        measure(app, "daily-dish")
    }

    func testThePuzzleHostHoldsTheFrameRate() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people", "-daily-test"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        let treat = el(app, "home.dish.test")
        guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Dish on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "daily-test-step").waitForExistence(timeout: Live.t(15)), "the test game never came up")
        measure(app, "daily-host")
    }

    private func measure(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let before = gameplayBaseline(app)
        // Only waiting: nothing reads the screen in the window.
        Thread.sleep(forTimeInterval: seconds)
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away", file: file, line: line) }
        let window = after - before
        let report = window.report(name) + String(format: " | host load %.2f per core", host.load)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-\(name)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(window.link.count, Int(seconds) * 20, "the screen hardly drew: \(report)", file: file, line: line)
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)", file: file, line: line) }
        if host.busy || !window.nearReference {
            print("FRAMES \(name): frames over 16.7 ms are reported, not enforced (\(host.busy ? "busy Mac" : "slow machine"))")
        } else {
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)", file: file, line: line)
        }
    }
}
