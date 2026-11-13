import XCTest

/// Screenshots of the sheets for a design review (before and after a change), written as PNGs to
/// `SHEET_SHOT_DIR` (`TEST_RUNNER_SHEET_SHOT_DIR` for xcodebuild) with names starting
/// `SHEET_SHOT_PREFIX`; `SHEET_SHOT_AX=1` runs at the largest accessibility text size. Skipped
/// without a directory, so a normal run never writes files.
@MainActor
final class SheetShotTests: XCTestCase {
    private var dir: URL?
    private var prefix = "shot"
    private var largestText = false

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SHEET_SHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("SHEET_SHOT_DIR not set")
        }
        dir = URL(fileURLWithPath: path, isDirectory: true)
        prefix = env["SHEET_SHOT_PREFIX"] ?? prefix
        largestText = env["SHEET_SHOT_AX"] == "1"
        try FileManager.default.createDirectory(at: dir!, withIntermediateDirectories: true)
    }

    private func launch(_ extra: [String], band: String = "adult") -> XCUIApplication {
        let app = XCUIApplication()
        var args = Live.arguments() + ["-uitest-reset", "-seed-people", "-age-band", band, "-no-tips"] + extra
        if largestText {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = args
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func save(_ name: String) {
        guard let dir else { return }
        Thread.sleep(forTimeInterval: 0.8)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent("\(prefix)-\(name).png"))
    }

    /// Shots of `sheet` from the top, then a page further down each time until it stops moving.
    private func scrolled(_ app: XCUIApplication, _ sheet: String, _ name: String, pages: Int = 5) {
        save("\(name)")
        let root = el(app, sheet)
        for page in 1..<pages {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            root.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.6)
            if XCUIScreen.main.screenshot().pngRepresentation == before { break }
            save("\(name)-\(page + 1)")
        }
    }

    /// Settings from the top, then each of its own pages that `pages` names.
    private func settings(_ app: XCUIApplication, _ name: String, pages: [String]) {
        XCTAssertTrue(el(app, "sheet-gear").waitForExistence(timeout: Live.t(15)), "no Settings")
        Thread.sleep(forTimeInterval: 1.5)
        scrolled(app, "sheet-gear", name, pages: 3)
        for page in pages {
            let row = el(app, "settings.page.\(page)")
            guard row.waitForExistence(timeout: Live.t(3)) else { continue }
            row.tap()
            Thread.sleep(forTimeInterval: 1)
            scrolled(app, "sheet-gear", "\(name)-\(page)", pages: 2)
            let back = el(app, "settings.back")
            if back.exists { back.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func testSettings() {
        let app = launch(["-stub-accounts", "signed-in", "-demo-kittens", "-show-gear"])
        settings(app, "settings", pages: ["quietHours", "account"])
    }

    func testSettingsGuest() {
        let app = launch(["-stub-accounts", "upgraded", "-show-gear"])
        settings(app, "settings-guest", pages: ["account"])
    }

    func testSettingsTeen() {
        let app = launch(["-show-gear"], band: "teen")
        settings(app, "settings-teen", pages: ["reminderTimes"])
    }

    func testSettingsKitten() {
        let app = launch(["-demo-kitten", "locked", "-show-gear"], band: "kitten")
        settings(app, "settings-kitten", pages: [])
    }

    func testTableMenu() {
        let app = launch(["-demo", "table"])
        let menu = el(app, "table.menu")
        XCTAssertTrue(menu.waitForExistence(timeout: Live.t(15)), "no table")
        menu.tap()
        XCTAssertTrue(el(app, "sheet-table-menu").waitForExistence(timeout: Live.t(5)), "no menu")
        save("table-menu")
        el(app, "menu.rules").tap()
        XCTAssertTrue(el(app, "sheet-rules").waitForExistence(timeout: Live.t(5)), "no How to play")
        save("table-menu-rules")
    }

    func testRules() {
        let app = launch(["-show-rules"])
        XCTAssertTrue(el(app, "sheet-rules").waitForExistence(timeout: Live.t(15)), "no How to play")
        Thread.sleep(forTimeInterval: 1.5)
        save("rules")
    }

    func testPeople() {
        let app = launch(["-show-people"])
        XCTAssertTrue(el(app, "sheet-people").waitForExistence(timeout: Live.t(15)), "no People")
        Thread.sleep(forTimeInterval: 1.5)
        save("people")
    }
}
