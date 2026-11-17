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

    // MARK: helpers

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
