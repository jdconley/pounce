import XCTest

/// A table you sit at alone (needs the dev server): left before anyone was invited, it stays off
/// Home; once its invite is out (here, its QR code shown), Home lists it while people accept.
final class EmptyTableTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testATableIsOnHomeOnlyOnceItsInviteIsOut() throws {
        let app = Live.app()
        app.launch()
        onboard(app)

        // Play, then straight back: no card for an empty table.
        newGame(app)
        let alone = lobbyCode(app)
        el(app, "lobby.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        // Home asks the server again on coming back; the table must not appear then either.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(until(5) { self.el(app, "home.table.\(alone)").exists }, "an empty table nobody was invited to is on Home")

        // Play again and show the QR code: the invite is out, so the table waits on Home.
        newGame(app)
        let invited = lobbyCode(app)
        showInvite(app)
        el(app, "lobby.home").tap()
        XCTAssertTrue(el(app, "home.table.\(invited)").waitForExistence(timeout: Live.t(15)), "an invited table isn't on Home")
        XCTAssertFalse(el(app, "home.table.\(alone)").exists, "the uninvited table came back")
        screenshot(app, "empty-table-home")
    }
}
