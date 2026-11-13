import XCTest

/// Sheets close the usual way: an X in the top trailing corner. A page inside a sheet goes back
/// with an arrow in the top leading corner, and the X stays where it was. No server is needed.
@MainActor
final class SheetCloseTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-age-band", "adult", "-no-tips"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    /// `control` sits in the top trailing corner of `sheet`: its right half, its first 120 points.
    private func assertTopTrailing(_ control: XCUIElement, of sheet: XCUIElement, _ what: String) {
        let c = control.frame, s = sheet.frame
        XCTAssertGreaterThan(c.midX, s.midX + s.width / 4, "\(what) isn't on the right: \(c) in \(s)")
        XCTAssertLessThan(c.minY - s.minY, 120, "\(what) isn't at the top: \(c) in \(s)")
        XCTAssertEqual(label(control), "Close", "\(what) isn't a close control")
    }

    private func assertTopLeading(_ control: XCUIElement, of sheet: XCUIElement, _ what: String) {
        let c = control.frame, s = sheet.frame
        XCTAssertLessThan(c.midX, s.midX - s.width / 4, "\(what) isn't on the left: \(c) in \(s)")
        XCTAssertLessThan(c.minY - s.minY, 120, "\(what) isn't at the top: \(c) in \(s)")
        XCTAssertEqual(label(control), "Back", "\(what) isn't a back control")
    }

    func testSettingsClosesWithTheXAndItsPagesGoBack() {
        let app = launch(["-show-gear"])
        let sheet = el(app, "sheet-gear")
        XCTAssertTrue(sheet.waitForExistence(timeout: Live.t(15)), "no Settings")
        let close = el(app, "gear.close")
        XCTAssertTrue(close.waitForExistence(timeout: Live.t(5)), "Settings has no close control")
        Thread.sleep(forTimeInterval: Live.pace(1))
        assertTopTrailing(close, of: sheet, "Settings' close")
        XCTAssertFalse(el(app, "settings.back").exists, "the Settings list has a back arrow")

        // A page inside Settings: back on the left, the X still on the right.
        let account = el(app, "settings.page.account")
        XCTAssertTrue(reveal(app, account, in: "sheet-gear"), "no Account row")
        account.tap()
        let back = el(app, "settings.back")
        XCTAssertTrue(back.waitForExistence(timeout: Live.t(5)), "the Account page has no back arrow")
        Thread.sleep(forTimeInterval: Live.pace(1))
        assertTopLeading(back, of: sheet, "the Account page's back")
        assertTopTrailing(close, of: sheet, "the Account page's close")
        back.tap()
        XCTAssertTrue(until(5) { !back.exists }, "back didn't return to the list")
        XCTAssertTrue(sheet.exists, "back closed Settings")

        close.tap()
        XCTAssertTrue(until(5) { !sheet.exists }, "the X didn't close Settings")
    }

    func testHowToPlayClosesWithTheX() {
        let app = launch(["-show-rules"])
        let sheet = el(app, "sheet-rules")
        XCTAssertTrue(sheet.waitForExistence(timeout: Live.t(15)), "no How to play")
        let close = el(app, "rules.close")
        XCTAssertTrue(close.waitForExistence(timeout: Live.t(5)), "How to play has no close control")
        Thread.sleep(forTimeInterval: Live.pace(1))
        assertTopTrailing(close, of: sheet, "How to play's close")
        close.tap()
        XCTAssertTrue(until(5) { !sheet.exists }, "the X didn't close How to play")
    }

    /// In a table's menu How to play is a page: back on the left returns to the menu.
    func testHowToPlayInTheTableMenuGoesBack() {
        let app = launch(["-demo", "table"])
        let menuButton = el(app, "table.menu")
        XCTAssertTrue(menuButton.waitForExistence(timeout: Live.t(15)), "no table")
        menuButton.tap()
        let menu = el(app, "sheet-table-menu")
        XCTAssertTrue(menu.waitForExistence(timeout: Live.t(5)), "no menu")
        let menuClose = el(app, "menu.close")
        XCTAssertTrue(menuClose.waitForExistence(timeout: Live.t(5)), "the menu has no close control")
        Thread.sleep(forTimeInterval: Live.pace(1))
        assertTopTrailing(menuClose, of: menu, "the menu's close")
        el(app, "menu.rules").tap()
        let rules = el(app, "sheet-rules")
        XCTAssertTrue(rules.waitForExistence(timeout: Live.t(5)), "no How to play")
        let back = el(app, "rules.close")
        Thread.sleep(forTimeInterval: Live.pace(1))
        assertTopLeading(back, of: rules, "How to play's back")
        back.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: Live.t(5)), "back didn't return to the menu")
        menuClose.tap()
        XCTAssertTrue(until(5) { !menu.exists }, "the X didn't close the menu")
    }
}
