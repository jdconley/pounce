import XCTest

/// Names people set and see: first launch asks for a name (the random one is only a
/// placeholder), the name is on the table, and a rename from the table menu reaches the server
/// and comes back in the next snapshot.
final class NamesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Needs the dev server (a build of this branch's play-api, which knows `rename`).
    @MainActor
    func testNameTypedAtFirstLaunchShowsAtTheTableAndRenames() throws {
        let app = Live.app()
        app.launch()

        // The name is the obvious step: asked for, the field focused, nothing filled in yet.
        let confirm = el(app, "pickcat.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(15)), "no pick-a-cat screen")
        XCTAssertTrue(el(app, "pickcat.prompt").exists, "no name prompt")
        let field = app.textFields["pickcat.name"]
        XCTAssertTrue(until(5) { app.keyboards.count > 0 }, "the name field isn't focused")
        let suggestion = field.placeholderValue ?? ""
        XCTAssertFalse(suggestion.isEmpty, "no suggested name")
        let typed = value(field) ?? ""
        XCTAssertTrue(typed.isEmpty || typed == suggestion, "the field isn't empty: \(typed)")
        // The suggestion is a placeholder: the check won't take it.
        confirm.tap()
        XCTAssertFalse(el(app, "home.newGame").waitForExistence(timeout: Live.t(2)), "an empty name went through")
        XCTAssertTrue(confirm.exists)

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

        // Rename mid-game from the table menu; the server's next snapshot carries it.
        el(app, "table.menu").tap()
        let names = el(app, "menu.names")
        XCTAssertTrue(names.waitForExistence(timeout: Live.t(5)), "no Names in the table menu")
        names.tap()
        let rename = app.textFields["rename.name.0"]
        XCTAssertTrue(rename.waitForExistence(timeout: Live.t(5)), "no rename field")
        // Focusing selects the whole name: typing replaces it.
        rename.tap()
        Thread.sleep(forTimeInterval: Live.pace(0.5))
        rename.typeText("Zed")
        el(app, "rename.save.0").tap()
        el(app, "rename.back").tap()
        _ = el(app, "menu.home").waitForExistence(timeout: Live.t(3))
        // Close the sheet (swipe it down) and look at the table.
        app.swipeDown()
        XCTAssertTrue(until(10) { label(me) == "Zed" }, "the rename never came back: \(label(me) ?? "-")")
        screenshot(app, "names-renamed")
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
