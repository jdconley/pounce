import XCTest

/// Task 24 multi-simulator game, run by `scripts/multi-sim.sh` on two simulators at once against
/// the dev server. A `pounce-e2e full` host plays a game with four seats on its own device plus a
/// bot; once a seat reaches phase 9 it moves seats to the phones with move links
/// (`--move-seats`, written to `move.txt` in the runner's `POUNCE_SHARED_DIR`, a Mac folder the
/// simulators can read). Each simulator runs `testMovedSeats` with its seats in
/// `POUNCE_MOVE_SEATS` ("1,2" on A: two people on one phone, pass and play; "3" on B), opens
/// those links, and plays its seats by taps (draw, discard; the curtain is held through) to the
/// game-over overlay, screenshotting the curtain, the first round over and the game over.
final class MultiSimTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMovedSeats() throws {
        let env = ProcessInfo.processInfo.environment
        guard let shared = env["POUNCE_SHARED_DIR"], let seatList = env["POUNCE_MOVE_SEATS"] else {
            throw XCTSkip("run by scripts/multi-sim.sh (POUNCE_SHARED_DIR, POUNCE_MOVE_SEATS)")
        }
        let seats = seatList.split(separator: ",").map(String.init)
        let tag = "seats" + seats.joined()
        let restoreQuiescence = Quiescence.disable()
        addTeardownBlock { @MainActor in restoreQuiescence() }
        let app = Live.app()
        app.launch()
        onboard(app)
        var links: [String: String] = [:]
        XCTAssertTrue(until(3600) {
            let text = (try? String(contentsOfFile: shared + "/move.txt", encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ")
                if parts.count == 2 { links[String(parts[0])] = String(parts[1]) }
            }
            return seats.allSatisfy { links[$0] != nil }
        }, "no move links for seats \(seats)")
        for seat in seats {
            app.open(URL(string: links[seat]!)!)
            // A custom-scheme link can stop at the system's "Open in Pounce?" prompt.
            let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
            if open.waitForExistence(timeout: Live.t(5)) { open.tap() }
            XCTAssertTrue(until(60) { self.el(app, "screen-table").exists || self.el(app, "screen-curtain").exists },
                          "the move link for seat \(seat) didn't open the table")
            Thread.sleep(forTimeInterval: 2)
        }
        save(app, shared: shared, "\(tag)-arrived")
        playToGameOver(app, tag: tag, shared: shared)
    }

    @MainActor
    private func save(_ app: XCUIApplication, shared: String, _ name: String) {
        screenshot(app, name)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shared)/\(name).png"))
    }

    /// Plays this phone's turns by taps (holding the curtain through) until the game-over
    /// overlay; screenshots the first round over and the game over into `shared`.
    @MainActor
    private func playToGameOver(_ app: XCUIApplication, tag: String, shared: String) {
        let deadline = Date().addingTimeInterval(Live.t(4 * 3600))
        let gameOver = el(app, "gameover.home")
        var turns = 0, rounds = Set<Int>(), roundOverShot = false, curtains = 0, curtainNames = Set<String>()
        func save(_ name: String) { self.save(app, shared: shared, "\(tag)-\(name)") }
        // One whole-app snapshot per poll, every 2 s (see `playTurnByTaps`).
        while Date() < deadline {
            guard let snap = UISnap(app) else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            if snap.exists("gameover.home") { break }
            if snap.exists("priming.notNow") {
                dismissPriming(app, snap)
                continue
            }
            if curtains == 0, snap.exists("curtain.hold") { save("curtain") }
            if let name = holdCurtain(app, snap) {
                curtainNames.insert(name)
                curtains += 1
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            guard let d = snap.debug else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            rounds.insert(d.round)
            if d.status == "roundOver", !roundOverShot {
                save("roundover-\(d.round)")
                roundOverShot = true
            }
            if d.status == "gameOver" {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            if playTurnByTaps(app, snap) {
                turns += 1
                if turns == 1 { save("first-turn") }
            } else {
                Thread.sleep(forTimeInterval: 2)
            }
        }
        XCTAssertTrue(gameOver.waitForExistence(timeout: Live.t(30)), "no game over within the time limit (rounds \(rounds.sorted()))")
        save("gameover")
        let summary = "\(tag): \(turns) turns by taps, rounds seen \(rounds.sorted()), curtains held \(curtains) \(curtainNames.sorted())"
        print("[multisim] \(summary)")
        try? summary.write(toFile: "\(shared)/\(tag)-summary.txt", atomically: true, encoding: .utf8)
        let note = XCTAttachment(string: summary)
        note.lifetime = .keepAlways
        add(note)
    }
}
