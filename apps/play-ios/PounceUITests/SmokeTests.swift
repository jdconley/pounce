import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
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
        XCTAssertTrue(turn.waitForExistence(timeout: 15), "no table")
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
        XCTAssertTrue(until(10) { value(turn) == "other" }, "the turn didn't pass: \(String(describing: debug(app)))")
        screenshot(app, "smoke-after-discard")
    }
}
