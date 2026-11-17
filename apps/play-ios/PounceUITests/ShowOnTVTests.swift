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

    /// Camera permission denied: the code entry works and nothing crashes. (The simulator has no
    /// scanner, so it would show the code entry whatever the permission; which view a denied,
    /// restricted or unasked camera gets is `TVSheetStartTests`.) A wrong code says so, and the
    /// right one still works.
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

    /// A TV's link opened before this phone has a player: onboarding first, then Home says "Pick
    /// a table for the TV.", and the table made from Home's games goes on the TV.
    func testATVLinkBeforeOnboardingGoesOnTheTableMadeFromHome() throws {
        let tv = try HostProcess("e2e", ["screen", "link", "--timeout", "300", "--base", Live.baseURL])
        addTeardownBlock { tv.stop() }
        let token = try XCTUnwrap(tvToken(tv), "the TV never got a link:\n\(tv.output())")

        let app = Live.app()
        app.launchArguments += ["-open-link", "pounce-dev://tv/\(token)"]
        app.launch()
        onboard(app)
        let cue = el(app, "home.tvCue")
        XCTAssertTrue(cue.waitForExistence(timeout: Live.t(10)), "no Pick a table for the TV on Home")
        XCTAssertEqual(cue.label, "Pick a table for the TV.")
        screenshot(app, "tv-home-cue")

        el(app, "home.newGame").tap()
        XCTAssertTrue(el(app, "tv.linked").waitForExistence(timeout: Live.t(20)), "no On the TV: \(message(app))")
        XCTAssertTrue(until(10) { !self.el(app, "sheet-tv").exists }, "the sheet stayed up")
        let code = lobbyCode(app)
        XCTAssertTrue(until(15) { tv.output().contains("linked \(code)") }, "the TV wasn't linked:\n\(tv.output())")
        XCTAssertFalse(el(app, "home.tvCue").exists)
        XCTAssertFalse(tv.output().contains("FAIL"), tv.output())
    }

    /// A TV's link opened while a lobby is up: that table goes on the TV.
    func testATVLinkOpenedInALobbyPutsThatTableOnTheTV() throws {
        let tv = try HostProcess("e2e", ["screen", "link", "--timeout", "300", "--base", Live.baseURL])
        addTeardownBlock { tv.stop() }
        let token = try XCTUnwrap(tvToken(tv), "the TV never got a link:\n\(tv.output())")

        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        // Opened in the running app (`XCUIApplication.open` relaunches it, losing the test's data).
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "not on a simulator")
        let opened = try HostProcess("openurl", [udid, "pounce-dev://tv/\(token)"])
        // The system may ask before handing a custom scheme's link over (only the first time).
        // "On the TV" shows for a moment, so look for it while answering that.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        let linked = el(app, "tv.linked")
        var sawLinked = false
        XCTAssertTrue(until(20) {
            if open.exists { open.tap() }
            if linked.exists { sawLinked = true }
            return sawLinked
        }, "no On the TV: \(message(app))")
        XCTAssertEqual(opened.wait(timeout: 20), 0, "couldn't open the link: \(opened.output())")
        XCTAssertTrue(until(15) { tv.output().contains("linked \(code)") }, "the TV wasn't linked:\n\(tv.output())")
        XCTAssertFalse(tv.output().contains("FAIL"), tv.output())
    }

    // MARK: helpers

    /// The token of the TV's first link.
    private func tvToken(_ tv: HostProcess) -> String? {
        var token: String?
        _ = until(30) {
            guard let line = tv.output().split(separator: "\n").first(where: { $0.hasPrefix("link ") }) else { return false }
            let parts = line.split(separator: " ")
            token = parts.count == 3 ? String(parts[1]) : nil
            return true
        }
        return token
    }

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
