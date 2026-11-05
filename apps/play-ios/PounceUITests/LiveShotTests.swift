import XCTest

/// Screenshots of the live table (spec §11.3) on the real Lock Screen and Dynamic Island, from a
/// local demo activity (`-demo-live-table`, Debug only; no server, no push). Skipped unless the
/// runner's environment names a folder:
///
///     TEST_RUNNER_POUNCE_SHOTS_DIR=/some/dir xcodebuild test ... -only-testing:PounceUITests/LiveShotTests
///
/// Shots land as `lock-<mine|theirs>.png`, `island-compact-<…>.png` and `island-expanded-<…>.png`.
/// The app points at a port nothing listens on, so it never reaches a dev server.
@MainActor
final class LiveShotTests: XCTestCase {
    private var dir = ""
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["POUNCE_SHOTS_DIR"], !dir.isEmpty else { throw XCTSkip("no POUNCE_SHOTS_DIR") }
        self.dir = dir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        continueAfterFailure = false
    }

    private func shot(_ name: String) throws {
        Thread.sleep(forTimeInterval: 2)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// The demo live table started in the foreground, then the app goes to the Home Screen.
    private func startDemo(_ whose: String) {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 10) + ["-uitest-reset", "-seed-people", "-demo-streaks", "-demo-live-table", whose]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = "http://localhost:8797"
        app.launch()
        XCTAssertTrue(el(app, "home.streak").waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
    }

    private func pressLock() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func run(_ whose: String) throws {
        startDemo(whose)
        try shot("island-compact-\(whose)")
        // A long press on the Island opens the expanded view.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
        try shot("island-expanded-\(whose)")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        pressLock()
        pressLock()
        try shot("lock-\(whose)")
        // Unlock again for the next run: swipe up from the bottom.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testMyMove() throws {
        try run("mine")
    }

    func testTheirMove() throws {
        try run("theirs")
    }
}
