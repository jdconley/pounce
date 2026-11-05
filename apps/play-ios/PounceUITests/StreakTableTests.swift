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
            if let parts = snap.value("table.streak")?.split(separator: "|").map(String.init), parts.count == 5,
               Int(parts[0]) ?? 0 >= 1, Int(parts[4]) ?? 0 >= 1 {
                stamped = parts
                break
            }
            dismissPriming(app, snap)
            if holdCurtain(app, snap) != nil {
                Thread.sleep(forTimeInterval: Live.pace(1))
                continue
            }
            if !playTurnByTaps(app, snap) { Thread.sleep(forTimeInterval: Live.poll(1)) }
        }
        let parts = try XCTUnwrap(stamped, "no stamp: \(String(describing: UISnap(app)?.value("table.streak")))")
        XCTAssertEqual(parts[0], "1")
        XCTAssertEqual(parts[3], "1", "the day is kept")
        screenshot(app, "stamp")
    }
}
