import XCTest

/// Screenshots of Cat Nap's puzzle screen against a dev server with `DAILY=on`: Home with its
/// treat, the fresh quilt, a run with marks and a clash, a hint's locked cat, and the end screen.
/// Skipped unless the runner sets `CATNAP_SHOTS_DIR` (`TEST_RUNNER_CATNAP_SHOTS_DIR`). An iPad
/// takes each in portrait and landscape; a phone also at the largest text size.
@MainActor
final class CatNapShotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private var dir: String? {
        let dir = ProcessInfo.processInfo.environment["CATNAP_SHOTS_DIR"]
        return dir?.isEmpty == false ? dir : nil
    }

    private func save(_ name: String) {
        guard let dir else { return }
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let suffix = pad ? (XCUIDevice.shared.orientation.isLandscape ? "-landscape" : "-portrait") : ""
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
    }

    private func cell(_ app: XCUIApplication, _ i: Int) -> XCUIElement { el(app, "catnap.cell.\(i)") }

    func testShots() throws {
        guard dir != nil else { throw XCTSkip("no CATNAP_SHOTS_DIR") }
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        for orientation in pad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            XCUIDevice.shared.orientation = orientation
            for big in pad ? [false] : [false, true] {
                let prefix = big ? "big-text-" : ""
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 4) + ["-uitest-reset", "-seed-people", "-settings.soundOn", "<false/>"] + (big ? Self.big : [])
                app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
                app.launch()
                let treat = el(app, "home.dish.cat-nap")
                guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Cat Nap on \(Live.baseURL)") }
                Thread.sleep(forTimeInterval: 2)
                save("\(prefix)catnap-home")
                treat.tap()
                XCTAssertTrue(el(app, "catnap.quilt").waitForExistence(timeout: Live.t(15)), "the quilt never came up")
                Thread.sleep(forTimeInterval: 2)
                save("\(prefix)catnap-fresh")

                let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'catnap.cell.'")).count
                let n = Int(Double(cells).squareRoot())
                // Two cats side by side (a clash), and a row marked "no cat" by a drag.
                for i in [0, 1] {
                    cell(app, i).tap()
                    cell(app, i).tap()
                }
                let row = n * (n - 1)
                cell(app, row).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: cell(app, row + n - 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
                Thread.sleep(forTimeInterval: 1.5)
                save("\(prefix)catnap-clash")

                let hint = el(app, "catnap.hint")
                hint.tap()
                Thread.sleep(forTimeInterval: 2)
                save("\(prefix)catnap-hint")
                for _ in 1..<n where !el(app, "daily.end").exists {
                    _ = until(10) { hint.isEnabled || self.el(app, "daily.end").exists }
                    if hint.isEnabled { hint.tap() }
                }
                XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
                Thread.sleep(forTimeInterval: 2.5)
                save("\(prefix)catnap-end")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
