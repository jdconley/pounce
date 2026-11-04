import XCTest

/// Hitting a laid group by drag: the card goes to the group under the finger and, on a run, to
/// the end it was dropped on (a natural goes where it fits). `-demo hit`: my play step, Leo's
/// run 4-5-6-7 is his group 2, and my hand is 2, 3, a Yarn and an 8; the fake server takes
/// each hit like the real one. The DEBUG `table.hit` probe reads
/// `<laid-group aim changes>|<last hit sent as seat.group.side>` (side `-` when none is sent).
class HitTests: XCTestCase {
    private let run = "table.group.1.1"

    override func setUp() {
        continueAfterFailure = false
    }

    /// JD's bug: a Yarn dropped at the start of a run went to its end.
    @MainActor
    func testYarnDroppedAtTheStartOfARunExtendsItDown() throws {
        let (app, probe) = launch()
        XCTAssertTrue(label(el(app, run))?.hasSuffix(": 4, gray; 5, gray; 6, tabby; 7, calico") == true, "\(label(el(app, run)) ?? "-")")

        drag(app, card: "Yarn, wild", toward: .start, of: run)
        XCTAssertTrue(until(3) { self.value(probe)?.hasSuffix("|1.1.start") == true }, value(probe) ?? "-")
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix(": Yarn, wild; 4, gray; 5, gray; 6, tabby; 7, calico") == true },
                      label(el(app, run)) ?? "-")
        XCTAssertGreaterThanOrEqual(aims(probe), 1, "the target never lit on the way")
        screenshot(app, "hit-yarn-start")

        // The 8 fits only above the run: dropped on its start half it still goes on the end.
        XCTAssertTrue(until(3) { self.handIndex(app, "8, gray") != nil })
        drag(app, card: "8, gray", toward: .start, of: run)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix("7, calico; 8, gray") == true }, label(el(app, run)) ?? "-")
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, value(probe) ?? "-")
    }

    /// At the end a Yarn extends the run upward, and a card dropped on a group that can't
    /// take it goes nowhere.
    @MainActor
    func testYarnDroppedAtTheEndExtendsItUpAndARefusedDropStaysInHand() throws {
        let (app, probe) = launch()

        drag(app, card: "Yarn, wild", toward: .end, of: run)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix("7, calico; Yarn, wild") == true }, label(el(app, run)) ?? "-")
        // The server's default end: no side on the wire, so an older server reads it the same.
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, value(probe) ?? "-")

        // The 3 onto Leo's 7s: refused, nothing sent, still in hand.
        XCTAssertTrue(until(3) { self.handIndex(app, "3, calico") != nil })
        drag(app, card: "3, calico", toward: .end, of: "table.group.1.0")
        XCTAssertTrue(until(3) { self.handIndex(app, "3, calico") != nil })
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, value(probe) ?? "-")
    }

    // MARK: helpers

    private enum End { case start, end }

    @MainActor private func launch() -> (XCUIApplication, XCUIElement) {
        let app = Live.demo("hit")
        app.launch()
        let probe = el(app, "table.hit")
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(el(app, run).waitForExistence(timeout: 5))
        return (app, probe)
    }

    @MainActor private func aims(_ probe: XCUIElement) -> Int {
        Int((value(probe) ?? "").split(separator: "|").first ?? "") ?? -1
    }

    @MainActor private func handIndex(_ app: XCUIApplication, _ card: String) -> Int? {
        var i = 0
        while let l = label(el(app, "table.hand.\(i)")) {
            if l == card { return i }
            i += 1
        }
        return nil
    }

    @MainActor private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Drags the hand card labelled `card` so the finger ends a quarter of the way into group
    /// `id` from its `end`. While a card is held the laid zone grows 1.1x about the piles'
    /// center (between deck and discard), so the aim is scaled the same way.
    @MainActor private func drag(_ app: XCUIApplication, card: String, toward end: End, of id: String) {
        guard let index = handIndex(app, card) else { return XCTFail("\(card) is not in the hand") }
        let f = el(app, id).frame
        let deck = el(app, "table.deck").frame, discard = el(app, "table.discard").frame
        let center = CGPoint(x: (deck.midX + discard.midX) / 2, y: deck.midY)
        let x = end == .start ? f.minX + f.width * 0.25 : f.maxX - f.width * 0.25
        let aim = CGPoint(x: center.x + (x - center.x) * 1.1, y: center.y + (f.midY - center.y) * 1.1)
        let h = el(app, "table.hand.\(index)").frame
        let start = point(app, h.minX + min(h.width, 24) / 2, h.midY + 10)
        start.press(forDuration: 0.15, thenDragTo: point(app, aim.x, aim.y), withVelocity: 500,
                    thenHoldForDuration: Live.pace(0.6))
    }
}
