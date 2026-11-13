import XCTest

/// The tile game against a real server (the dev server, with `GAMES=tiles`): Home's tile card
/// deals a table, a House Cat takes a seat, and the game is played to its end with the same
/// taps a person makes. Nothing here is canned: every snapshot, move and the game over
/// come from play-api over the room socket.
/// `TILES_LIVE_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_TILES_LIVE_SHOTS_DIR`) also
/// saves each step as a PNG there.
@MainActor
final class TilesLiveTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The tile table's DEBUG probe (`tiles.debug`) as key/value pairs.
    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "tiles.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        screenshot(app, name)
        guard let dir = ProcessInfo.processInfo.environment["TILES_LIVE_SHOTS_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testATileGameAgainstAHouseCatIsPlayedToItsEnd() {
        let app = Live.app()
        app.launch()
        onboard(app)

        // Home deals a tile table from its shelf card.
        let card = el(app, "home.game.tiles")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(10)), "no tile game card")
        XCTAssertFalse((label(card) ?? "").contains("coming soon"), "still coming soon: \(label(card) ?? "")")
        shot(app, "1-home")
        card.tap()
        let seat0 = el(app, "lobby.seat.0")
        XCTAssertTrue(seat0.waitForExistence(timeout: Live.t(20)), "no lobby: the server refused the tile game?")
        XCTAssertTrue(until(15) { seat0.label.contains("on this phone") }, "seat 0 not claimed: \(seat0.label)")
        // Four seats at most for this game.
        XCTAssertTrue(el(app, "lobby.seat.3").exists, "no fourth seat")
        XCTAssertFalse(el(app, "lobby.seat.4").exists, "a fifth seat at a four-seat game")
        seatMenu(app, seat: 1, "bot")
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(10) { seat1.label.contains("bot") }, "no bot on seat 1: \(seat1.label)")
        shot(app, "2-lobby")
        el(app, "lobby.start").tap()

        // The table, dealt by the server: 14 pieces each.
        XCTAssertTrue(el(app, "tiles.turn").waitForExistence(timeout: Live.t(20)), "no tile table")
        XCTAssertTrue(until(20) { self.probe(app)["rack"] == "14" || self.probe(app)["rack"] == "15" },
                      "no deal: \(probe(app))")
        shot(app, "3-dealt")

        // Play it out: on my turn, tap the turn button (Draw, or Pass once the box is empty); the
        // House Cat plays its own turns. The game ends when someone empties their stash or nobody
        // can move.
        let over = el(app, "tiles.over.title")
        var myTurns = 0
        var sawBotMove = false
        var lastSets = probe(app)["sets"] ?? "0"
        let started = Date()
        while !over.exists && Date().timeIntervalSince(started) < Live.t(600) {
            let p = probe(app)
            if p["sets"] != lastSets { sawBotMove = true; lastSets = p["sets"] ?? lastSets }
            if p["turn"] == "draw" || p["turn"] == "pass" {
                let before = p["rack"]
                el(app, "tiles.turn").tap()
                myTurns += 1
                if myTurns == 1 { shot(app, "4-first-draw") }
                // The move went: the rack grew (a draw), or the turn moved on (a pass).
                XCTAssertTrue(until(20) {
                    let q = self.probe(app)
                    return over.exists || q["rack"] != before || (q["turn"] != "draw" && q["turn"] != "pass")
                }, "my move never landed: \(probe(app))")
                if myTurns == 20 { shot(app, "5-mid-game") }
            } else {
                Thread.sleep(forTimeInterval: Live.poll(0.5))
            }
        }
        XCTAssertTrue(over.exists, "the game never ended after \(myTurns) turns: \(probe(app))")
        XCTAssertGreaterThan(myTurns, 0, "I never had a turn")
        XCTAssertTrue(sawBotMove, "the House Cat never put a set on the rug")
        shot(app, "6-game-over")

        // Home again, and the finished table is there.
        el(app, "tiles.over.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home after the game")
        shot(app, "7-home-after")
    }
}
