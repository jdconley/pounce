import XCTest

/// Nudges (NudgeViews.swift): the Nudge button on the card of the person whose move it is, its
/// wait and its sent state, and the nudge a phone gets at the table. No server: `-demo nudge` is
/// Kiki's (seat 2, asleep) move with a nudge ready, which the demo server answers as sent;
/// `nudgeWait` has a minute and a half to wait; `nudged` is this phone's move, nudged by Leo five seconds in.
@MainActor
final class NudgeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func table(_ demo: String, speed: Double = Live.speed) -> XCUIApplication {
        let app = Live.demo(demo, speed: speed)
        app.launchArguments += ["-uitest-reset", "-seed-people"]
        app.launch()
        XCTAssertTrue(el(app, "table.menu").waitForExistence(timeout: Live.t(10)), "no table")
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(3)) { dismissPriming(app) }
        _ = until(5) { !self.el(app, "priming.notNow").exists }
        return app
    }

    private func openCard(_ app: XCUIApplication, seat: Int) {
        let cat = el(app, "table.opponent.\(seat)")
        XCTAssertTrue(cat.waitForExistence(timeout: Live.t(10)), "no cat for seat \(seat)")
        tap(app, cat.frame)
        XCTAssertTrue(el(app, "player").waitForExistence(timeout: Live.t(5)), "no player card for seat \(seat)")
    }

    func testNudgeTheirMoveAndTheCardSaysItWent() {
        let app = table("nudge")
        openCard(app, seat: 2)
        let nudge = el(app, "player.nudge")
        XCTAssertTrue(nudge.waitForExistence(timeout: Live.t(5)), "no Nudge on Kiki's card")
        XCTAssertEqual(value(nudge), "ready")
        XCTAssertTrue(nudge.isEnabled)
        screenshot(app, "nudge-ready")
        nudge.tap()
        XCTAssertTrue(until(5) { self.value(nudge) == "sent" }, "the nudge never went: \(String(describing: value(nudge)))")
        XCTAssertEqual(label(nudge), "Nudge sent to Kiki")
        XCTAssertFalse(nudge.isEnabled, "a second nudge this turn")
        nudge.tap()
        XCTAssertEqual(value(nudge), "sent")
        Thread.sleep(forTimeInterval: Live.pace(0.6))
        screenshot(app, "nudge-sent")
    }

    func testTooSoonShowsWhenInWholeMinutes() {
        let app = table("nudgeWait")
        openCard(app, seat: 2)
        let nudge = el(app, "player.nudge")
        XCTAssertTrue(nudge.waitForExistence(timeout: Live.t(5)), "no Nudge on Kiki's card")
        XCTAssertEqual(value(nudge), "wait")
        XCTAssertFalse(nudge.isEnabled)
        XCTAssertEqual(label(nudge), "Nudge Kiki, In 2 min")
        screenshot(app, "nudge-wait")
    }

    func testNoNudgeForSomeoneOffTheMoveOrABot() {
        let app = table("nudge")
        openCard(app, seat: 1)
        XCTAssertFalse(el(app, "player.nudge").exists, "Leo isn't on the move")
        el(app, "player.close").tap()
        XCTAssertTrue(until(5) { !self.el(app, "player").exists })
        openCard(app, seat: 3)
        XCTAssertFalse(el(app, "player.nudge").exists, "a bot got a nudge button")
    }

    /// At normal speed: the pill is up for three seconds.
    func testANudgeAtTheTableTapsAndPlaysTheTurnCueAgain() {
        let app = table("nudged", speed: 1)
        let pill = el(app, "nudge.pill")
        XCTAssertTrue(pill.waitForExistence(timeout: Live.t(10)), "no nudge at the table")
        XCTAssertEqual(label(pill), "Leo nudged you. Your move.")
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertTrue(el(app, "turncue.mine").exists, "the Your turn cue didn't come back")
        screenshot(app, "nudged-in-app")
        XCTAssertTrue(until(8) { !pill.exists }, "the nudge pill never went")
    }
}
