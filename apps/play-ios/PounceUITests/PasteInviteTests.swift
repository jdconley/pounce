import UIKit
import XCTest

/// Invites that survive the install (first-run funnel, part 2): the invite page copies the link,
/// and on first launch Home offers the system paste control, which opens the table exactly as a
/// tapped link would. Join offers it too, and says when a code has no table. Against the dev
/// server; the runner writes the simulator's pasteboard, as the invite page would.
@MainActor
final class PasteInviteTests: XCTestCase {
    override func tearDown() {
        // Leave nothing for the next test's Home (staged runs ignore it anyway).
        UIPasteboard.general.items = []
        super.tearDown()
    }

    private func launch() -> XCUIApplication {
        let app = Live.app()
        app.launchArguments += ["-paste-invite", "-no-tips"]
        app.launch()
        return app
    }

    /// A lobby on the dev server, made by another phone: its code.
    private func remoteTable() async throws -> String {
        let base = URL(string: Live.baseURL)!
        var mint = URLRequest(url: base.appendingPathComponent("v1/devices"))
        mint.httpMethod = "POST"
        let (minted, _) = try await URLSession.shared.data(for: mint)
        let token = try XCTUnwrap((try JSONSerialization.jsonObject(with: minted) as? [String: Any])?["token"] as? String)
        var create = URLRequest(url: base.appendingPathComponent("v1/rooms"))
        create.httpMethod = "POST"
        create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = Data(#"{"game":"cat-tower"}"#.utf8)
        let (made, _) = try await URLSession.shared.data(for: create)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: made) as? [String: Any])?["code"] as? String)
    }

    func testFirstLaunchPastesTheCopiedInviteAndLandsAtTheTable() async throws {
        let code = try await remoteTable()
        UIPasteboard.general.string = "https://play.conleychaos.com/j/\(code)"
        let app = launch()
        onboard(app)
        let card = el(app, "card-pasteInvite")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(10)), "Home didn't offer to paste the invite")
        screenshot(app, "paste-invite-home")
        el(app, "pasteInvite.paste").tap()
        XCTAssertTrue(el(app, "lobby.seat.0").waitForExistence(timeout: Live.t(20)), "pasting didn't open the table")
        XCTAssertTrue(until(Live.t(5)) { !card.exists }, "the card stayed up")
        // Home doesn't offer the same pasteboard again.
        el(app, "lobby.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)))
        XCTAssertFalse(card.waitForExistence(timeout: 2), "the pasted invite was offered again")
    }

    func testNotNowPutsItAway() {
        UIPasteboard.general.string = "https://play.conleychaos.com/j/BCDFG"
        let app = launch()
        onboard(app)
        let card = el(app, "card-pasteInvite")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(10)))
        el(app, "pasteInvite.notNow").tap()
        XCTAssertTrue(until(Live.t(5)) { !card.exists }, "Not now didn't close the card")
        // Home takes taps again.
        el(app, "home.join").tap()
        XCTAssertTrue(el(app, "screen-join").waitForExistence(timeout: Live.t(10)), "Home is still covered")
    }

    func testSomethingElsePastedSaysItIsNotAnInvite() {
        UIPasteboard.general.string = "https://example.com/recipes/lasagna"
        let app = launch()
        onboard(app)
        XCTAssertTrue(el(app, "card-pasteInvite").waitForExistence(timeout: Live.t(10)))
        el(app, "pasteInvite.paste").tap()
        let line = el(app, "pasteInvite.line")
        XCTAssertTrue(until(Live.t(5)) { line.label == "That's not an invite." }, "said: \(line.label)")
        XCTAssertTrue(el(app, "card-pasteInvite").exists)
    }

    func testNoLinkNoOffer() {
        UIPasteboard.general.string = "see you at dinner"
        let app = launch()
        onboard(app)
        XCTAssertFalse(el(app, "card-pasteInvite").waitForExistence(timeout: 3), "offered to paste without a link")
    }

    func testJoinPastesALinkAndSaysWhenACodeHasNoTable() throws {
        let app = launch()
        onboard(app)
        el(app, "home.join").tap()
        XCTAssertTrue(el(app, "screen-join").waitForExistence(timeout: Live.t(10)))
        XCTAssertFalse(el(app, "join.paste").exists, "Paste with nothing copied")

        // A wrong code, typed: the tiles shake clear and the words stay until the next key.
        for c in "BCDFG" { el(app, "join.key.\(c)").tap() }
        let wrong = el(app, "join.wrong")
        let locked = el(app, "state.locked")
        XCTAssertTrue(until(Live.t(15)) { wrong.exists || locked.exists }, "a wrong code said nothing")
        // The dev server allows 20 wrong codes an hour from one address (every simulator shares it).
        if locked.exists { throw XCTSkip("the dev server's wrong-code limit for this address is used up; try again in an hour") }
        XCTAssertEqual(wrong.label, "No table with that code.")
        screenshot(app, "join-wrong-code")
        el(app, "join.key.H").tap()
        XCTAssertTrue(until(Live.t(3)) { !wrong.exists }, "the words stayed after typing")
        el(app, "join.key.delete").tap()

        // A link copied while Join is open: Paste appears when the app comes back, and opens it.
        UIPasteboard.general.string = "Come play at our table https://play.conleychaos.com/j/BCDFH"
        XCUIDevice.shared.press(.home)
        app.activate()
        let paste = el(app, "join.paste")
        XCTAssertTrue(paste.waitForExistence(timeout: Live.t(10)), "Join didn't offer to paste the link")
        screenshot(app, "join-paste")
        paste.tap()
        // No table behind it: back on Join, with the words.
        XCTAssertTrue(wrong.waitForExistence(timeout: Live.t(15)), "the pasted code wasn't checked")
    }

    /// A pounce link opened with no connection: a card says so and offers Try again, instead of
    /// a thump and nothing on screen.
    func testAPounceLinkWithNoConnectionSaysSo() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-no-tips", "-open-link", "pounce-dev://p/\(String(repeating: "A", count: 22))"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = "http://127.0.0.1:9"  // refused
        app.launch()
        onboard(app)
        let card = el(app, "card-offlineInvite")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(20)), "nothing on screen for an unreachable invite")
        screenshot(app, "pounce-link-offline")
        el(app, "offlineInvite.retry").tap()
        // Still no connection: the card comes back.
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(20)))
        el(app, "offlineInvite.close").tap()
        XCTAssertTrue(until(Live.t(5)) { !card.exists }, "Close didn't close it")
    }
}
