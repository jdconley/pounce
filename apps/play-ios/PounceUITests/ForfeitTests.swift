import XCTest

/// Forfeit (spec §5.13, needs the dev server): from the paw menu, behind a confirmation that
/// says what will happen. Against one bot the game ends and the bot wins; against two the phone
/// is out and goes Home while the bots play on, and opening the table again says so.
class ForfeitTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testForfeitAgainstOneBotEndsTheGame() throws {
        let app = start(bots: 1)
        openForfeit(app, "forfeit-confirm-2p")
        XCTAssertTrue(app.alerts.staticTexts["House Cat wins."].exists, "wrong message")
        app.alerts.buttons["Forfeit"].firstMatch.tap()

        let over = el(app, "screen-gameover")
        XCTAssertTrue(over.waitForExistence(timeout: Live.t(30)), "no game over")
        let mine = el(app, "gameover.standing.0")
        XCTAssertTrue(until(10) { mine.exists && mine.label.hasSuffix("forfeited") }, "standing: \(mine.label)")
        let winner = el(app, "gameover.winner")
        XCTAssertTrue(winner.waitForExistence(timeout: Live.t(10)), "no winner")
        Thread.sleep(forTimeInterval: Live.pace(2))
        screenshot(app, "forfeit-gameover-2p")
    }

    @MainActor
    func testForfeitAgainstTwoBotsGoesHomeWhileTheyPlayOn() throws {
        let app = start(bots: 2)
        let code = el(app, "table.code").value as? String ?? ""
        openForfeit(app, "forfeit-confirm-3p")
        XCTAssertTrue(
            app.alerts.staticTexts["You finish last. The rest play on."].exists, "wrong message")
        app.alerts.buttons["Forfeit"].firstMatch.tap()

        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(20)), "not Home after forfeiting")
        let card = el(app, "home.table.\(code)")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(15)), "the table left Home altogether")
        Thread.sleep(forTimeInterval: Live.pace(1))
        screenshot(app, "forfeit-home-3p")

        // Back in: no table, a card that says this phone is out.
        card.tap()
        XCTAssertTrue(el(app, "state.out").waitForExistence(timeout: Live.t(20)), "no forfeited card")
        Thread.sleep(forTimeInterval: Live.pace(1))
        screenshot(app, "forfeit-reopen-3p")
        el(app, "state.home").tap()
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Home")
    }

    /// `-demo forfeited`: what the others see when Kiki (seat 2) forfeits: the pill, then her
    /// seat dimmed with "Forfeited" under her name.
    @MainActor
    func testOthersSeeTheForfeit() throws {
        let app = Live.demo("forfeited", speed: 1)
        app.launch()
        let kiki = el(app, "table.opponent.2")
        XCTAssertTrue(kiki.waitForExistence(timeout: Live.t(10)), "no seat 2")
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(2)) { dismissPriming(app) }
        let pill = el(app, "forfeit.pill")
        XCTAssertTrue(pill.waitForExistence(timeout: Live.t(10)), "no forfeit notice")
        XCTAssertEqual(pill.label, "Kiki forfeited")
        screenshot(app, "forfeit-others-pill")
        XCTAssertTrue(until(5) { self.label(kiki) == "Kiki, forfeited" }, label(kiki) ?? "-")
        XCTAssertTrue(until(6) { !pill.exists }, "the notice stayed")
        screenshot(app, "forfeit-others-seat")
    }

    /// A fresh app at a new table with `bots` House Cats, the game started and the table up.
    @MainActor
    private func start(bots: Int) -> XCUIApplication {
        let app = Live.app()
        app.launchArguments.append("-no-tips")
        app.launch()
        onboard(app)
        newGame(app)
        for seat in 1...bots {
            seatMenu(app, seat: seat, "bot")
            XCTAssertTrue(until(10) { self.el(app, "lobby.seat.\(seat)").label.contains("bot") }, "no bot at \(seat)")
        }
        el(app, "lobby.start").tap()
        XCTAssertTrue(el(app, "table.menu").waitForExistence(timeout: Live.t(20)), "no table")
        dismissPriming(app)
        return app
    }

    /// Paw menu, Forfeit, and the confirmation up (screenshot `name`).
    @MainActor
    private func openForfeit(_ app: XCUIApplication, _ name: String) {
        el(app, "table.menu").tap()
        let forfeit = el(app, "menu.forfeit")
        XCTAssertTrue(forfeit.waitForExistence(timeout: Live.t(5)), "no Forfeit in the menu")
        Thread.sleep(forTimeInterval: Live.pace(0.6))
        screenshot(app, "\(name)-menu")
        forfeit.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: Live.t(5)), "no confirmation")
        XCTAssertTrue(app.alerts.buttons["Keep playing"].exists, "no way back")
        screenshot(app, name)
    }
}
