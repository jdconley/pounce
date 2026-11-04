import XCTest

/// Live hand reorder: while a card is dragged over the hand, the fan holds open the slot it
/// will land in, and letting go puts it exactly there. `-demo table`: Mia's ten-card hand, face
/// up. The DEBUG `table.drag` probe reads `<target-slot changes>|<slot the last reorder landed in>`.
class ReorderTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDraggedCardLandsInTheSlotTheFanHeldOpen() throws {
        let app = Live.demo("table")
        app.launch()
        let probe = el(app, "table.drag")
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        dismissPrimingIfShown(app)

        let before = handLabels(app)
        XCTAssertEqual(before.count, 10, "\(before)")
        XCTAssertEqual(value(probe), "0|-1")

        // Card 0 to slot 6: the hand reads the other nine with it seventh.
        drag(app, card: 0, toSlot: 6, of: before.count)
        var expected = before
        expected.insert(expected.removeFirst(), at: 6)
        XCTAssertTrue(until(3) { self.handLabels(app) == expected }, "\(handLabels(app)) != \(expected)")
        let (changes, landed) = drag(probe)
        XCTAssertEqual(landed, 6)
        XCTAssertGreaterThanOrEqual(changes, 1, "the target slot never changed on the way")
        screenshot(app, "reorder-landed")

        // And back the other way: the last card to slot 1.
        drag(app, card: 9, toSlot: 1, of: expected.count)
        expected.insert(expected.removeLast(), at: 1)
        XCTAssertTrue(until(3) { self.handLabels(app) == expected }, "\(handLabels(app)) != \(expected)")
        XCTAssertEqual(drag(probe).landed, 1)
    }

    /// A card dragged out of the hand and dropped on nothing goes back where it was.
    @MainActor
    func testDraggingOutOfTheHandLeavesTheOrder() throws {
        let app = Live.demo("table")
        app.launch()
        let probe = el(app, "table.drag")
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        dismissPrimingIfShown(app)

        let before = handLabels(app)
        let deck = el(app, "table.deck").frame
        let start = grabPoint(app, card: 3)
        start.press(forDuration: 0.15, thenDragTo: point(app, deck.midX, deck.midY), withVelocity: 600,
                    thenHoldForDuration: Live.pace(0.5))
        XCTAssertTrue(until(3) { self.handLabels(app) == before }, "\(handLabels(app)) != \(before)")
        XCTAssertEqual(drag(probe).landed, -1, "a drop outside the hand reordered it")
    }

    // MARK: helpers

    @MainActor private func dismissPrimingIfShown(_ app: XCUIApplication) {
        // A fresh simulator has no push answer yet, so the table puts the priming screen up.
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
    }

    @MainActor private func handLabels(_ app: XCUIApplication) -> [String] {
        var labels: [String] = []
        while let label = label(el(app, "table.hand.\(labels.count)")) { labels.append(label) }
        return labels
    }

    @MainActor private func drag(_ probe: XCUIElement) -> (changes: Int, landed: Int) {
        let parts = (value(probe) ?? "").split(separator: "|").compactMap { Int($0) }
        return (parts.first ?? -1, parts.count > 1 ? parts[1] : -2)
    }

    @MainActor private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// The middle of hand card `index`'s visible strip (frames are cut at the next card's edge).
    /// Not its left edge: a frame is the tilted card's bounding box, and on big (iPad) cards the
    /// box's corner sticks out well past the card.
    @MainActor private func grabPoint(_ app: XCUIApplication, card index: Int) -> XCUICoordinate {
        let f = el(app, "table.hand.\(index)").frame
        return point(app, Self.grabX(f), f.midY + 10)
    }

    private static func grabX(_ f: CGRect) -> CGFloat { f.minX + min(f.width, 96) / 2 }

    /// Drags hand card `index` so its center ends over the center of slot `slot` in a fan of
    /// `count`: the fan's slots are where its cards sit now, and the card keeps its offset from
    /// the finger.
    @MainActor private func drag(_ app: XCUIApplication, card index: Int, toSlot slot: Int, of count: Int) {
        let frames = (0..<count).map { el(app, "table.hand.\($0)").frame }
        let box = frames[count - 1].width  // the last card's frame is its whole rotated box
        let center = { (i: Int) in frames[i].minX + box / 2 }
        let start = grabPoint(app, card: index)
        // From the frame, not `start.screenPoint`: that is in the screen's own (portrait) space,
        // which an iPad on its side doesn't share with element frames.
        let finger = CGPoint(x: Self.grabX(frames[index]), y: frames[index].midY + 10)
        let target = center(slot) - (center(index) - finger.x)
        start.press(forDuration: 0.15, thenDragTo: point(app, target, finger.y - 6), withVelocity: 500,
                    thenHoldForDuration: Live.pace(0.6))
    }
}
