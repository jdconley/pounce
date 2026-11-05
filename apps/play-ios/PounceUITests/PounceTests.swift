import XCTest

/// The Pounce sheet, the bell and answering pounces (spec §12.4) on the Us screen, from
/// `DemoFixtures.streaks()` and `DemoPounceService` under `-demo-streaks`: no server needed.
/// Mia's table waits on her move; Kiki's pounce waits on you; Nova's bell rests.
@MainActor
final class PounceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-show-us"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        return app
    }

    private func openSheet(_ app: XCUIApplication) {
        let bell = el(app, "us.bell")
        XCTAssertTrue(bell.waitForExistence(timeout: Live.t(5)), "no bell")
        bell.tap()
        XCTAssertTrue(el(app, "sheet-pounce").waitForExistence(timeout: Live.t(5)), "no Pounce sheet")
    }

    func testSheetTargets() {
        let app = launch()
        XCTAssertEqual(value(el(app, "us.bell")), "ready")
        openSheet(app)
        let first = el(app, "pounce.tile.0")
        XCTAssertTrue(value(first)?.hasPrefix("table:") == true, "Mia's their-move table comes first")
        XCTAssertTrue(first.isSelected, "and it's preselected")
        XCTAssertEqual(value(el(app, "pounce.tile.1")), "new")
        XCTAssertEqual(value(el(app, "pounce.tile.2")), "pick")
        el(app, "pounce.tile.1").tap()
        XCTAssertTrue(until(3) { self.el(app, "pounce.tile.1").isSelected })
        XCTAssertFalse(el(app, "pounce.tile.0").isSelected)
        XCTAssertTrue(el(app, "pounce.share").exists, "an adult can share a link")
        el(app, "pounce.close").tap()
        XCTAssertTrue(until(3) { !self.el(app, "sheet-pounce").exists })
    }

    func testSendShowsSent() {
        let app = launch()
        openSheet(app)
        el(app, "pounce.send").tap()
        XCTAssertTrue(until(5) { !self.el(app, "sheet-pounce").exists }, "the sheet stays up")
        XCTAssertTrue(until(5) { self.value(self.el(app, "us.bell")) == "sent" }, "the bell isn't ringing")
    }

    func testRestingBellIsDisabled() {
        let app = launch()
        el(app, "us.pair.2").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "us.bell")) == "resting" }, "Nova's bell isn't asleep")
        el(app, "us.bell").tap()
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "sheet-pounce").exists, "a resting bell opened the sheet")
    }

    func testWaitingAnswerLater() {
        let app = launch()
        el(app, "us.pair.1").tap()
        let card = el(app, "us.waiting")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(5)), "Kiki's pounce doesn't wait")
        XCTAssertEqual(value(card), "table:K9PQR")
        el(app, "waiting.later").tap()
        XCTAssertTrue(until(5) { !self.el(app, "us.waiting").exists }, "the answered pounce still waits")
    }

    func testWaitingAnswerPlayOpensTheTable() {
        let app = launch()
        el(app, "us.pair.1").tap()
        XCTAssertTrue(el(app, "waiting.play").waitForExistence(timeout: Live.t(5)))
        el(app, "waiting.play").tap()
        XCTAssertTrue(el(app, "screen-table").waitForExistence(timeout: Live.t(10)), "Play didn't open the table")
    }

    func testPlayPillPreselectsNew() {
        let app = launch()
        el(app, "us.pair.2").tap()
        let play = el(app, "us.play")
        XCTAssertTrue(play.waitForExistence(timeout: Live.t(5)), "Nova has no table in play: the Play pill")
        play.tap()
        XCTAssertTrue(el(app, "sheet-pounce").waitForExistence(timeout: Live.t(5)), "Play didn't open the sheet")
        XCTAssertTrue(until(3) { self.el(app, "pounce.tile.0").isSelected && self.value(self.el(app, "pounce.tile.0")) == "new" })
    }

    func testKittenHasNoShare() {
        let app = launch(["-age-band", "kitten"])
        openSheet(app)
        XCTAssertTrue(el(app, "pounce.send").exists, "a kitten can pounce in the app")
        XCTAssertFalse(el(app, "pounce.share").exists, "no links from a kitten's device")
    }

    func testLinkOpensPick() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-show-link"]
        app.launch()
        let sheet = el(app, "sheet-pick")
        XCTAssertTrue(sheet.waitForExistence(timeout: Live.t(10)), "the link didn't open the pick sheet")
        XCTAssertEqual(value(sheet), "Leo")
        XCTAssertEqual(value(el(app, "pick.tile.0")), "new")
        el(app, "pick.no").tap()
        XCTAssertTrue(until(5) { !self.el(app, "sheet-pick").exists })
    }

    /// Review fix: a link opened by mistake closes without answering.
    func testLinkPickCloses() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-show-link"]
        app.launch()
        XCTAssertTrue(el(app, "sheet-pick").waitForExistence(timeout: Live.t(10)))
        el(app, "pick.close").tap()
        XCTAssertTrue(until(5) { !self.el(app, "sheet-pick").exists }, "the pick sheet didn't close")
    }
}
