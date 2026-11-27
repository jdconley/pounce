import XCTest

/// Toy Tumble against a real server (a dev server with `GAMES` listing tumble, the round room of
/// play-api): Home's Toy Tumble card deals a table, House Cats fill two seats, and the game is
/// played to its end. This phone's box plays itself through the scene's own input calls
/// (`-tumble-autoplay`); every round, relay, hit, sync and the game over come from play-api over
/// the room socket. `TUMBLE_LIVE_SHOTS_DIR` in the runner's environment
/// (`TEST_RUNNER_TUMBLE_LIVE_SHOTS_DIR`) also saves each step as a PNG there.
@MainActor
final class ToyTumbleLiveTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "tumble.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        screenshot(app, name)
        guard let dir = ProcessInfo.processInfo.environment["TUMBLE_LIVE_SHOTS_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testOnePersonAndTwoHouseCatsPlayAGame() {
        let app = Live.app()
        app.launchArguments += ["-tumble-autoplay", "-settings.soundOn", "<false/>"]
        app.launch()
        onboard(app)

        let card = el(app, "home.game.tumble")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(10)), "no Toy Tumble card")
        card.tap()
        let seat0 = el(app, "lobby.seat.0")
        XCTAssertTrue(seat0.waitForExistence(timeout: Live.t(20)), "no lobby: the server refused Toy Tumble?")
        XCTAssertTrue(until(15) { seat0.label.contains("on this phone") }, "seat 0 not claimed: \(seat0.label)")
        el(app, "tumble.cats.quick").tap()
        XCTAssertTrue(until(10) { self.el(app, "tumble.cats.quick").isSelected }, "the level didn't take")
        for seat in 1..<3 {
            seatMenu(app, seat: seat, "bot")
            let s = el(app, "lobby.seat.\(seat)")
            XCTAssertTrue(until(10) { s.label.contains("bot") }, "no House Cat in seat \(seat): \(s.label)")
        }
        shot(app, "tumble-1-lobby")
        el(app, "lobby.start").tap()
        let go = el(app, "lobby.start.confirm")
        if go.waitForExistence(timeout: Live.t(3)) { go.tap() }

        XCTAssertTrue(el(app, "screen-tumble").waitForExistence(timeout: Live.t(20)), "no Toy Tumble table")
        XCTAssertTrue(until(20) { self.probe(app)["status"] == "playing" }, "no round: \(probe(app))")
        shot(app, "tumble-2-playing")

        let over = el(app, "tumble.over.title")
        var sawBetween = false
        var rounds = Set<String>()
        let started = Date()
        while !over.exists && Date().timeIntervalSince(started) < Live.t(1500) {
            let p = probe(app)
            if let r = p["r"] { rounds.insert(r) }
            if p["status"] == "between", !sawBetween { sawBetween = true; shot(app, "tumble-3-between") }
            Thread.sleep(forTimeInterval: Live.poll(2))
        }
        XCTAssertTrue(over.exists, "the game never ended: \(probe(app))")
        XCTAssertTrue(sawBetween, "never saw a round end")
        XCTAssertGreaterThanOrEqual(rounds.count, 3, "fewer than three rounds: \(rounds)")
        shot(app, "tumble-4-over")
        el(app, "tumble.over.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home after the game")
    }
}
