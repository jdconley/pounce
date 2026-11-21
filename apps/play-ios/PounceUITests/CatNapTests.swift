import XCTest

/// Cat Nap end to end against a dev server with `DAILY=on` (G4 uses its own, `wrangler dev --port
/// 8805`; point the runner at it with `TEST_RUNNER_POUNCE_API_BASE_URL`). Today's quilt from the
/// server: a tap cycles a cell, a drag marks a row "no cat" in one move, and hints place the
/// server's cats until the run ends solved. The player never learns the solution any other way,
/// so the hints are how a test reaches the end. Skipped when the server has the Dish off.
@MainActor
final class CatNapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = Live.app()
        app.launchArguments += ["-seed-people"]
        app.launch()
        return app
    }

    /// Opens Cat Nap from Home's treat, or skips when this server has no Dish.
    private func open(_ app: XCUIApplication) throws -> Int {
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.cat-nap")
        if !treat.waitForExistence(timeout: Live.t(20)) {
            throw XCTSkip("the server at \(Live.baseURL) has no Cat Nap (DAILY on?)")
        }
        treat.tap()
        XCTAssertTrue(el(app, "catnap.quilt").waitForExistence(timeout: Live.t(15)), "the quilt never came up")
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'catnap.cell.'")).count
        let n = Int(Double(cells).squareRoot())
        XCTAssertTrue((5...9).contains(n) && n * n == cells, "a quilt of \(cells) cells")
        return n
    }

    private func cell(_ app: XCUIApplication, _ i: Int) -> XCUIElement { el(app, "catnap.cell.\(i)") }

    func testCatNapPlaysToTheEnd() throws {
        let app = launch()
        let n = try open(app)
        XCTAssertTrue(el(app, "daily.clock").exists, "no clock")

        // A tap cycles a cell: no cat, a cat, empty.
        cell(app, 0).tap()
        XCTAssertTrue(until(5) { self.cell(app, 0).label.hasSuffix(", no cat") }, "a tap didn't mark no cat: \(cell(app, 0).label)")
        cell(app, 0).tap()
        XCTAssertTrue(until(5) { self.cell(app, 0).label.hasSuffix(", cat") }, "a second tap didn't place a cat")
        cell(app, 0).tap()
        XCTAssertTrue(until(5) { !self.cell(app, 0).label.contains("cat,") && !self.cell(app, 0).label.hasSuffix("cat") }, "a third tap didn't clear it")

        // A drag along the bottom row marks it "no cat".
        let last = n * (n - 1)
        let from = cell(app, last).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = cell(app, last + n - 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertTrue(until(5) { self.cell(app, last + n - 1).label.hasSuffix(", no cat") }, "the drag didn't mark the row")

        // Hints place the server's cats, one each, until the quilt is solved.
        let hint = el(app, "catnap.hint")
        for i in 0..<n {
            if el(app, "daily.end").exists { break }
            XCTAssertTrue(until(10) { hint.isEnabled }, "Hint stayed off before hint \(i + 1)")
            hint.tap()
            let locked = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'catnap.cell.' AND label ENDSWITH ', cat, locked'"))
            XCTAssertTrue(until(10) { locked.count == i + 1 || self.el(app, "daily.end").exists }, "hint \(i + 1) placed no cat")
        }
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Solved")
        XCTAssertTrue(el(app, "daily.end.place").waitForExistence(timeout: Live.t(10)), "no place on the board")
    }
}
