import XCTest

/// The table side of streaks (spec §9.4, §9.5, §10.3, §10.4): the look tray, Play again, and the
/// stamp after a turn. The first two run on `-demo` tables (no server); the stamp plays a real
/// game on the dev server (run it with scripts/ui-tests.sh; the server needs `STREAKS` on, which
/// wrangler.jsonc sets).
@MainActor
final class StreakTableTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The table, with the push priming screen (other humans sit here) put away.
    private func openMenu(_ app: XCUIApplication) {
        let menu = el(app, "table.menu")
        XCTAssertTrue(menu.waitForExistence(timeout: Live.t(10)), "no table")
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(3)) { el(app, "priming.notNow").tap() }
        _ = until(5) { !self.el(app, "priming.notNow").exists }
        menu.tap()
    }

    /// The tray offers the defaults and this person's own unlocks only; a pick changes the table.
    func testTraySetsRug() {
        let app = Live.demo("table")
        app.launchArguments += ["-uitest-reset", "-seed-people", "-demo-streaks"]
        app.launch()
        XCTAssertTrue(el(app, "table.menu").waitForExistence(timeout: Live.t(10)), "no table")
        XCTAssertEqual(value(el(app, "table.look")), "rug-classic|back-violet-paw")
        openMenu(app)
        let look = el(app, "menu.look")
        XCTAssertTrue(look.waitForExistence(timeout: Live.t(5)), "no look tray in the menu")
        look.tap()
        let night = el(app, "look.rug.rug-night-sky")
        XCTAssertTrue(night.waitForExistence(timeout: Live.t(5)), "an unlocked rug is missing")
        XCTAssertTrue(el(app, "look.rug.rug-classic").exists, "the default rug is always there")
        XCTAssertTrue(el(app, "look.back.back-crown").exists)
        XCTAssertFalse(el(app, "look.rug.rug-fish-pond").exists, "a rug still in an unopened gift is offered")
        XCTAssertFalse(el(app, "look.back.back-golden-yarn").exists)
        night.tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "table.look")) == "rug-night-sky|back-violet-paw" }, "the rug didn't change")
        el(app, "look.back.back-crown").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "table.look")) == "rug-night-sky|back-crown" })
    }

    /// Without looks from the server (streaks off) there is no tray.
    func testNoTrayWithoutLooks() {
        let app = Live.demo("replay")
        app.launch()
        openMenu(app)
        XCTAssertTrue(el(app, "menu.home").waitForExistence(timeout: Live.t(5)))
        XCTAssertFalse(el(app, "menu.look").exists)
    }

    /// Play again on a finished table deals the next one and this phone goes there.
    func testPlayAgainJumps() {
        let app = Live.demo("over")
        app.launch()
        let again = el(app, "gameover.again")
        XCTAssertTrue(again.waitForExistence(timeout: Live.t(20)), "no Play again on the game over screen")
        again.tap()
        XCTAssertTrue(until(10) { !self.el(app, "screen-gameover").exists }, "still on the game over screen")
        XCTAssertTrue(until(10) { self.value(self.el(app, "table.code")) == "NWCDF" }, "not at the new table")
    }

    /// A new pair's first day: the badge appears with the message that keeps it, and still stamps.
    func testStampPlaysWhenTheBadgeAppearsWithIt() {
        let app = Live.demo("table")
        app.launchArguments += ["-uitest-reset", "-seed-people", "-demo-streaks", "-demo-stamp", "new"]
        app.launch()
        let badge = el(app, "table.streak")
        XCTAssertTrue(badge.waitForExistence(timeout: Live.t(15)), "no badge after the streak message")
        XCTAssertTrue(until(5) { (self.value(badge)?.split(separator: "|").last).flatMap { Int($0) } ?? 0 >= 1 },
                      "the badge appeared but never stamped: \(String(describing: value(badge)))")
    }

    /// Two people on this phone each take a turn: the table's badge shows the new streak and stamps.
    func testStampAfterTurn() throws {
        let restoreQuiescence = Quiescence.disable()
        addTeardownBlock { @MainActor in restoreQuiescence() }
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        seatMenu(app, seat: 1, "here")
        addLocalPerson(app)
        XCTAssertTrue(until(10) { self.el(app, "lobby.seat.1").label.contains("on this phone") }, "no second local seat")
        Thread.sleep(forTimeInterval: 1.5)  // the new person's profile goes up (debounced)
        el(app, "lobby.start").tap()

        let deadline = Date().addingTimeInterval(Live.t(400))
        var stamped: [String]?
        while Date() < deadline {
            guard let snap = UISnap(app) else {
                Thread.sleep(forTimeInterval: Live.poll(1))
                continue
            }
            // The badge is there and kept: from here it has a moment to have stamped.
            if let parts = snap.value("table.streak")?.split(separator: "|").map(String.init), parts.count == 5,
               Int(parts[0]) ?? 0 >= 1, parts[3] == "1" {
                _ = until(5) { (self.value(self.el(app, "table.streak"))?.split(separator: "|").last).flatMap { Int($0) } ?? 0 >= 1 }
                stamped = value(el(app, "table.streak"))?.split(separator: "|").map(String.init)
                break
            }
            dismissPriming(app, snap)
            if holdCurtain(app, snap) != nil {
                Thread.sleep(forTimeInterval: Live.pace(1))
                continue
            }
            if !playTurnByTaps(app, snap) { Thread.sleep(forTimeInterval: Live.poll(1)) }
        }
        let debug = String(describing: UISnap(app)?.value("table.stamp.debug"))
        let parts = try XCTUnwrap(stamped, "no kept badge: \(String(describing: UISnap(app)?.value("table.streak"))) \(debug)")
        XCTAssertEqual(parts[0], "1")
        XCTAssertEqual(parts[3], "1", "the day is kept")
        XCTAssertGreaterThanOrEqual(Int(parts[4]) ?? 0, 1, "the badge never stamped: \(parts) \(debug)")
        screenshot(app, "stamp")
    }
}
