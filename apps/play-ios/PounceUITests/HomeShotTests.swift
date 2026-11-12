import XCTest

/// Screenshots of Home in every state it has (`Art/screenshots/home-redesign/`), with no server:
/// a new player, tables with a turn waiting, tables with none, streak partners and a gift, the
/// sign-in card, the update card, a table behind an update, a child's device, a full shelf, and
/// the biggest text size. Skipped unless the runner sets `HOME_SHOTS_DIR`
/// (`TEST_RUNNER_HOME_SHOTS_DIR`). An iPad takes each state in portrait and landscape.
@MainActor
final class HomeShotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let states: [(String, [String])] = [
        ("new", ["-demo-streaks", "empty"]),
        ("tables", ["-demo-streaks", "-demo-home"]),
        ("tables-calm", ["-demo-streaks", "-demo-home", "calm"]),
        ("signin", ["-demo-streaks", "-signin-prompt"]),
        ("update", ["-demo-streaks", "-demo-update", "soft", "-age-band", "adult"]),
        ("locked", ["-demo-streaks", "-demo-update", "locked", "-age-band", "adult"]),
        ("under-13", ["-demo-streaks", "empty", "-age-band", "kitten"]),
        ("six-games", ["-demo-streaks", "-shelf", "six"]),
        ("big-text-new", ["-demo-streaks", "empty", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
        ("big-text-tables", ["-demo-streaks", "-demo-home", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ]

    func testShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["HOME_SHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("no HOME_SHOTS_DIR")
        }
        let only = ProcessInfo.processInfo.environment["HOME_SHOTS_ONLY"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [UIDeviceOrientation] = pad ? [.portrait, .landscapeLeft] : [.portrait]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            for (name, args) in Self.states where only?.contains(name) ?? true {
                // Big text on a phone only: one iPhone is enough for it.
                if pad, name.hasPrefix("big-text") { continue }
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 4) + ["-uitest-reset", "-seed-people"] + args
                app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
                app.launch()
                XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(15)), "no Home for \(name)")
                Thread.sleep(forTimeInterval: 2.5)
                let suffix = pad ? (orientation.isLandscape ? "-landscape" : "-portrait") : ""
                try? XCUIScreen.main.screenshot().pngRepresentation
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
