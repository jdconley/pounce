import XCTest

/// Names people set and see: first launch asks for a name (the random one is only a
/// placeholder), the name is on the table, and once the game has started it can't be changed.
class NamesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Needs the dev server (a build of this branch's play-api, which knows `rename`).
    @MainActor
    func testNameTypedAtFirstLaunchShowsAtTheTableAndIsFrozenThere() throws {
        let app = Live.app()
        app.launch()

        // A name is suggested and the keyboard waits, so every cat shows (first-run funnel).
        let confirm = el(app, "pickcat.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(15)), "no pick-a-cat screen")
        XCTAssertTrue(el(app, "pickcat.prompt").exists, "no name prompt")
        let field = app.textFields["pickcat.name"]
        XCTAssertEqual(app.keyboards.count, 0, "the keyboard came up on its own")
        XCTAssertFalse((value(field) ?? "").isEmpty, "no suggested name")
        // Tapping the name selects it: typing replaces it.
        field.tap()
        XCTAssertTrue(until(5) { app.keyboards.count > 0 }, "the name field isn't focused")

        field.typeText("Zelda Q")
        screenshot(app, "names-first-launch")
        confirm.tap()
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Home")

        newGame(app)
        XCTAssertTrue(el(app, "lobby.seat.0").label.hasPrefix("Zelda Q,"), el(app, "lobby.seat.0").label)
        seatMenu(app, seat: 1, "bot")
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(10) { seat1.label.contains("bot") }, "no bot on seat 1: \(seat1.label)")
        el(app, "lobby.start").tap()

        // At the table: my name by my hand, the bot's under its cat.
        dismissPrimingIfShown(app)
        let me = el(app, "table.me")
        XCTAssertTrue(me.waitForExistence(timeout: Live.t(15)), "no name by the hand")
        XCTAssertEqual(label(me), "Zelda Q")
        XCTAssertTrue(label(el(app, "table.opponent.1"))?.hasPrefix("House Cat") ?? false)
        screenshot(app, "names-at-the-table")

        // Names are frozen once the game has started: the table menu offers no rename.
        el(app, "table.menu").tap()
        XCTAssertTrue(el(app, "menu.home").waitForExistence(timeout: Live.t(5)), "no table menu")
        XCTAssertFalse(el(app, "menu.names").exists, "Names is offered mid-game")
        screenshot(app, "names-frozen-in-game")
    }

    /// No server: every seat of a demo table has its name on the table.
    @MainActor
    func testDemoTableNamesEverySeat() throws {
        let app = Live.demo("table")
        app.launch()
        dismissPrimingIfShown(app)
        let me = el(app, "table.me")
        XCTAssertTrue(me.waitForExistence(timeout: 10))
        XCTAssertEqual(label(me), "Mia")
        XCTAssertTrue(label(el(app, "table.opponent.1"))?.hasPrefix("Leo") ?? false)
        XCTAssertTrue(label(el(app, "table.opponent.3"))?.hasPrefix("House Cat") ?? false)
    }

    /// A fresh simulator has no push answer yet, so the table may put the priming screen up.
    @MainActor private func dismissPrimingIfShown(_ app: XCUIApplication) {
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: Live.t(4)) {
            dismissPriming(app)
            _ = notNow.waitForNonExistence(timeout: Live.t(3))
        }
    }
}
