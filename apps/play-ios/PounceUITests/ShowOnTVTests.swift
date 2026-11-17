import XCTest

/// Show on TV against the dev server (its `TV` flag on), with `pounce-e2e screen link` playing
/// the TV through the host broker: it prints the link's backup code, and the table it is linked
/// to, and fails if anything it hears is private. The simulator has no camera scanner, so the
/// sheet is the code entry here; the scanner's parser has its unit tests (`TVCodeTests`).
@MainActor
final class ShowOnTVTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The lobby's Show on TV, the TV's code typed: "On the TV", and the TV is a screen at this
    /// table. Then a second table: the TV moves after "Move the TV to this table?".
    func testTypingTheTVsCodePutsTheTableOnTheTVAndMovesIt() throws {
        let tv = try HostProcess("e2e", ["screen", "link", "--again", "--timeout", "300", "--base", Live.baseURL])
        addTeardownBlock { tv.stop() }

        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let first = lobbyCode(app)
        let link = try XCTUnwrap(tvCode(tv, number: 1), "the TV never got a link:\n\(tv.output())")

        el(app, "lobby.tv").tap()
        XCTAssertTrue(el(app, "sheet-tv").waitForExistence(timeout: Live.t(10)), "no Show on TV sheet")
        screenshot(app, "tv-sheet")
        type(app, link)
        XCTAssertTrue(el(app, "tv.linked").waitForExistence(timeout: Live.t(15)), "no On the TV: \(message(app))")
        screenshot(app, "tv-linked")
        XCTAssertTrue(until(15) { tv.output().contains("linked \(first)") }, "the TV wasn't linked:\n\(tv.output())")
        XCTAssertTrue(until(15) { tv.output().contains("snapshot") && tv.output().contains(" \(first) lobby screen=true") },
                      "the TV never saw the table:\n\(tv.output())")
        XCTAssertTrue(until(10) { !self.el(app, "sheet-tv").exists }, "the sheet stayed up")

        // A second table: the TV shows the first, so the phone asks before moving it.
        el(app, "lobby.home").tap()
        newGame(app)
        let second = lobbyCode(app)
        XCTAssertNotEqual(first, second)
        let again = try XCTUnwrap(tvCode(tv, number: 2), "the TV never offered another link:\n\(tv.output())")
        el(app, "lobby.tv").tap()
        XCTAssertTrue(el(app, "sheet-tv").waitForExistence(timeout: Live.t(10)), "no Show on TV sheet")
        type(app, again)
        let confirm = app.alerts["Move the TV to this table?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(15)), "no move question: \(message(app))")
        screenshot(app, "tv-move")
        confirm.buttons["Move"].firstMatch.tap()
        XCTAssertTrue(el(app, "tv.linked").waitForExistence(timeout: Live.t(15)), "no On the TV after moving: \(message(app))")
        XCTAssertTrue(until(15) { tv.output().contains("linked \(second)") }, "the TV didn't move:\n\(tv.output())")
        XCTAssertTrue(until(15) { tv.output().contains(" \(second) lobby screen=true") }, "the TV never saw the new table:\n\(tv.output())")
        XCTAssertFalse(tv.output().contains("FAIL"), tv.output())
    }

    /// Camera permission denied: the sheet shows the code entry ("Type the TV's code") and no
    /// error; a wrong code says so, and the right one still works.
    func testWithTheCameraDeniedTheCodeStillWorks() throws {
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "not on a simulator")
        let revoke = try HostProcess("privacy", [udid, "revoke"])
        XCTAssertEqual(revoke.wait(timeout: 20), 0, "couldn't revoke the camera: \(revoke.output())")
        addTeardownBlock { _ = try? HostProcess("privacy", [udid, "reset"]).wait(timeout: 20) }
        let tv = try HostProcess("e2e", ["screen", "link", "--timeout", "300", "--base", Live.baseURL])
        addTeardownBlock { tv.stop() }

        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let room = lobbyCode(app)
        let link = try XCTUnwrap(tvCode(tv, number: 1), "the TV never got a link:\n\(tv.output())")

        el(app, "lobby.tv").tap()
        let prompt = el(app, "tv.prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: Live.t(10)), "no code entry")
        XCTAssertEqual(prompt.label, "Type the TV's code")
        XCTAssertFalse(el(app, "tv.scanner").exists, "a camera with the camera denied")

        // A wrong code (the alphabet's first letters, or its last if those are the TV's).
        type(app, link == "BCDFGH" ? "ZXWVTR" : "BCDFGH")
        let wrong = el(app, "tv.message")
        XCTAssertTrue(wrong.waitForExistence(timeout: Live.t(15)), "no word on a wrong code")
        XCTAssertEqual(wrong.label, "No TV with that code.")
        screenshot(app, "tv-wrong")

        XCTAssertTrue(until(5) { (self.value(self.el(app, "tv.code")) ?? "").isEmpty }, "the tiles didn't clear")
        type(app, link)
        XCTAssertTrue(el(app, "tv.linked").waitForExistence(timeout: Live.t(15)), "no On the TV: \(message(app))")
        XCTAssertTrue(until(15) { tv.output().contains("linked \(room)") }, "the TV wasn't linked:\n\(tv.output())")
        XCTAssertFalse(tv.output().contains("FAIL"), tv.output())
    }

    // MARK: helpers

    /// The backup code of the TV's `number`th link (`link <token> <code>` lines).
    private func tvCode(_ tv: HostProcess, number: Int) -> String? {
        var code: String?
        _ = until(30) {
            let links = tv.output().split(separator: "\n").filter { $0.hasPrefix("link ") }
            guard links.count >= number else { return false }
            code = links[number - 1].split(separator: " ").last.map(String.init)
            return true
        }
        return code
    }

    /// Types `code` on the sheet's keypad, then Show.
    private func type(_ app: XCUIApplication, _ code: String) {
        let first = el(app, "tv.key.\(code.first ?? "B")")
        XCTAssertTrue(first.waitForExistence(timeout: Live.t(10)), "no keypad")
        for c in code { el(app, "tv.key.\(c)").tap() }
        el(app, "tv.show").tap()
    }

    private func message(_ app: XCUIApplication) -> String {
        label(el(app, "tv.message")) ?? "(no message)"
    }
}
