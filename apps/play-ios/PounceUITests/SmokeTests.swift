import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Live.t(10)))
    }

    /// Task 24 (needs the dev server): a fresh phone picks its cat, makes a room, adds a bot,
    /// starts, and plays one turn by taps against the real server.
    @MainActor
    func testCreateBotStartDrawDiscard() throws {
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        seatMenu(app, seat: 1, "bot")
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(10) { seat1.label.contains("bot") }, "no bot on seat 1: \(seat1.label)")
        el(app, "lobby.start").tap()

        let turn = el(app, "table.turn")
        XCTAssertTrue(turn.waitForExistence(timeout: Live.t(15)), "no table")
        XCTAssertTrue(until(30) { value(turn) == "mine" && (debug(app)?.settled ?? false) }, "my turn never came")
        el(app, "table.deck").tap()
        XCTAssertTrue(until(10) { debug(app).map { $0.step == "play" && $0.settled } ?? false }, "no draw")
        el(app, "table.hand.0").tap()
        el(app, "table.discard").tap()
        if !until(5, { value(turn) == "other" }) {
            // hand.0 was a Cucumber: it waits for a cat to aim at.
            let cat = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'table.opponent.' AND value == 'glowing'")).firstMatch
            if cat.exists { cat.tap() }
        }
        // The discard landed: the bot is up, or my next turn already began with a hand back at
        // 10 (a Cucumber skipped the bot, or its whole turn went by between two queries, each
        // of which waits for the app to idle).
        XCTAssertTrue(until(10) {
            value(turn) == "other" || debug(app).map { $0.step == "draw" && $0.handCount == 10 && $0.settled } ?? false
        }, "the turn didn't pass: \(String(describing: debug(app)))")
        screenshot(app, "smoke-after-discard")
    }
}
