import XCTest

/// JD: "people keep forgetting to lay down their cards ... confirm that they dont want to lay
/// down instead. and also the one that is just the paw isn't obvious that it is 'lay down'."
/// `-demo lay`: my play step on level 2 (a set of 3 and a run of 4), not laid yet, with three 9s,
/// a Yarn and 4-5-6 in hand; the fake server takes the lay-down. A discard it never answers, so
/// it stays in flight. `-demo controller-lay` is the same table with a TV showing it (Cards).
/// `POUNCE_SHOTS_DIR` (the runner's `TEST_RUNNER_POUNCE_SHOTS_DIR`) saves the screenshots there.
class LayDownFirstTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private let lay = [("9, tabby", 0), ("9, gray", 0), ("9, calico", 0), ("4, tuxedo", 1), ("5, gray", 1), ("6, calico", 1), ("Yarn, wild", 1)]

    /// A lay-down ready in the trays: the button says Lay down, a discard asks first, and Lay
    /// down lays them down.
    @MainActor
    func testADiscardWithALayDownReadyAsksAndLayDownLaysDown() throws {
        let app = launch("lay")
        fill(app, lay)
        let button = el(app, "table.laydown")
        XCTAssertTrue(button.waitForExistence(timeout: Live.t(3)), "no Lay down button")
        XCTAssertEqual(label(button), "Lay down")
        shot(app, "laydown-button")

        discard(app, "11, tabby")
        let ask = el(app, "ask.layDown")
        XCTAssertTrue(ask.waitForExistence(timeout: Live.t(3)), "a discard with a lay-down ready didn't ask")
        XCTAssertTrue(el(app, "ask.discard").exists)
        XCTAssertNotNil(handIndex(app, "11, tabby"), "the card left the hand before the answer")
        shot(app, "laydown-first")
        ask.tap()
        XCTAssertTrue(until(5) { debug(app)?.laid == true }, "Lay down didn't lay down: \(String(describing: debug(app)))")
        XCTAssertFalse(el(app, "ask").exists, "the question stayed up")
        XCTAssertNotNil(handIndex(app, "11, tabby"), "the 11 went with the lay-down")
        Thread.sleep(forTimeInterval: Live.pace(1))
        shot(app, "laydown-done")
    }

    /// "Discard anyway" discards the card, with its Undo, and the trays stay as they were.
    @MainActor
    func testDiscardAnywayDiscards() throws {
        let app = launch("lay")
        fill(app, lay)
        discard(app, "11, tabby")
        let anyway = el(app, "ask.discard")
        XCTAssertTrue(anyway.waitForExistence(timeout: Live.t(3)), "no question")
        anyway.tap()
        XCTAssertTrue(until(3) { self.handIndex(app, "11, tabby") == nil }, "Discard anyway didn't discard")
        // It waits on the pile with its Undo (a moment at test speed), then goes.
        XCTAssertTrue(until(5) { debug(app)?.inFlight == true }, "the discard never went: \(String(describing: debug(app)))")
        XCTAssertEqual(debug(app)?.laid, false, "it laid down anyway")
    }

    /// Nothing in the trays, or a lay-down that can't go yet: the discard goes at once.
    @MainActor
    func testNoQuestionWithoutALayDownReady() throws {
        let app = launch("lay")
        discard(app, "11, tabby")
        XCTAssertTrue(until(5) { debug(app)?.inFlight == true }, "the discard didn't go")
        XCTAssertFalse(el(app, "ask").exists, "asked with nothing in the trays")
        app.terminate()

        let again = launch("lay")
        fill(again, Array(lay.prefix(3)))  // just the set: no lay-down yet
        discard(again, "11, tabby")
        XCTAssertTrue(until(5) { debug(again)?.inFlight == true }, "the discard didn't go")
        XCTAssertFalse(el(again, "ask").exists, "asked with half a lay-down")
    }

    /// On Cards (a TV at the table): the same question, and laying down switches the phone to
    /// Table, where the laid groups are.
    @MainActor
    func testOnCardsTheQuestionAndLayingDownShowsTheTable() throws {
        let app = launch("controller-lay")
        XCTAssertTrue(el(app, "table.status").waitForExistence(timeout: Live.t(5)), "not on Cards")
        fill(app, lay)
        discard(app, "11, tabby")
        let ask = el(app, "ask.layDown")
        XCTAssertTrue(ask.waitForExistence(timeout: Live.t(3)), "Cards didn't ask")
        shot(app, "laydown-first-cards")
        ask.tap()
        XCTAssertTrue(until(5) { debug(app)?.laid == true }, "never laid down")
        // My own lay-down: the phone goes to Table (the other seats and the laid groups show).
        XCTAssertTrue(el(app, "table.group.0.0").waitForExistence(timeout: Live.t(5)), "the phone stayed on Cards after laying down")
        XCTAssertTrue(el(app, "table.opponent.1").exists)
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        shot(app, "laydown-table-after")
    }

    // MARK: helpers

    @MainActor private func launch(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo)
        app.launchArguments += ["-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "table.tray.0").waitForExistence(timeout: Live.t(10)), "no trays")
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        return app
    }

    /// Tap-tap: each card, then its tray.
    @MainActor private func fill(_ app: XCUIApplication, _ cards: [(String, Int)]) {
        for (card, tray) in cards {
            XCTAssertTrue(until(3) { self.handIndex(app, card) != nil }, "\(card) is not in the hand")
            guard let i = handIndex(app, card) else { return }
            el(app, "table.hand.\(i)").tap()
            XCTAssertTrue(until(2) { self.value(self.el(app, "table.hand.\(i)")) == "selected" }, "\(card) never lifted")
            el(app, "table.tray.\(tray)").tap()
        }
    }

    /// Tap-tap onto the discard pile.
    @MainActor private func discard(_ app: XCUIApplication, _ card: String) {
        XCTAssertTrue(until(3) { self.handIndex(app, card) != nil }, "\(card) is not in the hand")
        guard let i = handIndex(app, card) else { return }
        el(app, "table.hand.\(i)").tap()
        XCTAssertTrue(until(2) { self.value(self.el(app, "table.hand.\(i)")) == "selected" }, "\(card) never lifted")
        el(app, "table.discard").tap()
    }

    @MainActor private func handIndex(_ app: XCUIApplication, _ card: String) -> Int? {
        var i = 0
        while let l = label(el(app, "table.hand.\(i)")) {
            if l == card { return i }
            i += 1
        }
        return nil
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        screenshot(app, name)
        guard let dir = ProcessInfo.processInfo.environment["POUNCE_SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
