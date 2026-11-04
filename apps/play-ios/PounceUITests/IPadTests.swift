import UIKit
import XCTest

/// iPad only (skipped on a phone): the table re-lays out for landscape and keeps everything it
/// holds when the iPad turns mid-game, and the drag, hit-preview, turn-cue and name suites pass
/// again with the iPad on its side (`Landscape*` below re-run them).
@MainActor
func requireIPad() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
}

extension XCTestCase {
    /// Turns the iPad on its side for the rest of the test, and back upright after it.
    func turnLandscape() throws {
        try MainActor.assumeIsolated {
            try requireIPad()
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
    }
}

final class IPadRotationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Needs the dev server: a game against a bot. Turned on its side before the draw, upright
    /// after it and on its side again for the discard; the hand, its order, the step and the
    /// turn survive every turn of the iPad, and the table fills the new shape each time.
    @MainActor
    func testRotatingMidTurnKeepsTheTable() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        seatMenu(app, seat: 1, "bot")
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(10) { seat1.label.contains("bot") }, "no bot on seat 1: \(seat1.label)")
        el(app, "lobby.start").tap()

        let mine = untilSnap(app, 40) { snap in
            dismissPriming(app, snap)
            guard snap.value("table.turn") == "mine", let d = snap.debug else { return false }
            return d.settled && d.step == "draw" && snap.label("table.hand.0") != "Card"
        }
        let start = try XCTUnwrap(mine, "my turn never came")
        let hand = handLabels(start)
        XCTAssertEqual(hand.count, 10, "\(hand)")
        let tall = try XCTUnwrap(start.frame("table.deck"))

        // On its side before the draw.
        let wide = try turn(app, to: .landscapeLeft, expecting: hand, step: "draw")
        let wideDeck = try XCTUnwrap(wide.frame("table.deck"))
        XCTAssertNotEqual(wideDeck, tall, "the table didn't lay out again for landscape")
        screenshot(app, "ipad-rotation-landscape-draw")
        tap(app, wideDeck)
        let drawn = try XCTUnwrap(untilSnap(app, 15) { $0.debug.map { $0.step == "play" && $0.settled } ?? false },
                                  "no draw in landscape: \(String(describing: UISnap(app)?.debug))")
        let held = handLabels(drawn)
        XCTAssertEqual(held.count, 11, "\(held)")

        // Upright mid-turn, then on its other side: the drawn hand and the play step stay.
        _ = try turn(app, to: .portrait, expecting: held, step: "play")
        screenshot(app, "ipad-rotation-portrait-play")
        let back = try turn(app, to: .landscapeRight, expecting: held, step: "play")

        // Discard in landscape; the turn passes.
        let pick = (0..<held.count).first { !held[$0].hasPrefix("Cucumber") } ?? 0
        tap(app, try XCTUnwrap(back.frame("table.hand.\(pick)")))
        Thread.sleep(forTimeInterval: Live.pace(0.5))
        tap(app, try XCTUnwrap(back.frame("table.discard")))
        if !until(5, { self.value(self.el(app, "table.turn")) == "other" }) {
            // A hand of only Cucumbers: it waits for a cat to aim at.
            if let cat = UISnap(app)?.items.first(where: { $0.key.hasPrefix("table.opponent.") && $0.value.value == "glowing" }) {
                tap(app, cat.value.frame)
            }
        }
        XCTAssertNotNil(untilSnap(app, 15) { s in
            s.value("table.turn") == "other" || (s.debug.map { $0.step == "draw" && $0.handCount == 10 && $0.settled } ?? false)
        }, "the turn didn't pass in landscape: \(String(describing: UISnap(app)?.debug))")
        screenshot(app, "ipad-rotation-after-discard")
    }

    /// Turns the iPad and waits for the table to settle in the new shape; checks the hand (in
    /// order), the step, and that every hand card and both piles are on screen.
    @MainActor
    private func turn(_ app: XCUIApplication, to orientation: UIDeviceOrientation, expecting hand: [String],
                      step: String) throws -> UISnap {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        var screen = CGRect.zero
        let snap = try XCTUnwrap(untilSnap(app, 10) { s in
            // Done turning: the window is whole again (mid-turn its frame is a sliver) and stays put.
            let window = app.windows.firstMatch.frame
            defer { screen = window }
            guard window == screen, min(window.width, window.height) > 600,
                  (window.width > window.height) == landscape, let d = s.debug, d.settled else { return false }
            return handLabels(s) == hand
        }, "the table didn't settle \(landscape ? "in landscape" : "upright") with the same hand: "
            + "\(UISnap(app).map(handLabels) ?? []) vs \(hand)")
        XCTAssertEqual(snap.debug?.step, step)
        for i in 0..<hand.count {
            let f = try XCTUnwrap(snap.frame("table.hand.\(i)"))
            XCTAssertTrue(screen.contains(CGPoint(x: f.midX, y: f.midY)), "hand card \(i) off screen: \(f) in \(screen)")
        }
        for pile in ["table.deck", "table.discard"] {
            let f = try XCTUnwrap(snap.frame(pile))
            XCTAssertTrue(screen.contains(f), "\(pile) off screen: \(f) in \(screen)")
        }
        return snap
    }

    @MainActor
    private func handLabels(_ snap: UISnap) -> [String] {
        var labels: [String] = []
        while let label = snap.label("table.hand.\(labels.count)") { labels.append(label) }
        return labels
    }
}

/// Drag-to-snap in the hand, with the iPad on its side.
final class LandscapeReorderTests: ReorderTests {
    override func setUpWithError() throws { try turnLandscape() }
}

/// Hit previews and drops on laid groups, with the iPad on its side.
final class LandscapeHitTests: HitTests {
    override func setUpWithError() throws { try turnLandscape() }
}

/// The turn cue, with the iPad on its side.
final class LandscapeTurnCueTests: TurnCueTests {
    override func setUpWithError() throws { try turnLandscape() }
}

/// Player names at the table, with the iPad on its side.
final class LandscapeNamesTests: NamesTests {
    override func setUpWithError() throws { try turnLandscape() }
}

/// Table names in the lobby, on Home and at the table, with the iPad on its side.
final class LandscapeTableNameTests: TableNameTests {
    override func setUpWithError() throws { try turnLandscape() }
}
