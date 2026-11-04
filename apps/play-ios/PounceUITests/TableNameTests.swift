import XCTest

/// Table names (needs the dev server): a new table starts with a cat-themed name, the host names
/// it in the lobby, Home's card shows it, the table menu shows it, and renaming it from the menu
/// reaches Home too.
final class TableNameTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testNameATableInTheLobbySeeItOnHomeAndAtTheTable() throws {
        let app = Live.app()
        app.launchArguments.append("-no-tips")
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        XCTAssertEqual(code.count, 5, "no room code")

        let title = el(app, "lobby.name")
        XCTAssertTrue(title.waitForExistence(timeout: Live.t(10)), "no table name in the lobby")
        XCTAssertTrue(title.label.hasPrefix("Table name, The "), "no default name: \(title.label)")

        rename(app, from: title, to: "Taco Night")
        XCTAssertTrue(until(10) { title.label == "Table name, Taco Night" }, "the lobby kept \(title.label)")
        screenshot(app, "table-name-lobby")

        // Home's card shows it, the code still under it.
        el(app, "lobby.home").tap()
        let card = el(app, "home.table.\(code)")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(15)), "the table isn't on Home")
        XCTAssertTrue(until(10) { card.label.contains("Taco Night") }, "Home's card: \(card.label)")
        XCTAssertTrue(card.label.contains(code), "Home's card lost the code: \(card.label)")
        screenshot(app, "table-name-home")

        // Back in, a bot, and the game: the table menu shows the name.
        card.tap()
        XCTAssertTrue(el(app, "lobby.seat.1").waitForExistence(timeout: Live.t(15)), "no lobby")
        seatMenu(app, seat: 1, "bot")
        XCTAssertTrue(until(10) { self.el(app, "lobby.seat.1").label.contains("bot") }, "no bot")
        el(app, "lobby.start").tap()
        XCTAssertTrue(el(app, "table.menu").waitForExistence(timeout: Live.t(20)), "no table")
        dismissPriming(app)

        el(app, "table.menu").tap()
        let menuName = el(app, "menu.name")
        XCTAssertTrue(menuName.waitForExistence(timeout: Live.t(5)), "no name in the table menu")
        XCTAssertEqual(menuName.label, "Table name, Taco Night")
        screenshot(app, "table-name-menu")

        // Anyone seated renames it mid-game; the menu and then Home follow.
        rename(app, from: menuName, to: "Second Helpings")
        XCTAssertTrue(until(10) { menuName.label == "Table name, Second Helpings" }, "the menu kept \(menuName.label)")
        el(app, "menu.home").tap()
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(15)), "the table isn't on Home")
        XCTAssertTrue(until(10) { card.label.contains("Second Helpings") }, "Home's card: \(card.label)")
    }

    /// Taps the name, replaces the text in the rename sheet with `name`, and taps Done.
    @MainActor
    private func rename(_ app: XCUIApplication, from title: XCUIElement, to name: String) {
        title.tap()
        let field = el(app, "rename.field")
        XCTAssertTrue(field.waitForExistence(timeout: Live.t(5)), "no rename sheet")
        // The sheet focuses the field itself, with the cursor after the current name.
        if !until(4, { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true }) { field.tap() }
        let old = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + name)
        XCTAssertEqual(field.value as? String, name)
        screenshot(app, "table-name-sheet-\(name)")
        el(app, "rename.done").tap()
        XCTAssertTrue(until(5) { !field.exists }, "the rename sheet stayed up")
    }
}
