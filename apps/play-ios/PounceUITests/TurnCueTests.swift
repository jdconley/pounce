import XCTest

/// The start of your turn is unmissable (TurnCue.swift, TurnCueView.swift): "Your turn" plays
/// when this phone's turn comes, stays until the table is touched, and comes back when the app
/// returns from the background on that turn. Someone else's turn gets no label: their ring glows.
class TurnCueTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Needs the dev server: a game against a bot, played by taps.
    @MainActor
    func testYourTurnCueShowsUntilYouDraw() throws {
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        seatMenu(app, seat: 1, "bot")
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(10) { seat1.label.contains("bot") }, "no bot on seat 1: \(seat1.label)")
        el(app, "lobby.start").tap()

        // My turn: the cue is up, and it says so.
        var mine: UISnap?
        XCTAssertTrue(until(40) {
            guard let snap = UISnap(app) else { return false }
            dismissPriming(app, snap)
            guard snap.value("table.turn") == "mine", let d = snap.debug, d.settled, d.step == "draw" else { return false }
            mine = snap
            return snap.exists("turncue.mine")
        }, "no Your turn cue on my turn: \(String(describing: mine?.items.keys.sorted()))")
        let cue = try XCTUnwrap(mine)
        XCTAssertTrue(cue.label("turncue.mine")?.hasPrefix("Your turn") ?? false, "cue says \(String(describing: cue.label("turncue.mine")))")
        screenshot(app, "turn-cue-mine")

        // It never stands in the way: the deck under it takes the tap, and the cue goes.
        tap(app, try XCTUnwrap(cue.frame("table.deck")))
        let drawn = untilSnap(app, 15) { s in
            !s.exists("turncue.mine") && (s.debug.map { $0.step == "play" && $0.settled } ?? false)
        }
        XCTAssertNotNil(drawn, "the cue didn't go after the draw: \(String(describing: UISnap(app)?.debug))")

        // Back from the background on my turn: it plays again, until the next touch.
        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackgroundSuspended, timeout: Live.t(5))
        app.activate()
        XCTAssertNotNil(untilSnap(app, 15) { $0.exists("turncue.mine") }, "no cue after coming back on my turn")
        let back = try XCTUnwrap(UISnap(app))
        XCTAssertEqual(back.label("turncue.mine"), "Your turn!", "after the draw it shouldn't say to draw")
        tap(app, try XCTUnwrap(back.frame("table.hand.0")))  // picks a card up: a touch on the table
        XCTAssertNotNil(untilSnap(app, 10) { !$0.exists("turncue.mine") }, "a touch didn't put the cue away")
    }

    /// Someone else's turn: no label at all (their cat's glowing ring says it), and no "Your turn".
    @MainActor
    func testNoLabelForTheirTurn() throws {
        let app = Live.demo("other")
        app.launch()
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(3)) { dismissPriming(app) }
        XCTAssertNotNil(untilSnap(app, 15) { $0.value("table.turn") == "other" }, "not someone else's turn")
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        XCTAssertFalse(el(app, "turncue.theirs").exists, "a label for the other seat's turn")
        XCTAssertFalse(el(app, "turncue.mine").exists)
        screenshot(app, "turn-cue-theirs")
    }
}
