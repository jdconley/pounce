import XCTest

/// A table a TV shows (spec §3): this phone shows just its cards, with a Cards/Table switch on
/// top. `-demo controller` is the `hit` table with `screen: true`: my play step after laying down,
/// my hand 2, 3, a Yarn and an 8, and Leo's run 4-5-6-7 as his group 2; the fake server takes each
/// hit like the real one. `-demo controller-lay`: the `lay` table on Cards. `-demo controller-off`:
/// Kiki's turn.
class ControllerTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The switch is there on Cards; Table brings the other seats' cats back (the full table),
    /// Cards takes them away again.
    @MainActor
    func testTheSwitchShowsTheWholeTableAndBack() throws {
        let app = launch("controller")
        XCTAssertEqual(label(el(app, "table.status")), "Your turn")
        XCTAssertFalse(el(app, "table.opponent.1").exists, "the other seats show on Cards")
        XCTAssertFalse(el(app, "table.group.1.1").exists, "the laid groups show on Cards")
        screenshot(app, "controller-cards")

        el(app, "table.view.table").tap()
        XCTAssertTrue(el(app, "table.opponent.1").waitForExistence(timeout: Live.t(3)), "Table didn't show the other seats")
        XCTAssertTrue(el(app, "table.group.1.1").exists)
        XCTAssertTrue(el(app, "table.view.cards").exists, "the switch went away on Table")
        XCTAssertFalse(el(app, "table.status").exists, "the status line stayed on Table")
        screenshot(app, "controller-table")

        el(app, "table.view.cards").tap()
        XCTAssertTrue(el(app, "table.opponent.1").waitForNonExistence(timeout: Live.t(3)), "Cards kept the other seats")
        XCTAssertTrue(el(app, "table.status").waitForExistence(timeout: Live.t(2)))
    }

    /// Pick the 3, its one target (Leo's run) shows as a chip; pick it, Hit, and the 3 leaves the
    /// hand and lands at the start of Leo's run.
    @MainActor
    func testAHitThroughTheListLands() throws {
        let app = launch("controller")
        XCTAssertFalse(el(app, "hit.list").exists, "a hit list with no card picked")
        guard let i = handIndex(app, "3, calico") else { return XCTFail("no 3 in the hand") }
        el(app, "table.hand.\(i)").tap()

        let chip = el(app, "hit.target.1.1")
        XCTAssertTrue(chip.waitForExistence(timeout: Live.t(3)), "no hit list for the 3")
        XCTAssertEqual(label(chip), "Leo's run")
        XCTAssertFalse(el(app, "hit.target.0.0").exists, "the 3 can't go on my 9s")
        chip.tap()
        let hit = el(app, "hit.confirm")
        XCTAssertTrue(hit.waitForExistence(timeout: Live.t(2)), "no Hit after picking a group")
        XCTAssertTrue(el(app, "hit.cancel").exists)
        screenshot(app, "controller-hit-picked")

        // Cancel goes back to the list; picking again and Hit plays it.
        el(app, "hit.cancel").tap()
        XCTAssertTrue(chip.waitForExistence(timeout: Live.t(2)))
        XCTAssertFalse(hit.exists)
        chip.tap()
        XCTAssertTrue(hit.waitForExistence(timeout: Live.t(2)))
        hit.tap()

        XCTAssertTrue(until(5) { self.handIndex(app, "3, calico") == nil && debug(app)?.handCount == 3 },
                      "the 3 is still in the hand: \(String(describing: debug(app)))")
        XCTAssertTrue(until(3) { !self.el(app, "hit.list").exists }, "the hit list stayed up")
        el(app, "table.view.table").tap()
        let run = el(app, "table.group.1.1")
        XCTAssertTrue(run.waitForExistence(timeout: Live.t(3)))
        XCTAssertTrue(until(3) { self.label(run)?.hasSuffix(": 3, calico; 4, gray; 5, gray; 6, tabby; 7, calico") == true },
                      label(run) ?? "-")
    }

    /// The trays filled by tap-tap, Lay down is a word in the action row, and it lays them down.
    @MainActor
    func testLayDownFromTheActionRow() throws {
        let app = launch("controller-lay")
        XCTAssertFalse(el(app, "table.laydown.row").exists, "Lay down before the trays are ready")
        for (card, tray) in [("9, tabby", 0), ("9, gray", 0), ("9, calico", 0), ("4, tuxedo", 1), ("5, gray", 1), ("6, calico", 1), ("Yarn, wild", 1)] {
            XCTAssertTrue(until(3) { self.handIndex(app, card) != nil }, "\(card) is not in the hand")
            guard let i = handIndex(app, card) else { return }
            el(app, "table.hand.\(i)").tap()
            XCTAssertTrue(until(2) { self.value(self.el(app, "table.hand.\(i)")) == "selected" }, "\(card) never lifted")
            el(app, "table.tray.\(tray)").tap()
        }
        let lay = el(app, "table.laydown.row")
        XCTAssertTrue(lay.waitForExistence(timeout: Live.t(3)), "no Lay down in the action row")
        screenshot(app, "controller-lay")
        lay.tap()
        XCTAssertTrue(until(5) { debug(app)?.laid == true }, "never laid down: \(String(describing: debug(app)))")
    }

    /// Someone else's turn: whose it is, and nothing to do here.
    @MainActor
    func testOffTurnSaysWhoseTurn() throws {
        let app = launch("controller-off")
        XCTAssertEqual(label(el(app, "table.status")), "Kiki's turn")
        XCTAssertFalse(el(app, "hit.list").exists)
        XCTAssertFalse(el(app, "table.laydown.row").exists)
        screenshot(app, "controller-off")
    }

    /// A Cucumber picked on Cards lists who it can skip (there are no cats here to tap); "Skip Leo"
    /// discards it at Leo (with its Undo first, as a cat tap does), and never says "pick a cat".
    @MainActor
    func testACucumberSkipsSomeoneFromTheActionRow() throws {
        let app = launch("controller-skip")
        guard let i = handIndex(app, "Cucumber, skip") else { return XCTFail("no Cucumber in the hand: \(handLabels(app))") }
        el(app, "table.hand.\(i)").tap()
        let leo = el(app, "skip.target.1")
        XCTAssertTrue(leo.waitForExistence(timeout: Live.t(3)), "no skip list for the Cucumber")
        XCTAssertEqual(label(leo), "Skip Leo")
        XCTAssertTrue(el(app, "skip.target.3").exists, "the House Cat can be skipped too")
        XCTAssertFalse(el(app, "skip.target.2").exists, "Kiki already has a skip waiting")
        screenshot(app, "controller-skip")

        // Dropped on the discard it waits for a pick, with no "pick a cat" note.
        el(app, "table.discard").tap()
        XCTAssertTrue(leo.waitForExistence(timeout: Live.t(2)))
        XCTAssertFalse(el(app, "table.note").exists, "a note asked for a cat that isn't on Cards")

        leo.tap()
        // It waits on the pile with its Undo (a moment at test speed), then goes; the demo server
        // never answers a discard, so it stays in flight.
        XCTAssertTrue(until(3) { self.handIndex(app, "Cucumber, skip") == nil }, "the Cucumber is still in the hand")
        XCTAssertTrue(until(5) { debug(app)?.inFlight == true }, "the discard never went: \(String(describing: debug(app)))")
        XCTAssertFalse(el(app, "skip.list").exists, "the skip list stayed up")
    }

    /// Pass and play on Cards: the curtain covers the hand between players, and nothing of the
    /// table under it can be read or touched; the hold shows that player's hand on Cards.
    @MainActor
    func testTheCurtainCoversTheHandOnCards() throws {
        let app = Live.demo("controller-curtain")
        app.launch()
        let curtain = el(app, "screen-curtain")
        let hold = el(app, "curtain.hold")
        XCTAssertTrue(hold.waitForExistence(timeout: Live.t(10)), "no curtain")
        XCTAssertTrue(curtain.exists)
        XCTAssertFalse(el(app, "table.hand.0").exists, "the hand reads under the curtain")
        XCTAssertFalse(el(app, "table.deck").exists, "the table reads under the curtain")
        let cards = el(app, "table.view.cards")
        XCTAssertFalse(cards.exists && cards.isHittable, "the switch takes touches under the curtain")
        screenshot(app, "controller-curtain")

        hold.press(forDuration: Live.pace(1.3, floor: 0.3))
        XCTAssertTrue(curtain.waitForNonExistence(timeout: Live.t(5)), "the hold didn't lift the curtain")
        XCTAssertTrue(el(app, "table.hand.0").waitForExistence(timeout: Live.t(3)), "no hand after the curtain")
        XCTAssertTrue(until(3) { self.label(self.el(app, "table.hand.0")).map { $0 != "Card" } ?? false },
                      "the hand stayed face down: \(label(el(app, "table.hand.0")) ?? "-")")
        XCTAssertEqual(label(el(app, "table.status")), "Your turn, Mia")
        XCTAssertTrue(el(app, "table.view.cards").isHittable)
    }

    // MARK: helpers

    @MainActor private func handLabels(_ app: XCUIApplication) -> [String] {
        var labels: [String] = []
        while let l = label(el(app, "table.hand.\(labels.count)")) { labels.append(l) }
        return labels
    }

    @MainActor private func launch(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo)
        app.launch()
        XCTAssertTrue(el(app, "table.view.cards").waitForExistence(timeout: Live.t(10)), "no Cards/Table switch")
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(el(app, "table.status").waitForExistence(timeout: Live.t(5)), "no status line on Cards")
        return app
    }

    @MainActor private func handIndex(_ app: XCUIApplication, _ card: String) -> Int? {
        var i = 0
        while let l = label(el(app, "table.hand.\(i)")) {
            if l == card { return i }
            i += 1
        }
        return nil
    }
}
