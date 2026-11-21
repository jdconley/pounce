import XCTest

/// Screenshots of every screen the Daily Dish touches: Home in the same states as
/// `HomeShotTests` (for before and after) with the Dish on it, the Dish screen (a few results,
/// all done, long names, the biggest text), and the puzzle host and its end screen against a server
/// with `DAILY=on DAILY_TEST=on`. Skipped unless the runner sets `DAILY_SHOTS_DIR`
/// (`TEST_RUNNER_DAILY_SHOTS_DIR`). An iPad takes each in portrait and landscape.
@MainActor
final class DailyShotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private static let states: [(String, [String], String)] = [
        ("home-new", ["-demo-streaks", "empty", "-demo-dish", "fresh"], "screen-home"),
        ("home-tables", ["-demo-streaks", "-demo-home", "-demo-dish", "some"], "screen-home"),
        ("home-done", ["-demo-streaks", "-demo-home", "calm", "-demo-dish", "done"], "screen-home"),
        ("big-text-home-tables", ["-demo-streaks", "-demo-home", "-demo-dish", "some"] + big, "screen-home"),
        ("dish", ["-demo-streaks", "-demo-dish", "some", "-show-dish"], "screen-dish"),
        ("dish-long", ["-demo-streaks", "-demo-dish", "long", "-show-dish"], "screen-dish"),
        ("big-text-dish", ["-demo-streaks", "-demo-dish", "some", "-show-dish"] + big, "screen-dish"),
    ]

    private var dir: String? {
        let dir = ProcessInfo.processInfo.environment["DAILY_SHOTS_DIR"]
        return dir?.isEmpty == false ? dir : nil
    }

    private var orientations: [UIDeviceOrientation] {
        UIDevice.current.userInterfaceIdiom == .pad ? [.portrait, .landscapeLeft] : [.portrait]
    }

    private func save(_ name: String) {
        guard let dir else { return }
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let suffix = pad ? (XCUIDevice.shared.orientation.isLandscape ? "-landscape" : "-portrait") : ""
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
    }

    func testShots() throws {
        guard dir != nil else { throw XCTSkip("no DAILY_SHOTS_DIR") }
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            for (name, args, screen) in Self.states {
                if pad, name.hasPrefix("big-text") { continue }
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 4) + ["-uitest-reset", "-seed-people"] + args
                app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
                app.launch()
                XCTAssertTrue(el(app, screen).waitForExistence(timeout: Live.t(15)), "no \(screen) for \(name)")
                Thread.sleep(forTimeInterval: 2.5)
                save(name)
                if name == "dish" {
                    el(app, "dish.tab.sniff").tap()
                    Thread.sleep(forTimeInterval: 1)
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 1)
                    save("dish-sniff-stats")
                }
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// The host and its end screen, playing the server's test game.
    func testHostShots() throws {
        guard dir != nil else { throw XCTSkip("no DAILY_SHOTS_DIR") }
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            for big in [false, true] {
                if big, UIDevice.current.userInterfaceIdiom == .pad { continue }
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 4) + ["-uitest-reset", "-seed-people", "-daily-test"] + (big ? Self.big : [])
                app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
                app.launch()
                let treat = el(app, "home.dish.test")
                guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Dish on \(Live.baseURL)") }
                treat.tap()
                let step = el(app, "daily-test-step")
                XCTAssertTrue(step.waitForExistence(timeout: Live.t(15)))
                step.tap()
                Thread.sleep(forTimeInterval: 1.5)
                save(big ? "big-text-host" : "host")
                for _ in 0..<12 where !el(app, "daily.end").exists {
                    if step.exists && step.isHittable { step.tap() }
                    Thread.sleep(forTimeInterval: 0.3)
                }
                XCTAssertTrue(el(app, "daily.end.place").waitForExistence(timeout: Live.t(15)))
                Thread.sleep(forTimeInterval: 2)
                save(big ? "big-text-end" : "end")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
