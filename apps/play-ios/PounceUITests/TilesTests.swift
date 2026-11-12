import XCTest

/// The tile game's table, on its demo tables (no server; the fake socket runs the game on the
/// device and plays the other seats). The DEBUG `tiles.debug` probe reads the scene back:
/// `turn=<draw|pass|play|blocked-…|sent|none> sets=<n> rack=<n> placed=<n> selected=<n> loupe=<id|-> …`.
@MainActor
final class TilesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: helpers

    private func launch(_ demo: String, _ extra: [String] = [], speed: Double = Live.speed) -> XCUIApplication {
        let app = Live.demo(demo, speed: speed)
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(el(app, "tiles.debug").waitForExistence(timeout: Live.t(20)), "the tile game's table never came up")
        return app
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "tiles.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func wait(_ app: XCUIApplication, _ key: String, _ wanted: String, timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(until(timeout) { self.probe(app)[key] == wanted }, "\(key) is \(probe(app)[key] ?? "nil"), wanted \(wanted): \(probe(app))", file: file, line: line)
    }

    /// The first element whose id starts with `prefix` and whose label starts with `label`.
    private func find(_ app: XCUIApplication, _ prefix: String, label: String) -> XCUIElement? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", prefix, label))
        return query.count > 0 ? query.element(boundBy: 0) : nil
    }

    private func rack(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        guard let e = find(app, "tiles.rack.", label: label) else {
            XCTFail("no stash piece \(label)", file: file, line: line)
            return el(app, "tiles.rack.0")
        }
        return e
    }

    private func set(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        guard let e = find(app, "tiles.set.", label: label) else {
            XCTFail("no set \(label)", file: file, line: line)
            return el(app, "tiles.set.0")
        }
        return e
    }

    private func drag(_ from: XCUIElement, to: XCUIElement) {
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // The piece rides above the finger, so aim a little under the target's middle.
        let end = to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: 500, thenHoldForDuration: Live.pace(0.4))
    }

    // MARK: composing a turn

    func testTapPathPlacesAPieceAndUndoTakesItBack() {
        let app = launch("tiles")
        XCTAssertEqual(probe(app)["turn"], "draw")
        XCTAssertEqual(probe(app)["sets"], "9")
        XCTAssertEqual(probe(app)["rack"], "9")
        XCTAssertEqual(label(el(app, "tiles.turn")), "Draw a toy")

        // Select, then tap the target: the whole set is the target.
        rack(app, "7, fish").tap()
        wait(app, "selected", "1")
        set(app, "Row, fish, 3 to 6").tap()
        wait(app, "placed", "1")
        wait(app, "turn", "play")
        XCTAssertEqual(probe(app)["rack"], "8")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, fish, 3 to 7, changed this turn"))
        XCTAssertEqual(label(el(app, "tiles.turn")), "Play")
        screenshot(app, "tiles-tap-placed")

        el(app, "tiles.undo").tap()
        wait(app, "placed", "0")
        wait(app, "turn", "draw")
        XCTAssertEqual(probe(app)["rack"], "9")
    }

    func testDragPathPlacesAPieceAndDragsItBack() {
        let app = launch("tiles")
        drag(rack(app, "13, mouse"), to: set(app, "Row, mouse, 10 to 12"))
        wait(app, "placed", "1")
        wait(app, "turn", "play")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, mouse, 10 to 13"))

        // A piece placed this turn comes straight back off the rug. Its set is four pieces wide
        // and the 13 is the last of them.
        let row = set(app, "Row, mouse, 10 to 13")
        let piece = row.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        let stash = el(app, "tiles.rack.0").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        piece.press(forDuration: 0.15, thenDragTo: stash, withVelocity: 500, thenHoldForDuration: Live.pace(0.4))
        wait(app, "placed", "0")
        wait(app, "turn", "draw")
        XCTAssertEqual(probe(app)["rack"], "9")
    }

    func testAPieceThatWasOnTheRugNeverComesToTheStash() {
        let app = launch("tiles")
        let row = set(app, "Row, fish, 3 to 6")
        let piece = row.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let stash = el(app, "tiles.rack.0").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        piece.press(forDuration: 0.15, thenDragTo: stash, withVelocity: 500, thenHoldForDuration: Live.pace(0.4))
        XCTAssertEqual(probe(app)["rack"], "9")
        XCTAssertEqual(probe(app)["turn"], "draw")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, fish, 3 to 6"))
    }

    func testSeveralPiecesMakeANewSetAndABrokenSetBlocksPlay() {
        let app = launch("tiles")
        rack(app, "11, bell").tap()
        rack(app, "13, fish").tap()
        wait(app, "selected", "2")
        el(app, "tiles.newset").tap()
        wait(app, "sets", "10")
        wait(app, "turn", "blocked-set")
        XCTAssertEqual(label(el(app, "tiles.turn")), "Play, not ready")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Not a set yet: 11, bell and 13, fish, needs three toys"))
        screenshot(app, "tiles-invalid")
        // The greyed button sends nothing.
        el(app, "tiles.turn").tap()
        XCTAssertEqual(probe(app)["sent"], "-")
        // Reset is a press and hold.
        el(app, "tiles.reset").press(forDuration: 1.0)
        wait(app, "turn", "draw")
        XCTAssertEqual(probe(app)["sets"], "9")
        XCTAssertEqual(probe(app)["rack"], "9")
    }

    func testTheLoupeOpensASetAndSplitsIt() {
        let app = launch("tiles")
        set(app, "Row, feather, 1 to 5").tap()
        wait(app, "loupe", "3")
        XCTAssertTrue(el(app, "tiles.loupe.close").exists)
        screenshot(app, "tiles-loupe")
        // Tap the gap before the fourth piece: 1-2-3 and 4-5.
        el(app, "tiles.loupe.gap.3").tap()
        wait(app, "sets", "10")
        wait(app, "turn", "blocked-set")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, feather, 1 to 3"))
        el(app, "tiles.loupe.close").tap()
        wait(app, "loupe", "-")
        el(app, "tiles.undo").tap()
        wait(app, "sets", "9")
        wait(app, "turn", "draw")
    }

    func testAYarnIsSwappedOutThroughTheTapPath() {
        let app = launch("tiles")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, bell, 5 to 8"))
        rack(app, "7, bell").tap()
        set(app, "Row, bell, 5 to 8").tap()
        wait(app, "turn", "play")
        // The 7 takes the Yarn's place and the Yarn moves to the end, standing for 9.
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, bell, 5 to 9"))
    }

    // MARK: the opening

    func testBeforeOpeningTheRugIsLockedAndTheMeterFills() {
        let app = launch("tiles-early")
        XCTAssertEqual(label(el(app, "tiles.meter")), "Opening: 0 of 30")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, mouse, 10 to 12, locked until you open"))
        // A locked set doesn't open and takes nothing.
        set(app, "Row, mouse, 10 to 12").tap()
        XCTAssertEqual(probe(app)["loupe"], "-")
        rack(app, "13, feather").tap()
        set(app, "Row, mouse, 10 to 12").tap()
        XCTAssertEqual(probe(app)["placed"], "0")
        rack(app, "13, feather").tap()
        wait(app, "selected", "0")

        // Three 5s are 15: a set, but not an opening.
        for piece in ["5, mouse", "5, fish", "5, feather"] { rack(app, piece).tap() }
        el(app, "tiles.newset").tap()
        wait(app, "turn", "blocked-opening")
        XCTAssertEqual(label(el(app, "tiles.meter")), "Opening: 15 of 30")
        // Fish 10-11-12 brings it to 48.
        for piece in ["10, fish", "11, fish", "12, fish"] { rack(app, piece).tap() }
        el(app, "tiles.newset").tap()
        wait(app, "turn", "play")
        XCTAssertEqual(label(el(app, "tiles.meter")), "Opening: 48 of 30")
        screenshot(app, "tiles-opening")

        el(app, "tiles.turn").tap()
        XCTAssertTrue(until(5) { (self.probe(app)["sent"] ?? "").hasPrefix("play") })
        // The fake server takes it (the same rules) and the other seats play on.
        XCTAssertEqual(probe(app)["refused"], "-")
        XCTAssertTrue(until(20) { self.probe(app)["turn"] == "draw" && self.probe(app)["rack"] != "8" || self.probe(app)["turn"] == "draw" },
                      "the move never came back: \(probe(app))")
        XCTAssertNil(find(app, "tiles.meter", label: "Opening"))
    }

    // MARK: draw, pass, sort

    func testDrawTakesAHold() {
        // At normal speed: the hold's length is what this checks.
        let app = launch("tiles", speed: 1)
        el(app, "tiles.turn").tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(probe(app)["sent"], "-", "a tap drew a piece")
        el(app, "tiles.turn").press(forDuration: 0.9)
        XCTAssertTrue(until(5) { self.probe(app)["sent"] == "draw" }, "\(probe(app))")
        // The piece lands at the right end of the stash.
        XCTAssertTrue(until(8) { self.probe(app)["rack"] == "10" }, "\(probe(app))")
    }

    func testAnEmptyToyBoxMakesTheButtonPass() {
        let app = launch("tiles-pass")
        XCTAssertEqual(probe(app)["turn"], "pass")
        XCTAssertEqual(label(el(app, "tiles.turn")), "Pass")
        XCTAssertEqual(label(el(app, "tiles.pool")), "Toy box, 0 toys")
    }

    func testSortTogglesAndTheLateTableFitsTheScreen() {
        let app = launch("tiles-late")
        XCTAssertEqual(probe(app)["sets"], "25")
        XCTAssertEqual(probe(app)["rack"], "22")
        let piece = Int(probe(app)["piece"] ?? "0") ?? 0
        XCTAssertGreaterThanOrEqual(piece, 24, "rug pieces shrank below 24 pt")
        XCTAssertEqual(probe(app)["sort"], "free")
        el(app, "tiles.sort.number").tap()
        wait(app, "sort", "number")
        XCTAssertEqual(label(el(app, "tiles.rack.0")), "1, fish")
        el(app, "tiles.sort.toy").tap()
        wait(app, "sort", "toy")
        el(app, "tiles.sort.toy").tap()
        wait(app, "sort", "free")
        screenshot(app, "tiles-late")
    }

    // MARK: pass and play, easy mode, the end

    func testOnASharedPhoneTheCurtainCoversTheStashAndTheRugStaysInView() {
        let app = launch("tiles-curtain", speed: 1)
        XCTAssertTrue(el(app, "curtain.hold").waitForExistence(timeout: 5))
        XCTAssertEqual(probe(app)["shown"], "-")
        XCTAssertEqual(probe(app)["rack"], "0")
        XCTAssertFalse(el(app, "tiles.rack.0").exists, "a stash piece exists behind the curtain")
        XCTAssertNotNil(find(app, "tiles.set.", label: "Row, fish, 3 to 6"), "the rug is public")
        screenshot(app, "tiles-curtain")
        // A tap is not a hold.
        el(app, "curtain.hold").tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(probe(app)["shown"], "-")
        el(app, "curtain.hold").press(forDuration: 1.2)
        XCTAssertTrue(until(5) { self.probe(app)["shown"] == "0" }, "\(probe(app))")
        XCTAssertEqual(probe(app)["rack"], "9")
        XCTAssertTrue(el(app, "curtain.hold").waitForNonExistence(timeout: 5))
    }

    func testEasyModeSendsAPieceThatDoesNotFitBackAndShowsAHint() {
        let app = launch("tiles", ["-tiles-easy"])
        XCTAssertTrue(el(app, "tiles.hint").exists)
        XCTAssertFalse(el(app, "tiles.tidy").exists)
        // The stash sorts itself.
        XCTAssertEqual(probe(app)["sort"], "toy")
        // A bell on the fish row goes back to the stash instead of breaking the row.
        rack(app, "11, bell").tap()
        set(app, "Row, fish, 3 to 6").tap()
        XCTAssertEqual(probe(app)["placed"], "0")
        XCTAssertEqual(probe(app)["turn"], "draw")
        wait(app, "selected", "0")
        // The loupe is a trick: a tap on a set doesn't open it.
        set(app, "Row, feather, 1 to 5").tap()
        XCTAssertEqual(probe(app)["loupe"], "-")
        el(app, "tiles.hint").tap()
        screenshot(app, "tiles-easy-hint")
    }

    func testAFinishedGameShowsTheStandings() {
        let app = launch("tiles-over")
        XCTAssertTrue(el(app, "screen-tiles-over").waitForExistence(timeout: 8))
        XCTAssertEqual(label(el(app, "tiles.over.title")), "Leo wins!")
        XCTAssertTrue(el(app, "tiles.over.home").exists)
    }

    func testPlayAgainSaysSoWhenTheGameIsSwitchedOff() {
        let app = launch("tiles-over", ["-tiles-game-off"])
        XCTAssertTrue(el(app, "tiles.over.again").waitForExistence(timeout: 8))
        el(app, "tiles.over.again").tap()
        XCTAssertTrue(el(app, "tiles.over.off").waitForExistence(timeout: 8), "game_off left no message")
        XCTAssertFalse(el(app, "tiles.over.again").exists, "Play again is still offered")
        XCTAssertTrue(el(app, "tiles.over.home").exists)
        screenshot(app, "tiles-game-off")
    }

    /// Drag timings on the busiest table (25 sets, 22 pieces in the stash): one stash piece
    /// dragged slowly across the whole rug and back. Prints the `[dragperf]` line.
    func testDragPerformanceOnALateTable() {
        let app = launch("tiles-late", speed: 1)
        let from = el(app, "tiles.rack.3").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = set(app, "Row, fish, 1 to 3").coordinate(withNormalizedOffset: CGVector(dx: 2.5, dy: 0.5))
        from.press(forDuration: 0.2, thenDragTo: top, withVelocity: 160, thenHoldForDuration: 0.3)
        XCTAssertTrue(until(5) { (self.value(self.el(app, "tiles.perf")) ?? "-") != "-" })
        let first = value(el(app, "tiles.perf")) ?? "-"
        print("TILES-PERF slow \(first)")
        // And a fast sweep.
        let again = el(app, "tiles.rack.5").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        again.press(forDuration: 0.2, thenDragTo: top, withVelocity: 900, thenHoldForDuration: 0.3)
        XCTAssertTrue(until(5) { (self.value(self.el(app, "tiles.perf")) ?? first) != first })
        print("TILES-PERF fast \(value(el(app, "tiles.perf")) ?? "-")")
    }

    func testCatTowersDemoTableIsUntouched() {
        let app = Live.demo("table")
        app.launch()
        XCTAssertTrue(el(app, "table.debug").waitForExistence(timeout: Live.t(20)))
        XCTAssertFalse(el(app, "tiles.debug").exists)
    }
}
