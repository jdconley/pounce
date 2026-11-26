import XCTest

/// Hitting a laid group by drag: the card goes to the group under the finger and, on a run, to
/// the end it was dropped on (a natural goes where it fits). `-demo hit`: my play step, Leo's
/// run 4-5-6-7 is his group 2, and my hand is 2, 3, a Yarn and an 8; the fake server takes
/// each hit like the real one. The DEBUG `table.hit` probe reads
/// `<laid-group aim changes>|<last hit sent as seat.group.side>` (side `-` when none is sent).
/// A failed drag also prints `table.touches` (`<began>|<moved>|<ended>|<cancelled>|<fingers down>|<drag open>`):
/// a drag whose end never reached the app reads `1|n|0|0|1|1`.
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
        XCTAssertTrue(until(3) { self.value(probe)?.hasSuffix("|1.1.start") == true }, report(app, probe))
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix(": Yarn, wild; 4, gray; 5, gray; 6, tabby; 7, calico") == true },
                      "\(label(el(app, run)) ?? "-") \(report(app, probe))")
        XCTAssertGreaterThanOrEqual(aims(probe), 1, "the target never lit on the way")
        screenshot(app, "hit-yarn-start")

        // The 8 fits only above the run: dropped on its start half it still goes on the end.
        XCTAssertTrue(until(3) { self.handIndex(app, "8, gray") != nil })
        drag(app, card: "8, gray", toward: .start, of: run)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix("7, calico; 8, gray") == true }, "\(label(el(app, run)) ?? "-") \(report(app, probe))")
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, report(app, probe))
    }

    /// At the end a Yarn extends the run upward, and a card dropped on a group that can't
    /// take it goes nowhere.
    @MainActor
    func testYarnDroppedAtTheEndExtendsItUpAndARefusedDropStaysInHand() throws {
        let (app, probe) = launch()

        drag(app, card: "Yarn, wild", toward: .end, of: run)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix("7, calico; Yarn, wild") == true }, "\(label(el(app, run)) ?? "-") \(report(app, probe))")
        // The server's default end: no side on the wire, so an older server reads it the same.
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, value(probe) ?? "-")

        // The 3 onto Leo's 7s: refused, nothing sent, still in hand.
        XCTAssertTrue(until(3) { self.handIndex(app, "3, calico") != nil })
        drag(app, card: "3, calico", toward: .end, of: "table.group.1.0")
        XCTAssertTrue(until(3) { self.handIndex(app, "3, calico") != nil })
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, value(probe) ?? "-")
    }

    /// JD's bug: a card snapped into place on a group, and let go there it said it didn't fit
    /// (or went back to the hand). While a card is held the laid zone is drawn 1.1x bigger; the
    /// drop was aimed at the zone at rest, so near the edge of a group it had just snapped to
    /// the finger landed on the group beside it, or on nothing. The 8 fits only the run's end.
    @MainActor
    func testACardThatSnapsLandsThereWhereverItIsLetGo() throws {
        let (app, probe) = launch()
        let rest = groupFrames(app)
        let c = pilesCenter(app)
        let drawn = rest.mapValues { grown($0, about: c) }
        // A spot the drawn table snaps to the run that the table at rest gives another group
        // (or none), as far from both choices' edges as there is.
        let around = (drawn[run] ?? .zero).insetBy(dx: -16, dy: -16)
        let spot = grid(around, step: 1)
            .compactMap { p -> (p: CGPoint, margin: CGFloat)? in
                let now = nearest(p, drawn), then = nearest(p, rest)
                guard now.id == run, then.id != run else { return nil }
                return (p, min(now.margin, then.margin))
            }
            .max { $0.margin < $1.margin }
        guard let spot, spot.margin >= 2 else {
            return XCTFail("no spot the drawn run takes that the table at rest misses: \(rest) about \(c)")
        }
        print("HIT spot \(spot) rest \(rest) center \(c)")

        drag(app, card: "8, gray", to: spot.p)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix("7, calico; 8, gray") == true },
                      "\(label(el(app, run)) ?? "-") \(report(app, probe))")
        XCTAssertTrue(value(probe)?.hasSuffix("|1.1.-") == true, report(app, probe))
        XCTAssertGreaterThanOrEqual(aims(probe), 1, "the run never lit on the way")
    }

    /// JD: "for sets or runs where it only fits in one place, don't need to be precise." The 3
    /// fits only the start of Leo's run: let go on the bare rug, away from every group, it goes
    /// there. The Yarn fits several groups, so the same drop puts it nowhere.
    @MainActor
    func testACardThatFitsOnePlaceGoesThereFromTheRug() throws {
        let (app, probe) = launch()
        let rest = groupFrames(app)
        let c = pilesCenter(app)
        let drawn = Array(rest.values.map { grown($0, about: c) })
        let piles = [el(app, "table.deck").frame, el(app, "table.discard").frame]
        // The bare rug between the rows: the spot farthest from every group and both piles.
        let band = drawn.reduce(CGRect.null) { $0.union($1) }
        func clearance(_ p: CGPoint) -> CGFloat {
            (drawn + piles).map { f in hypot(max(f.minX - p.x, 0, p.x - f.maxX), max(f.minY - p.y, 0, p.y - f.maxY)) }.min() ?? 0
        }
        guard let spot = grid(band, step: 4).max(by: { clearance($0) < clearance($1) }), clearance(spot) > 30 else {
            return XCTFail("no bare rug between the groups: \(rest)")
        }

        drag(app, card: "Yarn, wild", to: spot)
        XCTAssertTrue(until(3) { self.handIndex(app, "Yarn, wild") != nil }, report(app, probe))
        XCTAssertTrue(value(probe)?.hasSuffix("|-") == true, "a Yarn that fits several groups went to one: \(report(app, probe))")

        drag(app, card: "3, calico", to: spot)
        XCTAssertTrue(until(3) { self.label(el(app, self.run))?.hasSuffix(": 3, calico; 4, gray; 5, gray; 6, tabby; 7, calico") == true },
                      "\(label(el(app, run)) ?? "-") \(report(app, probe))")
        screenshot(app, "hit-from-the-rug")
    }

    // MARK: helpers

    private enum End { case start, end }

    /// Every laid group's frame on screen, at rest (no card held).
    @MainActor private func groupFrames(_ app: XCUIApplication) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for seat in 0..<4 {
            for g in 0..<4 {
                let e = el(app, "table.group.\(seat).\(g)")
                if e.exists { frames["table.group.\(seat).\(g)"] = e.frame }
            }
        }
        return frames
    }

    /// What the laid zone grows about while a card is held: between deck and discard.
    @MainActor private func pilesCenter(_ app: XCUIApplication) -> CGPoint {
        let deck = el(app, "table.deck").frame, discard = el(app, "table.discard").frame
        return CGPoint(x: (deck.midX + discard.midX) / 2, y: deck.midY)
    }

    /// `f` as drawn while a card is held: 1.1x about `c`.
    private func grown(_ f: CGRect, about c: CGPoint) -> CGRect {
        CGRect(x: c.x + (f.minX - c.x) * 1.1, y: c.y + (f.minY - c.y) * 1.1, width: f.width * 1.1, height: f.height * 1.1)
    }

    /// Points across `f`, `step` apart.
    private func grid(_ f: CGRect, step: CGFloat) -> [CGPoint] {
        stride(from: f.minY, through: f.maxY, by: step).flatMap { y in
            stride(from: f.minX, through: f.maxX, by: step).map { CGPoint(x: $0, y: y) }
        }
    }

    /// The group whose frame is nearest `p` within 16 pt (`LaidTargets.target`; nil: none), and
    /// how far the finger is from changing that answer.
    private func nearest(_ p: CGPoint, _ frames: [String: CGRect]) -> (id: String?, margin: CGFloat) {
        let reach: CGFloat = 16
        let near = frames.map { id, f in
            (id: id, d: hypot(max(f.minX - p.x, 0, p.x - f.maxX), max(f.minY - p.y, 0, p.y - f.maxY)))
        }.sorted { $0.d < $1.d }
        guard let best = near.first, best.d <= reach else { return (nil, (near.first?.d ?? .infinity) - reach) }
        return (best.id, min(near.dropFirst().first?.d ?? .infinity, reach + 1) - best.d)
    }

    /// Drags the hand card labelled `card` and lets go with the finger at `aim`.
    @MainActor private func drag(_ app: XCUIApplication, card: String, to aim: CGPoint) {
        guard let index = handIndex(app, card) else { return XCTFail("\(card) is not in the hand") }
        let h = el(app, "table.hand.\(index)").frame
        let start = point(app, h.minX + min(h.width, 24) / 2, h.midY + 10)
        start.press(forDuration: 0.15, thenDragTo: point(app, aim.x, aim.y), withVelocity: 500,
                    thenHoldForDuration: Live.pace(0.6))
    }

    @MainActor private func launch() -> (XCUIApplication, XCUIElement) {
        let app = Live.demo("hit")
        app.launchArguments += ["-settings.soundOn", "<false/>"]
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

    /// The hit probe and the touches the table was handed, for a failure message.
    @MainActor private func report(_ app: XCUIApplication, _ probe: XCUIElement) -> String {
        "hit \(value(probe) ?? "-"), touches \(value(el(app, "table.touches")) ?? "-")"
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
