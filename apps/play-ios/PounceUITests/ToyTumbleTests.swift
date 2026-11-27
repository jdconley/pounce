import XCTest

/// Toy Tumble on its demo socket (`-demo tumble-*`, no server: House Cat boxes run on the device),
/// driven by the gestures a person makes (spec §5.3): a drag moves the toy, a tap turns it, a
/// flick drops it, a trick dragged onto a mini is used, and a drag from the very left edge moves
/// the toy instead of leaving the table (Review Focus 2).
@MainActor
final class ToyTumbleTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// `key=value` pairs from an element's value.
    private func pairs(_ text: String?) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in (text ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, let n = Int(pair[1]) { out[pair[0]] = n }
        }
        return out
    }

    private func toy(_ app: XCUIApplication) -> [String: Int] { pairs(value(el(app, "tumble.box"))) }

    private func launch(_ demo: String) -> XCUIApplication {
        // Real speed: the game runs on the wall clock, and the gestures' timing matters.
        let app = Live.demo(demo, speed: 1)
        app.launchArguments += ["-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "screen-tumble").waitForExistence(timeout: Live.t(10)), "no Toy Tumble table")
        XCTAssertTrue(until(8) { self.toy(app)["toy"] != nil }, "no toy in hand")
        return app
    }

    private func point(_ app: XCUIApplication, x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    func testDragMovesTapTurnsAndFlickDrops() {
        let app = launch("tumble-two")
        let box = el(app, "tumble.box")
        let frame = box.frame
        let cell = frame.width / 12

        // A drag of three cells to the right, anywhere on the box.
        let before = toy(app)
        let start = point(app, x: frame.minX + cell * 2, y: frame.midY)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: cell * 3.4, dy: 0)), withVelocity: 300, thenHoldForDuration: 0.05)
        XCTAssertTrue(until(3) { (self.toy(app)["x"] ?? 0) >= (before["x"] ?? 0) + 2 || self.toy(app)["toy"] != before["toy"] },
                      "the drag didn't move the toy: \(before) -> \(toy(app))")

        // A tap turns it.
        let turned = toy(app)
        point(app, x: frame.midX, y: frame.midY).tap()
        XCTAssertTrue(until(3) { self.toy(app)["rot"] != turned["rot"] || self.toy(app)["toy"] != turned["toy"] },
                      "the tap didn't turn the toy: \(turned) -> \(toy(app))")

        // A flick down drops it: the next toy comes.
        let next = toy(app)["next"] ?? 0
        let top = point(app, x: frame.midX, y: frame.minY + frame.height * 0.3)
        top.press(forDuration: 0.02, thenDragTo: top.withOffset(CGVector(dx: 0, dy: frame.height * 0.4)), withVelocity: 3000, thenHoldForDuration: 0)
        XCTAssertTrue(until(3) { (self.toy(app)["next"] ?? 0) > next }, "the flick didn't drop the toy: \(toy(app))")
    }

    /// Review Focus 2: a drag from 4 pt off the left edge moves the toy and stays on the table.
    func testADragFromTheLeftEdgeMovesTheToy() {
        let app = launch("tumble-two")
        let frame = el(app, "tumble.box").frame
        let cell = frame.width / 12
        // Move it left first, so there's room to drag it right.
        let before = toy(app)
        let edge = point(app, x: 4, y: frame.midY)
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: cell * 3.4, dy: 0)), withVelocity: 300, thenHoldForDuration: 0.05)
        XCTAssertTrue(until(3) { (self.toy(app)["x"] ?? 0) > (before["x"] ?? 0) || self.toy(app)["toy"] != before["toy"] },
                      "the edge drag didn't move the toy: \(before) -> \(toy(app))")
        XCTAssertTrue(el(app, "screen-tumble").exists, "the edge drag left the table")
    }

    /// A trick dragged from the tray onto a mini is used; a tap, then a tap on a box, too.
    func testATrickDraggedOntoAMiniIsUsed() {
        let app = launch("tumble-play")
        // The tray's tricks are the scene's own elements (the SwiftUI probe redraws only with the room).
        XCTAssertTrue(el(app, "tumble.trick.1").waitForExistence(timeout: Live.t(5)), "no tricks in hand")
        let trick = el(app, "tumble.trick.0")
        let mini = el(app, "tumble.mini.1")
        XCTAssertTrue(trick.waitForExistence(timeout: Live.t(3)), "no trick in the tray")
        XCTAssertTrue(mini.exists, "no mini")
        trick.press(forDuration: 0.1, thenDragTo: mini)
        XCTAssertTrue(until(3) { !self.el(app, "tumble.trick.1").exists }, "the dragged trick wasn't used")

        // Tap the last trick to lift it, then tap your own box.
        el(app, "tumble.trick.0").tap()
        el(app, "tumble.box").tap()
        XCTAssertTrue(until(3) { !self.el(app, "tumble.trick.0").exists }, "the tapped trick wasn't used")
    }
}
