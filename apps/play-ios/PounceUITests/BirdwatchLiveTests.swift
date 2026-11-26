import XCTest

/// Birdwatch against a real server (the dev server, with `GAMES` listing birdwatch): Home's
/// Birdwatch card deals a table, House Cats fill the seats, and the game is played to its end.
/// This phone's seat plays itself through the scene's own calls (`-bird-autoplay`: the least bid
/// or a pass, the put-back, trump, the partner call, the first playable card by two taps); every
/// snapshot, deal, House Cat move and the game over come from play-api over the room socket.
/// `BIRD_LIVE_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_BIRD_LIVE_SHOTS_DIR`) also saves
/// each step as a PNG there.
@MainActor
final class BirdwatchLiveTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "bird.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        screenshot(app, name)
        guard let dir = ProcessInfo.processInfo.environment["BIRD_LIVE_SHOTS_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testFourPlayersOfficial() { play(seats: 4, rules: "official") }
    func testFivePlayersTucker() { play(seats: 5, rules: "tucker") }
    func testSixPlayersFriesen() { play(seats: 6, rules: "friesen") }

    private func play(seats: Int, rules: String) {
        let app = Live.app()
        app.launchArguments += ["-bird-autoplay", "-settings.soundOn", "<false/>"]
        app.launch()
        onboard(app)

        let card = el(app, "home.game.birdwatch")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(10)), "no Birdwatch card")
        card.tap()
        let seat0 = el(app, "lobby.seat.0")
        XCTAssertTrue(seat0.waitForExistence(timeout: Live.t(20)), "no lobby: the server refused Birdwatch?")
        XCTAssertTrue(until(15) { seat0.label.contains("on this phone") }, "seat 0 not claimed: \(seat0.label)")
        XCTAssertTrue(el(app, "lobby.seat.5").exists, "no sixth seat")
        // The rule set, as the host picks it.
        el(app, "bird.rules.\(rules)").tap()
        XCTAssertTrue(until(10) { self.el(app, "bird.rules.\(rules)").isSelected }, "the rule set didn't take")
        for seat in 1..<seats {
            seatMenu(app, seat: seat, "bot")
            let s = el(app, "lobby.seat.\(seat)")
            XCTAssertTrue(until(10) { s.label.contains("bot") }, "no House Cat in seat \(seat): \(s.label)")
        }
        shot(app, "bird-\(seats)-1-lobby")
        let start = el(app, "lobby.start")
        if el(app, "lobby.seat.\(seats)").exists, !(label(el(app, "lobby.seat.\(seats)")) ?? "").contains("Closed") {
            // Open seats left: Start offers to close them.
            start.tap()
            let go = el(app, "lobby.start.confirm")
            if go.waitForExistence(timeout: Live.t(3)) { go.tap() }
        } else {
            start.tap()
        }

        XCTAssertTrue(el(app, "screen-birdwatch").waitForExistence(timeout: Live.t(20)), "no Birdwatch table")
        XCTAssertTrue(until(20) { self.probe(app)["phase"] == "bidding" }, "no deal: \(probe(app))")
        shot(app, "bird-\(seats)-2-bidding")

        // Play it out: this seat plays itself; the House Cats play theirs.
        let over = el(app, "bird.over.title")
        var sawPlay = false, sawBetween = false, sawNest = false
        let started = Date()
        while !over.exists && Date().timeIntervalSince(started) < Live.t(1200) {
            let p = probe(app)
            if p["phase"] == "play", !sawPlay { sawPlay = true; shot(app, "bird-\(seats)-3-play") }
            if p["phase"] == "nest", p["turn"] == "0", !sawNest { sawNest = true; shot(app, "bird-\(seats)-3-nest") }
            if p["phase"] == "between", !sawBetween { sawBetween = true; shot(app, "bird-\(seats)-4-between") }
            Thread.sleep(forTimeInterval: Live.poll(1))
        }
        XCTAssertTrue(over.exists, "the game never ended: \(probe(app))")
        XCTAssertTrue(sawPlay, "never saw a trick played")
        XCTAssertTrue(sawBetween, "never saw a hand end")
        shot(app, "bird-\(seats)-5-over")
        el(app, "bird.over.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home after the game")
    }
}
