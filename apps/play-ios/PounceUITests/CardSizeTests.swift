import XCTest

/// JD: "in some of the animations in the card view the cards are small instead of big sometimes
/// just for a few frames." Each table's DEBUG `*.sizes` probe counts frames where a hand card was
/// drawn smaller than the hand's size and then came back (`CardSizeWatch`): a card made at the
/// wrong size, a tween that starts from one, or a layout that applied late. These play the moves
/// that touch hand cards on Cards (a TV at the table) and on the phone's own table, and fail on
/// any such frame.
class CardSizeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Cat Tower on Cards: opening, picking cards, a hit through the list (it flies up to the TV),
    /// sorting, a reorder drag, and the switch to Table and back.
    @MainActor
    func testCatTowerOnCards() throws {
        let app = launch("controller")
        check(app, "opening Cards")
        tapCard(app, "3, calico")
        check(app, "picking the 3")
        tapCard(app, "3, calico")
        check(app, "putting the 3 down")
        tapCard(app, "3, calico")
        let chip = el(app, "hit.target.1.1")
        XCTAssertTrue(chip.waitForExistence(timeout: Live.t(3)), "no hit list for the 3")
        chip.tap()
        let hit = el(app, "hit.confirm")
        XCTAssertTrue(hit.waitForExistence(timeout: Live.t(2)))
        hit.tap()
        XCTAssertTrue(until(5) { debug(app)?.handCount == 3 }, "the hit never landed")
        Thread.sleep(forTimeInterval: Live.pace(1))
        check(app, "a hit from the list")
        let sort = el(app, "table.sort")
        if sort.exists {
            sort.tap()
            Thread.sleep(forTimeInterval: Live.pace(0.6))
            check(app, "sorting")
        }
        dragCard(app, from: 0, to: 2)
        check(app, "a reorder drag")
        el(app, "table.view.table").tap()
        XCTAssertTrue(el(app, "table.opponent.1").waitForExistence(timeout: Live.t(3)))
        // A real second on Table, so going back isn't counted as a size that came back.
        Thread.sleep(forTimeInterval: 1)
        check(app, "switching to Table")
        el(app, "table.view.cards").tap()
        XCTAssertTrue(el(app, "table.opponent.1").waitForNonExistence(timeout: Live.t(3)))
        Thread.sleep(forTimeInterval: Live.pace(0.6))
        check(app, "switching back to Cards")
    }

    /// Cat Tower on Cards: the trays filled by tap-tap and the lay-down.
    @MainActor
    func testCatTowerLayDownOnCards() throws {
        let app = launch("controller-lay")
        for (card, tray) in [("9, tabby", 0), ("9, gray", 0), ("9, calico", 0), ("4, tuxedo", 1), ("5, gray", 1), ("6, calico", 1), ("Yarn, wild", 1)] {
            tapCard(app, card)
            el(app, "table.tray.\(tray)").tap()
            Thread.sleep(forTimeInterval: Live.pace(0.3))
        }
        check(app, "filling the trays")
        let lay = el(app, "table.laydown.row")
        XCTAssertTrue(lay.waitForExistence(timeout: Live.t(3)), "no Lay down in the action row")
        lay.tap()
        XCTAssertTrue(until(5) { debug(app)?.laid == true }, "never laid down")
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        check(app, "laying down")
    }

    /// Cat Tower on Cards: a Cucumber skips Leo, waits on the pile with its Undo, and comes back.
    @MainActor
    func testCatTowerSkipAndUndoOnCards() throws {
        let app = launch("controller-skip")
        tapCard(app, "Cucumber, skip")
        let leo = el(app, "skip.target.1")
        XCTAssertTrue(leo.waitForExistence(timeout: Live.t(3)), "no skip list for the Cucumber")
        leo.tap()
        let undo = el(app, "table.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "no Undo after Skip Leo")
        check(app, "a skip onto the pile")
        undo.tap()
        XCTAssertTrue(until(3) { self.handIndex(app, "Cucumber, skip") != nil }, "Undo didn't bring the Cucumber back")
        Thread.sleep(forTimeInterval: 0.8)
        check(app, "an Undo back into the hand")
    }

    /// The phone's own table: hits by drag, a refused one, and a reorder.
    @MainActor
    func testCatTowerOnThePhonesTable() throws {
        let app = Live.demo("hit", speed: 1)
        app.launchArguments += ["-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "table.group.1.1").waitForExistence(timeout: Live.t(10)))
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) { dismissPriming(app) }
        Thread.sleep(forTimeInterval: Live.pace(0.6))
        check(app, "opening the table")
        dragCard(app, from: handIndex(app, "8, gray") ?? 3, toElement: "table.group.1.1")
        Thread.sleep(forTimeInterval: Live.pace(1))
        check(app, "a hit by drag")
        dragCard(app, from: handIndex(app, "3, calico") ?? 1, toElement: "table.group.1.0")
        Thread.sleep(forTimeInterval: Live.pace(1))
        check(app, "a refused hit")
        dragCard(app, from: 0, to: 2)
        check(app, "a reorder drag")
    }

    /// Whole games played by the demo servers, on Cards (`-on-tv`) and on the phone's own table:
    /// `replay` (draws, discards, hits, a reshuffle), `celebrate` (the versus intro, deals, a
    /// round over, game over) and `howto` (my whole turn: the draw, the lay-down, hits).
    @MainActor
    func testWholeGamesOnCardsAndOnThePhonesTable() throws {
        let only = ProcessInfo.processInfo.environment["POUNCE_SIZES_DEMO"].map { [$0] }
        for demo in only ?? ["replay", "celebrate", "howto"] {
            for onTV in [true, false] {
                let where_ = onTV ? "on Cards" : "on the phone's table"
                let app = Live.demo(demo, speed: 1)
                app.launchArguments += ["-settings.soundOn", "<false/>"] + (onTV ? ["-on-tv"] : [])
                app.launch()
                XCTAssertTrue(el(app, "table.sizes").waitForExistence(timeout: Live.t(10)), "no table for \(demo) \(where_)")
                let notNow = el(app, "priming.notNow")
                if notNow.waitForExistence(timeout: 2) { dismissPriming(app) }
                // Long enough for the demo's whole game at the test's speed.
                Thread.sleep(forTimeInterval: demo == "celebrate" ? 24 : 14)
                check(app, "\(demo) \(where_)")
                app.terminate()
            }
        }
    }

    /// Tuna Tiles on Cards and on the phone's own table: a game against House Cats that run on
    /// the phone (`tiles-play`: draws, plays, turns going round) with the stash's own drags
    /// (`-autoplay`), the other seats playing up to my move (`controller-tiles-off`), and the
    /// Cards/Table switch, where every piece grows or shrinks on its way.
    @MainActor
    func testTunaTilesOnCardsAndOnThePhonesTable() throws {
        for extra in [["-on-tv"], []] {
            watch("tiles-play", extra + ["-autoplay"], probe: "tiles.sizes", seconds: 12)
        }
        watch("controller-tiles-off", [], probe: "tiles.sizes", seconds: 10)
        let app = watch("controller-tiles", [], probe: "tiles.sizes", seconds: 1, terminate: false)
        for side in ["table", "cards", "table", "cards"] {
            el(app, "table.view.\(side)").tap()
            Thread.sleep(forTimeInterval: 1)
            check(app, "Tuna Tiles switched to \(side)", probe: "tiles.sizes")
        }
        app.terminate()
    }

    /// Birdwatch on Cards (`bird-tv`) and on the phone's own table (`bird-play`), the hand playing
    /// itself (`-bird-autoplay`): bids, the put-back, trump, tricks and new deals.
    @MainActor
    func testBirdwatchOnCardsAndOnThePhonesTable() throws {
        for demo in ["bird-tv", "bird-play"] {
            watch(demo, ["-bird-autoplay"], probe: "bird.sizes", seconds: 14)
        }
    }

    // MARK: helpers

    /// Launches `demo` at the app's own pace, lets it play `seconds`, and checks `probe`.
    @MainActor @discardableResult
    private func watch(_ demo: String, _ extra: [String], probe: String, seconds: TimeInterval, terminate: Bool = true) -> XCUIApplication {
        let app = Live.demo(demo, speed: 1)
        app.launchArguments += ["-settings.soundOn", "<false/>"] + extra
        app.launch()
        XCTAssertTrue(el(app, probe).waitForExistence(timeout: Live.t(15)), "no \(probe) for \(demo) \(extra)")
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) { dismissPriming(app) }
        Thread.sleep(forTimeInterval: seconds)
        check(app, "\(demo) \(extra.joined(separator: " "))", probe: probe)
        if terminate { app.terminate() }
        return app
    }

    /// Fails on any hand card the table drew small for a few frames so far.
    @MainActor private func check(
        _ app: XCUIApplication, _ moment: String, probe id: String = "table.sizes", file: StaticString = #filePath, line: UInt = #line
    ) {
        let probe = value(el(app, id)) ?? "-"
        print("SIZES \(moment): \(probe)")
        XCTAssertTrue(probe.hasPrefix("0|"), "a hand card was drawn small (\(moment)): \(probe)", file: file, line: line)
        let judged = Int(probe.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first ?? "") ?? 0
        XCTAssertGreaterThan(judged, 0, "the watch saw no cards (\(moment)): \(probe)", file: file, line: line)
    }

    /// At the app's own pace: a tween sped up ten times moves a card a long way in one frame.
    @MainActor private func launch(_ demo: String, speed: Double = 1) -> XCUIApplication {
        let app = Live.demo(demo, speed: speed)
        app.launchArguments += ["-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "table.view.cards").waitForExistence(timeout: Live.t(10)), "no Cards/Table switch")
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(el(app, "table.status").waitForExistence(timeout: Live.t(5)), "no status line on Cards")
        Thread.sleep(forTimeInterval: Live.pace(0.6))
        return app
    }

    @MainActor private func tapCard(_ app: XCUIApplication, _ card: String) {
        XCTAssertTrue(until(3) { self.handIndex(app, card) != nil }, "\(card) is not in the hand")
        guard let i = handIndex(app, card) else { return }
        el(app, "table.hand.\(i)").tap()
        Thread.sleep(forTimeInterval: Live.pace(0.4))
    }

    @MainActor private func handIndex(_ app: XCUIApplication, _ card: String) -> Int? {
        var i = 0
        while let l = label(el(app, "table.hand.\(i)")) {
            if l == card { return i }
            i += 1
        }
        return nil
    }

    @MainActor private func dragCard(_ app: XCUIApplication, from i: Int, to j: Int) {
        let a = el(app, "table.hand.\(i)").frame, b = el(app, "table.hand.\(j)").frame
        drag(app, from: CGPoint(x: a.minX + min(a.width, 24) / 2, y: a.midY + 10), to: CGPoint(x: b.midX + 6, y: b.midY))
    }

    @MainActor private func dragCard(_ app: XCUIApplication, from i: Int, toElement id: String) {
        let a = el(app, "table.hand.\(i)").frame, b = el(app, id).frame
        drag(app, from: CGPoint(x: a.minX + min(a.width, 24) / 2, y: a.midY + 10), to: CGPoint(x: b.midX, y: b.midY))
    }

    @MainActor private func drag(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)), withVelocity: 500,
                   thenHoldForDuration: Live.pace(0.4))
        Thread.sleep(forTimeInterval: Live.pace(0.8))
    }
}
