import XCTest

/// The Daily Dish end to end against a dev server with `DAILY=on DAILY_TEST=on` (H1 uses its own,
/// `wrangler dev --port 8806`; point the runner at it with `TEST_RUNNER_POUNCE_API_BASE_URL`).
/// The host plays the server's test game ("count to 3 + level"; `-daily-test` shows it on the
/// Dish): Home's treat, the puzzle with its clock, the end screen with the place and Share, and
/// the board. Skipped when the server has the Dish off.
@MainActor
final class DailyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = Live.app()
        app.launchArguments += ["-seed-people", "-daily-test"] + extra
        app.launch()
        return app
    }

    /// Home's test treat, or a skip when this server has no Dish.
    private func treat(_ app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.test")
        if !treat.waitForExistence(timeout: Live.t(20)) {
            throw XCTSkip("the server at \(Live.baseURL) has no Dish (DAILY and DAILY_TEST on?)")
        }
        return treat
    }

    /// "n of target" from the test game's counter.
    private func count(_ app: XCUIApplication) -> (n: Int, target: Int)? {
        let label = el(app, "daily-test-count").label
        let parts = label.split(separator: " ").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    func testTheTestGamePlaysToTheEnd() throws {
        let app = launch()
        try treat(app).tap()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "no puzzle screen")
        XCTAssertTrue(el(app, "daily-test-step").waitForExistence(timeout: Live.t(15)), "the test game never came up")
        XCTAssertTrue(el(app, "daily.clock").exists, "no clock")
        let start = try XCTUnwrap(count(app), "no counter")
        // A hint takes one step, from the server.
        el(app, "daily-test-hint").tap()
        XCTAssertTrue(until(10) { (self.count(app)?.n ?? 0) == start.n + 1 }, "the hint didn't step")
        for _ in 0..<(start.target - start.n - 1) {
            el(app, "daily-test-step").tap()
        }
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Solved")
        XCTAssertTrue(el(app, "daily.end.place").waitForExistence(timeout: Live.t(10)), "no place on the board")
        XCTAssertTrue(el(app, "daily.end.share").exists, "no share")
        el(app, "daily.end.stats").tap()
        XCTAssertTrue(el(app, "screen-dish").waitForExistence(timeout: Live.t(10)), "Stats didn't open the Dish")
        XCTAssertTrue(el(app, "dish.row.me").waitForExistence(timeout: Live.t(10)), "I'm not on the test game's board")
        XCTAssertTrue(el(app, "dish.stats.test").exists, "no stats for the test game")
        // Back on Home, the treat shows the result.
        el(app, "dish.back").tap()
        let done = try treat(app)
        XCTAssertTrue(until(10) { (self.value(done) ?? "").contains(":") }, "Home's treat has no result: \(value(done) ?? "-")")
    }

    func testGivingUpEndsTheRun() throws {
        let app = launch()
        try treat(app).tap()
        XCTAssertTrue(el(app, "daily-test-step").waitForExistence(timeout: Live.t(15)), "the test game never came up")
        el(app, "daily-test-step").tap()
        el(app, "daily.giveup").tap()
        let confirm = app.buttons["daily.giveup.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(5)), "no confirmation")
        confirm.tap()
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "giving up didn't end it")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Gave up")
    }

    /// A server with the Dish off (a 404) shows no Dish on Home.
    func testTheDishHidesWhenOff() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-demo-dish", "off"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(el(app, "home.dish").exists, "the Dish shows while the server has it off")
    }

    /// The demo board: Home's treats, the Dish's cards, tabs, rows and stats.
    func testTheDishScreen() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-demo-dish", "some"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        let open = el(app, "home.dish.open")
        XCTAssertTrue(open.waitForExistence(timeout: Live.t(20)), "no Dish on Home")
        XCTAssertEqual(value(el(app, "home.dish.sniff")), "3 of 6")
        open.tap()
        XCTAssertTrue(el(app, "screen-dish").waitForExistence(timeout: Live.t(10)))
        for game in ["sniff", "nine-lives", "cat-nap", "box-fort"] {
            XCTAssertTrue(el(app, "dish.card.\(game)").exists, "no \(game) card")
        }
        XCTAssertTrue(el(app, "dish.row.me").exists, "I'm not on the Dish")
        el(app, "dish.tab.sniff").tap()
        XCTAssertTrue(el(app, "dish.stats.sniff").waitForExistence(timeout: Live.t(5)), "no Sniff stats")
        XCTAssertTrue(el(app, "dish.row.pr_gramps").exists, "Grandpa's playing row is missing")
        XCTAssertTrue(el(app, "dish.tv").exists, "no Board on TV")
    }
}
