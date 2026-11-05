import XCTest

/// The notification settings panel (spec §12.6, §14.1) from the Us screen's gear and the gear
/// sheet, with each age band's defaults. No server needed (`-demo-streaks`).
@MainActor
final class NotifyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-show-us"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        let gear = el(app, "us.gear")
        XCTAssertTrue(gear.waitForExistence(timeout: Live.t(5)), "no gear on the Us screen")
        gear.tap()
        XCTAssertTrue(el(app, "sheet-notify").waitForExistence(timeout: Live.t(5)), "no settings panel")
        return app
    }

    func testAdultDefaults() {
        let app = launch()
        XCTAssertEqual(value(el(app, "notify.reminders")), "on")
        XCTAssertEqual(value(el(app, "notify.auto")), "on")
        XCTAssertEqual(value(el(app, "notify.lastChance")), "on")
        XCTAssertEqual(value(el(app, "notify.quietStart")), "22:00")
        XCTAssertEqual(value(el(app, "notify.quietEnd")), "08:00")
        XCTAssertFalse(el(app, "notify.weekday").exists, "Auto hides the dials")
        XCTAssertFalse(el(app, "notify.kitten").exists)
    }

    func testAutoOffShowsDials() {
        let app = launch()
        el(app, "notify.auto").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "notify.auto")) == "off" })
        let weekday = el(app, "notify.weekday")
        XCTAssertTrue(weekday.waitForExistence(timeout: Live.t(3)), "no weekday dial")
        XCTAssertEqual(value(weekday), "19:30")
        XCTAssertEqual(value(el(app, "notify.weekend")), "19:30")
        el(app, "notify.weekday.plus").tap()
        XCTAssertTrue(until(3) { self.value(weekday) == "19:45" }, "the dial didn't step")
        // Two hours before quiet hours is as late as it goes.
        for _ in 0..<4 { el(app, "notify.weekday.plus").tap() }
        XCTAssertTrue(until(3) { self.value(weekday) == "20:00" }, "the dial went past 20:00")
    }

    func testRemindersOffAndBackOn() {
        let app = launch()
        el(app, "notify.reminders").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "notify.reminders")) == "off" })
        el(app, "notify.reminders").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "notify.reminders")) == "on" })
    }

    func testTeenDefaults() {
        let app = launch(["-age-band", "teen"])
        XCTAssertEqual(value(el(app, "notify.reminders")), "off")
        XCTAssertEqual(value(el(app, "notify.auto")), "off")
        XCTAssertEqual(value(el(app, "notify.lastChance")), "off")
        XCTAssertEqual(value(el(app, "notify.quietStart")), "21:00")
        XCTAssertEqual(value(el(app, "notify.weekday")), "19:00", "a teen's fixed time, clamped before 21:00 quiet")
    }

    func testKittenPanel() {
        let app = launch(["-age-band", "kitten"])
        let bell = el(app, "notify.kitten")
        XCTAssertTrue(bell.exists)
        XCTAssertEqual(value(bell), "off")
        XCTAssertFalse(el(app, "notify.reminders").exists)
        XCTAssertFalse(el(app, "notify.quietStart").exists)
        XCTAssertFalse(el(app, "notify.liveTable").exists, "a kitten never gets a live table (§14.1)")
    }

    /// The live table toggle (spec §11.3, §12.6): on by default for adults and teens, and it flips.
    func testLiveTableToggle() {
        let app = launch()
        let live = el(app, "notify.liveTable")
        XCTAssertTrue(live.exists, "no live table toggle")
        XCTAssertEqual(value(live), "on")
        live.tap()
        XCTAssertTrue(until(3) { self.value(live) == "off" })
        live.tap()
        XCTAssertTrue(until(3) { self.value(live) == "on" })
        app.terminate()
        let teen = launch(["-age-band", "teen"])
        XCTAssertEqual(value(el(teen, "notify.liveTable")), "on", "the game itself, so on for teens too")
    }

    func testGearHasPanel() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-show-gear"]
        app.launch()
        XCTAssertTrue(el(app, "sheet-gear").waitForExistence(timeout: Live.t(10)), "no gear sheet")
        XCTAssertTrue(el(app, "notify.reminders").waitForExistence(timeout: Live.t(5)), "the gear sheet has no panel")
    }
}
