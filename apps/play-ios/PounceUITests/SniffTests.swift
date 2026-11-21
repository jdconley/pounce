import XCTest

/// Sniff end to end against a dev server with `DAILY=on` (G3 uses its own, `wrangler dev --port
/// 8804`; point the runner at it with `TEST_RUNNER_POUNCE_API_BASE_URL`): Home's treat, the
/// puzzle, guesses marked by the server, and the end. Each test is a new person, so each plays
/// today's Sniff fresh. Skipped when the server has the Dish off.
@MainActor
final class SniffTests: XCTestCase {
    /// Six allowed words with different letters. Today's answer is secret, so a run ends solved if
    /// one of them is it, and missed otherwise.
    private static let words = ["crane", "sloth", "pudgy", "witch", "femur", "balky"]
    private static let marks = ["right spot", "elsewhere", "not in the word"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// A new person's app on today's Sniff. `realTime`: animations at their real speed (a note on
    /// screen for its real 1.4 s), not the tests' faster pace.
    private func open(realTime: Bool = false) throws -> XCUIApplication {
        let app = Live.app()
        if realTime { app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset"] }
        app.launchArguments += ["-seed-people"]
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.sniff")
        guard treat.waitForExistence(timeout: Live.t(20)) else {
            throw XCTSkip("the server at \(Live.baseURL) has no Dish or no Sniff (DAILY on?)")
        }
        treat.tap()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "no puzzle screen")
        XCTAssertTrue(el(app, "sniff.key.a").waitForExistence(timeout: Live.t(15)), "Sniff never came up")
        return app
    }

    private func type(_ app: XCUIApplication, _ word: String) {
        for letter in word { el(app, "sniff.key.\(letter)").tap() }
        el(app, "sniff.send").tap()
    }

    /// How many of row `row`'s tags carry a mark (its label lists each tag's letter and mark).
    private func marked(_ app: XCUIApplication, row: Int) -> Int {
        let element = el(app, "sniff.row.\(row)")
        guard element.exists else { return 0 }
        let label = element.label
        return Self.marks.reduce(0) { $0 + label.components(separatedBy: $1).count - 1 }
    }

    func testSniffPlaysToTheEnd() throws {
        let app = try open()
        var solved = false
        for (row, word) in Self.words.enumerated() {
            type(app, word)
            // The guess that ends the run brings up the end screen over the board.
            let last = row == Self.words.count - 1
            XCTAssertTrue(
                until(10) { self.marked(app, row: row) == 5 || (last && self.el(app, "daily.end").exists) },
                "\(word) never came back marked")
            if !el(app, "daily.end").exists, el(app, "sniff.row.\(row)").label.components(separatedBy: "right spot").count - 1 == 5 {
                solved = true
            }
            if el(app, "daily.end").exists { break }
        }
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        let headline = el(app, "daily.end.headline").label
        XCTAssertTrue(["Solved", "Missed"].contains(headline), "ended as \(headline)")
        if solved { XCTAssertEqual(headline, "Solved") }
        XCTAssertTrue(el(app, "daily.end.share").waitForExistence(timeout: Live.t(10)), "no share")
    }

    func testAnUnknownWordShakesAndIsNeverSent() throws {
        let app = try open(realTime: true)
        type(app, "zzzzz")
        XCTAssertTrue(el(app, "sniff.note").waitForExistence(timeout: Live.t(5)), "no note for an unknown word")
        XCTAssertEqual(el(app, "sniff.note").label, "Not a word")
        XCTAssertEqual(marked(app, row: 0), 0, "an unknown word was marked")
        XCTAssertTrue(el(app, "sniff.row.0").label.hasPrefix("Z"), "the row isn't still typed: \(el(app, "sniff.row.0").label)")
        // The row is still typed: delete it and send a real word.
        for _ in 0..<5 { el(app, "sniff.delete").tap() }
        type(app, "crane")
        XCTAssertTrue(until(10) { self.marked(app, row: 0) == 5 }, "crane never came back marked")
    }
}
