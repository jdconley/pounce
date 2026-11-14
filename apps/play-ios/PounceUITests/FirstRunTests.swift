import XCTest

/// The first-run funnel, part 1 (`docs/superpowers/specs/2026-11-13-first-run-funnel-design.md`):
/// a name in one tap, one tip on Home's first visit with Practice in reach, a first table that
/// opens ready to play with a House Cat, and an invited guest who sees who saved them a seat and
/// takes the House Cat's place. The lobby and guest tests need the dev server; the guest test
/// also needs the host broker (`scripts/ui-tests.sh` starts both).
@MainActor
final class FirstRunTests: XCTestCase {
    private var host: HostProcess?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        host?.stop()
        host = nil
    }

    // MARK: the name screen

    /// A suggested name and a cat are already chosen: the check alone goes on to Home.
    func testTheNameIsReadyInOneTap() {
        let app = Live.app()
        app.launch()
        let name = el(app, "pickcat.name")
        XCTAssertTrue(name.waitForExistence(timeout: Live.t(15)), "no name screen")
        XCTAssertFalse((value(name) ?? "").isEmpty, "no suggested name")
        XCTAssertEqual(app.keyboards.count, 0, "the keyboard covers the cats on arrival")
        el(app, "pickcat.confirm").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "the check didn't go on")
    }

    /// Tapping the suggested name selects it, so typing replaces it, and every cat stays above
    /// the keyboard.
    func testTypingReplacesTheNameAndKeepsTheCatsInView() {
        let app = Live.app()
        app.launch()
        let name = el(app, "pickcat.name")
        XCTAssertTrue(name.waitForExistence(timeout: Live.t(15)), "no name screen")
        name.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: Live.t(5)), "no keyboard")
        Thread.sleep(forTimeInterval: Live.pace(1))  // the layout settles
        let top = keyboard.frame.minY
        for i in 0..<8 {
            let cat = el(app, "pickcat.cat.\(i)")
            XCTAssertTrue(cat.isHittable, "cat \(i) can't be tapped with the keyboard up")
            XCTAssertLessThanOrEqual(cat.frame.maxY, top + 1, "cat \(i) is under the keyboard")
        }
        name.typeText("Mia")
        XCTAssertEqual(value(name), "Mia", "typing didn't replace the suggestion")
        // A cat tap puts the keyboard away; the check goes on with the typed name.
        el(app, "pickcat.cat.5").tap()
        _ = until(4) { app.keyboards.count == 0 }
        el(app, "pickcat.confirm").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
    }

    // MARK: Home's first visit

    /// One tip, not three in a row; Practice sits in the dock, never under it.
    func testHomeFirstVisitShowsOneTipAndPracticeInTheDock() {
        let app = Live.app()
        app.launchArguments += ["-seed-people", "-ui-tips"]
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(15)), "no Home")
        let tip = app.descendants(matching: .any).matching(identifier: "tip").firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: Live.t(8)), "no first tip")
        tip.tap()
        XCTAssertTrue(until(4) { !tip.exists }, "the tip stayed up")
        // Long enough for the next tip's settle and gap at any speed.
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertFalse(tip.exists, "a second tip followed the first")
        let practice = el(app, "home.practice")
        let dock = el(app, "home.dock")
        XCTAssertTrue(practice.waitForExistence(timeout: Live.t(5)), "no Practice")
        XCTAssertTrue(practice.isHittable, "Practice can't be tapped")
        XCTAssertTrue(dock.frame.contains(CGPoint(x: practice.frame.midX, y: practice.frame.midY)), "Practice is not in the dock")
    }

    // MARK: the lobby

    /// A first table opens with a House Cat in seat 1, so Start is lit; the tray offers the four
    /// ways to fill the next seat, and Same room shows the QR code with a seat open for it.
    func testAFirstTableIsReadyToPlay() {
        let app = Live.app()
        app.launchArguments += ["-house-cat"]
        app.launch()
        onboard(app)
        newGame(app)
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(15) { seat1.label.contains("bot") }, "no House Cat on seat 1: \(seat1.label)")
        let start = el(app, "lobby.start")
        XCTAssertTrue(until(5) { value(start) == nil || value(start) == "" }, "Start isn't ready: \(value(start) ?? "")")
        for way in ["lobby.qr", "lobby.share", "lobby.here", "lobby.bot"] {
            XCTAssertTrue(el(app, way).exists, "no \(way) in the tray")
        }
        XCTAssertTrue(el(app, "lobby.code").exists, "no room code")
        el(app, "lobby.qr").tap()
        XCTAssertTrue(el(app, "lobby.qrcode").waitForExistence(timeout: Live.t(5)), "no QR code")
        let seat2 = el(app, "lobby.seat.2")
        XCTAssertTrue(until(10) { seat2.label.contains("Open seat") }, "no seat open for the room: \(seat2.label)")
        // Two cats and an open seat: Start still deals, after one question.
        start.tap()
        XCTAssertTrue(el(app, "lobby.start.confirm").waitForExistence(timeout: Live.t(5)), "no start question")
        el(app, "lobby.start.wait").tap()
    }

    // MARK: an invited guest

    /// Grandma's table, with a House Cat beside her: the guest's name screen says who saved the
    /// seat, and the guest takes the House Cat's place, with the table (not the host's sharing
    /// controls) up front.
    func testAGuestSeesWhoSavedTheirSeatAndTakesIt() throws {
        host = try HostProcess("e2e", ["host", "--name", "Grandma", "--cat", "4", "--house-cat", "--timeout", "300",
                                       "--base", Live.baseURL])
        var code = ""
        XCTAssertTrue(until(30) {
            code = host?.output().split(separator: "\n").first { $0.hasPrefix("room ") }.map { String($0.dropFirst(5)) } ?? ""
            return code.count == 5 && host?.output().contains("seated as") == true
        }, "no table from the host: \(host?.output() ?? "")")

        let app = Live.app()
        app.launchArguments += ["-open-link", "pounce-dev://j/\(code)"]
        app.launch()
        let invite = el(app, "pickcat.invite")
        XCTAssertTrue(invite.waitForExistence(timeout: Live.t(20)), "no invite line on the name screen")
        XCTAssertTrue(invite.label.contains("Grandma saved you a seat"), "wrong invite line: \(invite.label)")
        el(app, "pickcat.confirm").tap()

        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(seat1.waitForExistence(timeout: Live.t(20)), "no lobby")
        XCTAssertTrue(until(15) { seat1.label.contains("on this phone") }, "the guest didn't take the House Cat's seat: \(seat1.label)")
        XCTAssertTrue(until(15) { self.host?.output().contains("guest seated 1") == true }, "the host never saw the guest")
        XCTAssertTrue(el(app, "lobby.add").exists, "no Add a player")
        XCTAssertFalse(el(app, "lobby.qr").exists, "the host's tray is up front for a guest")
    }
}
