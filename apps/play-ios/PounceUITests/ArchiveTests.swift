import XCTest

/// Home's archive (needs the dev server): a table leaves the row by its long-press menu, waits
/// in the Archived sheet, and goes back on Home with a tap.
final class ArchiveTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testArchiveAndRestoreATable() throws {
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        XCTAssertEqual(code.count, 5, "no room code")
        showInvite(app)
        el(app, "lobby.home").tap()

        let card = el(app, "home.table.\(code)")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(15)), "the new table isn't on Home")
        XCTAssertFalse(el(app, "home.archived").exists, "an Archived tile before anything was archived")

        card.press(forDuration: 1.2)
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: Live.t(5)), "no Archive in the table's menu")
        archive.tap()
        XCTAssertTrue(until(10) { !card.exists }, "the archived table stayed on Home")
        let tile = el(app, "home.archived")
        XCTAssertTrue(tile.waitForExistence(timeout: Live.t(5)), "no Archived tile")
        screenshot(app, "archive-home-after-archive")

        // Still archived after a fresh table list from the server.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(tile.waitForExistence(timeout: Live.t(10)), "no Archived tile after coming back")
        XCTAssertFalse(card.exists, "the archived table came back on its own")

        tile.tap()
        let archived = el(app, "archived.table.\(code)")
        XCTAssertTrue(archived.waitForExistence(timeout: Live.t(5)), "the table isn't in the Archived sheet")
        screenshot(app, "archive-sheet")
        archived.tap()
        XCTAssertTrue(until(10) { !el(app, "sheet-archived").exists }, "the empty Archived sheet stayed up")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(5)), "the restored table isn't back on Home")
        XCTAssertFalse(tile.exists, "the Archived tile outlived the last archived table")
    }
}
