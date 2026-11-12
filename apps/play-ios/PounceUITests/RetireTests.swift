import XCTest

/// Retiring a stalled seat (PlayerCardView.swift): on the card of a person whose move has waited
/// its days, "Retire seat" asks first, saying what happens, then their seat forfeits.
/// No server: `-demo retire` is Kiki's (seat 2, asleep) move with the wait over, which the demo
/// server answers with her forfeit. Home's "N days ago" comes from `-demo-home`.
@MainActor
final class RetireTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func table(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo, speed: Live.speed)
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

    func testRetireAStalledSeatAsksFirstThenTheirSeatForfeits() {
        let app = table("retire")
        openCard(app, seat: 2)
        let retire = el(app, "player.retire")
        XCTAssertTrue(retire.waitForExistence(timeout: Live.t(5)), "no retire on Kiki's card")
        XCTAssertEqual(retire.label, "Retire seat")
        screenshot(app, "retire-card")

        // Keep waiting: nothing happens.
        retire.tap()
        let alert = app.alerts["Retire Kiki's seat?"]
        XCTAssertTrue(alert.waitForExistence(timeout: Live.t(5)), "no confirmation")
        let message = "Kiki finishes last. The rest play on. It can't be undone."
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch.exists,
            "the confirmation doesn't say what happens")
        screenshot(app, "retire-confirm")
        el(app, "retire.cancel").firstMatch.tap()
        XCTAssertTrue(el(app, "player.retire").waitForExistence(timeout: Live.t(5)))

        // Retire seat: the card goes, and her seat is out like any forfeit.
        el(app, "player.retire").tap()
        XCTAssertTrue(alert.waitForExistence(timeout: Live.t(5)))
        el(app, "retire.confirm").firstMatch.tap()
        XCTAssertTrue(until(5) { !self.el(app, "player").exists }, "the card stayed up")
        let kiki = el(app, "table.opponent.2")
        XCTAssertTrue(until(5) { kiki.label == "Kiki, forfeited" }, "Kiki isn't out: \(kiki.label)")
        screenshot(app, "retire-done")
        openCard(app, seat: 2)
        XCTAssertFalse(el(app, "player.retire").exists, "a retired seat can be retired again")
    }

    func testNoRetireBeforeTheWaitIsOverOrForAnyoneElse() {
        // `nudge`: Kiki's move, but the server offers no retire yet.
        let app = table("nudge")
        openCard(app, seat: 2)
        XCTAssertTrue(el(app, "player.nudge").waitForExistence(timeout: Live.t(5)))
        XCTAssertFalse(el(app, "player.retire").exists, "retire before the wait is over")
        app.terminate()

        let stalled = table("retire")
        openCard(stalled, seat: 1)
        XCTAssertFalse(el(stalled, "player.retire").exists, "Leo isn't on the move")
    }
}
