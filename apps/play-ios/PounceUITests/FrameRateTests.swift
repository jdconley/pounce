import XCTest

/// Frame times while playing (`docs/main-thread.md`): the tables ask for the screen's top rate
/// (120 on ProMotion), and while a card or a piece moves the frames stay within budget, with no
/// main-thread hang. Each test plays at normal speed on a demo table (no server) and prints a
/// `FRAMES` line: the table's rendered frames, the main thread's (the watchdog's display link)
/// and hangs, over the gameplay window only.
///
/// Budgets, loose enough for a busy simulator, tight enough to catch a real stall:
/// - the table's 95th percentile frame within 1.5 frame times,
/// - at most 2% of its frames (and 3 at least) over 16.7 ms,
/// - the same for the main thread's frames,
/// - no hang over 100 ms.
@MainActor
final class FrameRateTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Cat Tower's hit table (`-demo hit`): a Yarn dragged onto the start of Leo's run, and the 8
    /// onto its end, each with the hit animation.
    func testCatTowerPlaysAtTheTopFrameRate() {
        let app = Live.demo("hit", speed: 1)
        app.launch()
        let run = "table.group.1.1"
        XCTAssertTrue(el(app, "table.hit").waitForExistence(timeout: Live.t(10)))
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        XCTAssertTrue(el(app, run).waitForExistence(timeout: 5))
        let before = gameplayBaseline(app)

        dragCard(app, "Yarn, wild", toStartOf: run)
        XCTAssertTrue(until(5) { self.label(el(app, run))?.contains("Yarn, wild; 4, gray") == true }, label(el(app, run)) ?? "-")
        XCTAssertTrue(until(3) { self.handIndex(app, "8, gray") != nil })
        dragCard(app, "8, gray", toStartOf: run)
        XCTAssertTrue(until(5) { self.label(el(app, run))?.hasSuffix("7, calico; 8, gray") == true }, label(el(app, run)) ?? "-")
        // A tap on the deck (not my draw step: the table shakes its head) and the hand settling.
        el(app, "table.deck").tap()
        Thread.sleep(forTimeInterval: 1)

        check(app, "cat-tower", since: before)

        // Idle: once nothing moves the view pauses, so the table draws nothing (`IdleRenderTests`
        // gates that; this prints the rate). A cat blink may land in the window.
        let frames = el(app, "table.frames")
        Thread.sleep(forTimeInterval: 2)
        let idleFrom = Int(value(frames) ?? "") ?? 0
        Thread.sleep(forTimeInterval: 5)
        let idle = (Int(value(frames) ?? "") ?? 0) - idleFrom
        print(String(format: "FRAMES cat-tower idle: %d table frames in 5 s (%.1f fps)", idle, Double(idle) / 5))
    }

    /// Tuna Tiles (`-demo tiles`): a piece dragged onto a row, back to the stash, and onto it again.
    func testTunaTilesPlaysAtTheTopFrameRate() {
        let app = launchTiles("tiles")
        let before = gameplayBaseline(app)

        dragPiece(app, "13, mouse", to: "Row, mouse, 10 to 12")
        XCTAssertTrue(until(5) { self.find(app, "tiles.set.", label: "Row, mouse, 10 to 13") != nil })
        // Back to the stash: the 13 is the last of the row's four pieces.
        if let row = find(app, "tiles.set.", label: "Row, mouse, 10 to 13") {
            let piece = row.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            let stash = el(app, "tiles.rack.0").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            piece.press(forDuration: 0.15, thenDragTo: stash, withVelocity: 500, thenHoldForDuration: 0.4)
        }
        XCTAssertTrue(until(5) { self.find(app, "tiles.set.", label: "Row, mouse, 10 to 12") != nil })
        dragPiece(app, "13, mouse", to: "Row, mouse, 10 to 12")
        XCTAssertTrue(until(5) { self.find(app, "tiles.set.", label: "Row, mouse, 10 to 13") != nil })
        Thread.sleep(forTimeInterval: 1)

        check(app, "tuna-tiles", since: before)
    }

    /// Tuna Tiles' busiest table (`-demo tiles-late`: 25 sets, 22 pieces in the stash): one slow
    /// and one fast sweep across the whole rug, with the drag's own timings (`tiles.perf`).
    func testTunaTilesLateTableDragsAtTheTopFrameRate() {
        let app = launchTiles("tiles-late")
        let before = gameplayBaseline(app)

        let perf = el(app, "tiles.perf")
        let top = find(app, "tiles.set.", label: "Row, fish, 1 to 3")?.coordinate(withNormalizedOffset: CGVector(dx: 2.5, dy: 0.5))
        guard let top else { return XCTFail("no row of fish 1 to 3 on the late table") }
        el(app, "tiles.rack.3").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: top, withVelocity: 160, thenHoldForDuration: 0.3)
        XCTAssertTrue(until(5) { (self.value(perf) ?? "-") != "-" })
        let slow = value(perf) ?? "-"
        el(app, "tiles.rack.5").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: top, withVelocity: 900, thenHoldForDuration: 0.3)
        XCTAssertTrue(until(5) { (self.value(perf) ?? slow) != slow })
        print("FRAMES tiles-late dragperf slow \(slow)")
        print("FRAMES tiles-late dragperf fast \(value(perf) ?? "-")")
        Thread.sleep(forTimeInterval: 1)

        check(app, "tuna-tiles-late", since: before)
    }

    // MARK: the gate

    private func check(_ app: XCUIApplication, _ name: String, since before: Watchdog, file: StaticString = #filePath, line: UInt = #line) {
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away", file: file, line: line) }
        let window = after - before
        let report = window.report(name)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-\(name)"
        note.lifetime = .keepAlways
        add(note)

        XCTAssertGreaterThan(window.screen, 0, report, file: file, line: line)
        XCTAssertEqual(window.table, window.screen, "the table doesn't ask for the screen's top rate: \(report)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.tableFrames.count, 30, "the table hardly rendered while it played: \(report)", file: file, line: line)
        Self.assertWithinBudget(window.tableFrames, "table", report, file: file, line: line)
        Self.assertWithinBudget(window.link, "main thread", report, file: file, line: line)
        XCTAssertFalse(window.hangs > 0 && window.hangMaxMs > 100 * Live.scale, "a main-thread hang over 100 ms during gameplay: \(report)", file: file, line: line)
    }

    /// The 95th percentile within 1.5 frame times, and at most 2% (3 at least) over 16.7 ms.
    static func assertWithinBudget(_ frames: Watchdog.Frames, _ what: String, _ report: String, file: StaticString = #filePath, line: UInt = #line) {
        guard frames.count > 0 else { return }
        XCTAssertLessThanOrEqual(frames.percentile(0.95), frames.frameMs * 1.5 + Watchdog.Frames.bucketMs,
                                 "\(what): 95th percentile frame over budget: \(report)", file: file, line: line)
        XCTAssertLessThanOrEqual(frames.slow, max(3, frames.count / 50), "\(what): too many frames over 16.7 ms: \(report)", file: file, line: line)
    }

    // MARK: helpers

    private func launchTiles(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo, speed: 1)
        app.launch()
        XCTAssertTrue(el(app, "tiles.debug").waitForExistence(timeout: Live.t(20)), "the tile game's table never came up")
        return app
    }

    private func find(_ app: XCUIApplication, _ prefix: String, label: String) -> XCUIElement? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", prefix, label))
        return query.count > 0 ? query.element(boundBy: 0) : nil
    }

    private func dragPiece(_ app: XCUIApplication, _ piece: String, to set: String) {
        guard let from = find(app, "tiles.rack.", label: piece), let to = find(app, "tiles.set.", label: set) else {
            return XCTFail("no \(piece) in the stash or no \(set) on the rug")
        }
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: 500, thenHoldForDuration: 0.4)
    }

    private func handIndex(_ app: XCUIApplication, _ card: String) -> Int? {
        var i = 0
        while let l = label(el(app, "table.hand.\(i)")) {
            if l == card { return i }
            i += 1
        }
        return nil
    }

    /// Drags the hand card `card` a quarter of the way into group `id` from its start (as
    /// `HitTests` does: the laid zone grows 1.1x about the piles' center while a card is held).
    private func dragCard(_ app: XCUIApplication, _ card: String, toStartOf id: String) {
        guard let index = handIndex(app, card) else { return XCTFail("\(card) is not in the hand") }
        let f = el(app, id).frame
        let deck = el(app, "table.deck").frame, discard = el(app, "table.discard").frame
        let center = CGPoint(x: (deck.midX + discard.midX) / 2, y: deck.midY)
        let x = f.minX + f.width * 0.25
        let aim = CGPoint(x: center.x + (x - center.x) * 1.1, y: center.y + (f.midY - center.y) * 1.1)
        let h = el(app, "table.hand.\(index)").frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: h.minX + min(h.width, 24) / 2, dy: h.midY + 10))
        start.press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: aim.x, dy: aim.y)), withVelocity: 500,
                    thenHoldForDuration: 0.6)
    }
}
