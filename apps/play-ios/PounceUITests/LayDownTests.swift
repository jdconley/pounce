import XCTest

/// A Yarn laid down in a run stays where the player put it. `-demo lay`: my play step on
/// phase 2 (a set of 3, a run of 4) with three 9s, a Yarn, 4, 5 and 6 in hand, so the Yarn can
/// be the 3 or the 7; the fake server takes the lay-down like the real one.
class LayDownTests: XCTestCase {
    private let runTray = "table.tray.1"
    private let laidRun = "table.group.0.1"

    override func setUp() {
        continueAfterFailure = false
    }

    /// JD's report: a Yarn at one end of the run tray must be at that end once laid.
    @MainActor
    func testYarnDroppedAtTheEndOfTheRunIsLaidAtTheEnd() throws {
        let app = launch()
        fillTrays(app)
        drag(app, card: "Yarn, wild", intoTray: runTray, atStart: false)
        XCTAssertTrue(until(3) { self.trayCards(app, 1) == ["4, tuxedo", "5, gray", "6, calico", "Yarn, wild"] },
                      "\(trayCards(app, 1))")
        screenshot(app, "lay-yarn-end-tray")

        layDown(app)
        XCTAssertTrue(until(5) { self.label(el(app, self.laidRun))?.hasSuffix(": 4, tuxedo; 5, gray; 6, calico; Yarn, wild") == true },
                      label(el(app, laidRun)) ?? "-")
        screenshot(app, "lay-yarn-end-laid")
    }

    @MainActor
    func testYarnDroppedAtTheStartOfTheRunIsLaidAtTheStart() throws {
        let app = launch()
        fillTrays(app)
        drag(app, card: "Yarn, wild", intoTray: runTray, atStart: true)
        XCTAssertTrue(until(3) { self.trayCards(app, 1) == ["Yarn, wild", "4, tuxedo", "5, gray", "6, calico"] },
                      "\(trayCards(app, 1))")

        layDown(app)
        XCTAssertTrue(until(5) { self.label(el(app, self.laidRun))?.hasSuffix(": Yarn, wild; 4, tuxedo; 5, gray; 6, calico") == true },
                      label(el(app, laidRun)) ?? "-")
        screenshot(app, "lay-yarn-start-laid")
    }

    // MARK: helpers

    @MainActor private func launch() -> XCUIApplication {
        let app = Live.demo("lay")
        app.launch()
        XCTAssertTrue(el(app, runTray).waitForExistence(timeout: 10))
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        return app
    }

    /// The three 9s into the set tray and 4, 5, 6 into the run tray, by tap-tap.
    @MainActor private func fillTrays(_ app: XCUIApplication) {
        for (card, tray) in [("9, tabby", 0), ("9, gray", 0), ("9, calico", 0), ("4, tuxedo", 1), ("5, gray", 1), ("6, calico", 1)] {
            XCTAssertTrue(until(3) { self.handIndex(app, card) != nil }, "\(card) is not in the hand")
            guard let i = handIndex(app, card) else { return }
            el(app, "table.hand.\(i)").tap()
            XCTAssertTrue(until(2) { self.value(el(app, "table.hand.\(i)")) == "selected" }, "\(card) never lifted")
            el(app, "table.tray.\(tray)").tap()
            XCTAssertTrue(until(3) { self.trayCards(app, tray).contains(card) }, "\(card) never reached tray \(tray)")
        }
    }

    @MainActor private func layDown(_ app: XCUIApplication) {
        let paw = el(app, "table.laydown")
        XCTAssertTrue(paw.waitForExistence(timeout: 3))
        paw.tap()
    }

    @MainActor private func trayCards(_ app: XCUIApplication, _ tray: Int) -> [String] {
        var cards: [String] = []
        while let l = label(el(app, "table.traycard.\(tray).\(cards.count)")) { cards.append(l) }
        return cards
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

    /// Drags the hand card labelled `card` and lets go over one end of tray `id`'s cards.
    @MainActor private func drag(_ app: XCUIApplication, card: String, intoTray id: String, atStart: Bool) {
        guard let index = handIndex(app, card) else { return XCTFail("\(card) is not in the hand") }
        let first = el(app, "table.traycard.1.0").frame, last = el(app, "table.traycard.1.2").frame
        let x = atStart ? first.minX + 2 : last.maxX + first.width * 0.4
        let y = el(app, id).frame.midY
        let h = el(app, "table.hand.\(index)").frame
        let start = point(app, h.minX + min(h.width, 24) / 2, h.midY + 10)
        start.press(forDuration: 0.15, thenDragTo: point(app, x, y), withVelocity: 500,
                    thenHoldForDuration: Live.pace(0.3))
    }
}
