import XCTest

/// Home at launch (needs the dev server): a phone with tables opens on them, not on the
/// first-visit game posters while the server's list is on its way. The second launch keeps the
/// first one's data (`-uitest-data`) and never hears from the server (`-tables-offline`), so
/// what it shows is what it saved.
final class HomeLaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeOpensOnYourTablesBeforeTheServerAnswers() throws {
        let data = UUID().uuidString
        let app = Live.app()
        app.launchArguments += ["-uitest-data", data]
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        showInvite(app)
        el(app, "lobby.home").tap()
        XCTAssertTrue(el(app, "home.table.\(code)").waitForExistence(timeout: Live.t(15)), "the new table isn't on Home")
        app.terminate()

        app.launchArguments += ["-tables-offline"]
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        let card = el(app, "home.table.\(code)")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(5)), "Home forgot the table until the server answers")
        XCTAssertFalse(el(app, "home.practice").exists, "the first-visit Practice pill with a table going")
        let catTower = el(app, "home.newGame")
        XCTAssertTrue(catTower.exists, "no Cat Tower card under the tables")
        XCTAssertLessThan(card.frame.minY, catTower.frame.minY, "the game posters lead over a table in progress")
        screenshot(app, "home-launch-saved-tables")
    }
}
