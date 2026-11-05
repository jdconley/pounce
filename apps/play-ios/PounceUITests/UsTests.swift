import XCTest

/// The Home streak badge and the Us screen (spec §10.1, §10.2), drawn from `DemoFixtures.streaks()`
/// under `-demo-streaks`: no server needed.
@MainActor
final class UsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func us(_ app: XCUIApplication) {
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
    }

    func testHomeBadgeOpensUs() {
        let app = launch()
        let badge = el(app, "home.streak")
        XCTAssertTrue(badge.waitForExistence(timeout: Live.t(10)), "no streak badge on Home")
        XCTAssertEqual(value(badge), "128|1|0|normal")
        badge.tap()
        us(app)
        el(app, "us.back").tap()
        XCTAssertTrue(el(app, "home.streak").waitForExistence(timeout: Live.t(10)))
    }

    /// The gift waits on Home (§9.5): tapping it opens it on the Us screen.
    func testHomeGiftOpens() {
        let app = launch()
        let gift = el(app, "home.gift")
        XCTAssertTrue(gift.waitForExistence(timeout: Live.t(10)), "no gift waiting on Home")
        gift.tap()
        XCTAssertTrue(el(app, "gift.reveal").waitForExistence(timeout: Live.t(10)), "the gift didn't open")
        let done = el(app, "gift.done")
        XCTAssertTrue(done.waitForExistence(timeout: Live.t(10)))
        done.tap()
        el(app, "us.back").tap()
        XCTAssertTrue(el(app, "home.streak").waitForExistence(timeout: Live.t(10)))
        XCTAssertTrue(until(5) { !self.el(app, "home.gift").exists }, "the opened gift still waits on Home")
    }

    func testUsShowsCondoWeekAndStats() {
        let app = launch(["-show-us"])
        us(app)
        XCTAssertEqual(label(el(app, "us.count")), "128")
        XCTAssertEqual(value(el(app, "us.count")), "normal")
        XCTAssertEqual(value(el(app, "us.condo")), "7")
        XCTAssertEqual(value(el(app, "us.week")), "kept,kept,nap,kept,held,kept,live")
        XCTAssertEqual(value(el(app, "us.paws")), "1|0")
        XCTAssertEqual(value(el(app, "us.stat.best")), "128")
        XCTAssertEqual(value(el(app, "us.stat.days")), "141")
        XCTAssertEqual(value(el(app, "us.stat.weeks")), "14")
        XCTAssertEqual(value(el(app, "us.arc")), "128/150")
        XCTAssertTrue(el(app, "us.gift.g7").exists)
        XCTAssertTrue(el(app, "us.toy.toy-golden-fish").exists, "the toys sit on the condo")
    }

    func testSwitchPairs() {
        let app = launch(["-show-us"])
        us(app)
        el(app, "us.pair.1").tap()
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "9" })
        XCTAssertEqual(value(el(app, "us.count")), "winback")
        el(app, "us.pair.2").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "us.count")) == "paused" })
    }

    func testGiftOpens() {
        let app = launch(["-show-us"])
        us(app)
        el(app, "us.gift.g7").tap()
        let reveal = el(app, "gift.reveal")
        XCTAssertTrue(reveal.waitForExistence(timeout: Live.t(5)), "no gift reveal")
        let done = el(app, "gift.done")
        XCTAssertTrue(done.waitForExistence(timeout: Live.t(10)))
        XCTAssertEqual(value(reveal), "rug-fish-pond")
        done.tap()
        XCTAssertTrue(until(5) { !self.el(app, "us.gift.g7").exists }, "the opened gift is still waiting")
    }

    func testPauseDial() {
        let app = launch(["-show-us"])
        us(app)
        el(app, "us.pause").tap()
        XCTAssertTrue(el(app, "pause.day.3").waitForExistence(timeout: Live.t(5)), "no day dial")
        el(app, "pause.day.3").tap()
        el(app, "pause.confirm").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "us.count")) == "paused" }, "no suitcase on the numeral")
        el(app, "us.pause").tap()
        XCTAssertTrue(el(app, "pause.end").waitForExistence(timeout: Live.t(5)))
        el(app, "pause.end").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "us.count")) == "normal" })
    }

    func testLeaveShowsGhostThenRejoin() {
        let app = launch(["-show-us"])
        us(app)
        XCTAssertTrue(el(app, "us.ghost.0").exists, "Leo's ghosted cat")
        el(app, "us.pair.0").press(forDuration: 1.0)
        let leave = el(app, "us.leave")
        XCTAssertTrue(leave.waitForExistence(timeout: Live.t(5)), "no long-press bubble")
        XCTAssertTrue(el(app, "us.pin").exists)
        leave.tap()
        let confirm = el(app, "leave.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(5)), "leaving asks first")
        confirm.tap()
        XCTAssertTrue(until(5) { self.el(app, "us.ghost.1").exists }, "no ghosted cat for Mia")
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "9" }, "the next pair shows")
        el(app, "us.ghost.1").tap()
        XCTAssertTrue(until(5) { !self.el(app, "us.ghost.1").exists }, "the ghost stays")
        XCTAssertTrue(el(app, "us.pair.2").exists, "Mia is back as a fresh pair")
    }

    func testNoBadgeWhenStreaksAreOff() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "off"]
        app.launch()
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)))
        Thread.sleep(forTimeInterval: Live.pace(2))
        XCTAssertFalse(el(app, "home.streak").exists)
    }
}
